import Foundation

/// Everything that defines a pending daily-summary notification. Two descriptors that are equal
/// need no rescheduling. Trigger fields are wall-clock components in `timeZoneIdentifier`, so a
/// daylight-saving transition between scheduling and delivery never shifts the local delivery time.
public struct DailyNotificationDescriptor: Hashable, Sendable {
    public let identifier: String
    public let locationID: UUID
    public let title: String
    public let body: String
    public let playSound: Bool
    public let year: Int
    public let month: Int
    public let day: Int
    public let hour: Int
    public let minute: Int
    public let timeZoneIdentifier: String

    public init(
        identifier: String,
        locationID: UUID,
        title: String,
        body: String,
        playSound: Bool,
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int,
        timeZoneIdentifier: String
    ) {
        self.identifier = identifier
        self.locationID = locationID
        self.title = title
        self.body = body
        self.playSound = playSound
        self.year = year
        self.month = month
        self.day = day
        self.hour = hour
        self.minute = minute
        self.timeZoneIdentifier = timeZoneIdentifier
    }
}

public enum DailyNotificationDescriptorBuilder: Sendable {
    /// Desired set of pending daily notifications. Empty when notifications are disabled or not authorized.
    public static func descriptors(
        state: SharedAppState,
        snapshots: [UUID: CachedLocationSnapshot],
        preferences: NotificationPreferences,
        isAuthorized: Bool,
        now: Date = Date(),
        locale: Locale = .autoupdatingCurrent
    ) -> [DailyNotificationDescriptor] {
        guard preferences.notificationsEnabled, isAuthorized else { return [] }

        var result: [DailyNotificationDescriptor] = []
        for location in state.locations {
            let rule = preferences.rule(for: location.id).dailySummary
            guard rule.enabled,
                  let snapshot = snapshots[location.id],
                  let bundle = snapshot.bundle,
                  let timeZone = location.timeZone else {
                continue
            }
            let plans = DailyNotificationSchedulePlanner.plans(
                location: location,
                rule: rule,
                now: now,
                dayCount: max(2, location.forecastDays)
            )
            for plan in plans {
                guard let draft = DailySummaryContentBuilder.content(
                    location: location,
                    bundle: bundle,
                    deliveryDate: plan.deliveryDate,
                    locale: locale
                ) else { continue }
                let components = DailyNotificationSchedulePlanner.dateComponents(for: plan, timeZone: timeZone)
                result.append(
                    DailyNotificationDescriptor(
                        identifier: plan.identifier,
                        locationID: location.id,
                        title: draft.title,
                        body: draft.body,
                        playSound: preferences.playSound,
                        year: components.year ?? 0,
                        month: components.month ?? 0,
                        day: components.day ?? 0,
                        hour: components.hour ?? 0,
                        minute: components.minute ?? 0,
                        timeZoneIdentifier: timeZone.identifier
                    )
                )
            }
        }
        return result
    }
}

public struct DailyNotificationReconcilePlan: Equatable, Sendable {
    /// New identifiers, or identifiers whose content/trigger changed (adding replaces in place).
    public let toAdd: [DailyNotificationDescriptor]
    /// Pending daily identifiers that are no longer wanted.
    public let toRemove: [String]
}

public enum DailyNotificationReconciler: Sendable {
    public static func reconcile(
        desired: [DailyNotificationDescriptor],
        pending: [DailyNotificationDescriptor]
    ) -> DailyNotificationReconcilePlan {
        // De-duplicate desired by identifier (last wins) so a duplicate can never be scheduled twice.
        var desiredByID: [String: DailyNotificationDescriptor] = [:]
        var order: [String] = []
        for descriptor in desired {
            if desiredByID[descriptor.identifier] == nil { order.append(descriptor.identifier) }
            desiredByID[descriptor.identifier] = descriptor
        }
        var pendingByID: [String: DailyNotificationDescriptor] = [:]
        for descriptor in pending { pendingByID[descriptor.identifier] = descriptor }

        let toAdd = order.compactMap { id -> DailyNotificationDescriptor? in
            guard let want = desiredByID[id] else { return nil }
            return pendingByID[id] == want ? nil : want
        }
        let toRemove = pendingByID.keys.filter { desiredByID[$0] == nil }.sorted()
        return DailyNotificationReconcilePlan(toAdd: toAdd, toRemove: toRemove)
    }
}

/// Abstraction over the system notification center for daily summaries.
public protocol DailyNotificationScheduling: Sendable {
    /// Pending requests whose identifier starts with `DailyNotificationSchedulePlanner.identifierPrefix`.
    /// Requests whose content cannot be interpreted should be returned with empty content so they are replaced.
    func pendingDailyDescriptors() async -> [DailyNotificationDescriptor]
    /// Adds or replaces (same identifier) a pending request.
    func schedule(_ descriptor: DailyNotificationDescriptor) async throws
    func removePending(identifiers: [String]) async
}

public struct DailyNotificationApplyResult: Equatable, Sendable {
    public var added: Int = 0
    public var removed: Int = 0
    public var retained: Int = 0
    public var failedIdentifiers: [String] = []
}

/// Serializes daily-notification reconciliation. Overlapping requests are coalesced: while a pass
/// is running, only the most recent desired set is kept and applied afterwards, so an older
/// (stale) request can never overwrite a newer one. Adds happen before removals and a failed add
/// never removes the previously scheduled notification with the same identifier.
public actor DailyNotificationScheduler {
    private let scheduling: any DailyNotificationScheduling
    private var isRunning = false
    private var queuedDesired: [DailyNotificationDescriptor]?
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []
    private var lastResult = DailyNotificationApplyResult()

    public init(scheduling: any DailyNotificationScheduling) {
        self.scheduling = scheduling
    }

    /// Returns after the desired set (or a newer one that superseded it) has been applied.
    @discardableResult
    public func apply(desired: [DailyNotificationDescriptor]) async -> DailyNotificationApplyResult {
        if isRunning {
            queuedDesired = desired
            await withCheckedContinuation { idleWaiters.append($0) }
            return lastResult
        }
        isRunning = true
        var current = desired
        while true {
            lastResult = await reconcileOnce(desired: current)
            if let next = queuedDesired {
                queuedDesired = nil
                current = next
            } else {
                break
            }
        }
        isRunning = false
        let waiters = idleWaiters
        idleWaiters = []
        waiters.forEach { $0.resume() }
        return lastResult
    }

    private func reconcileOnce(desired: [DailyNotificationDescriptor]) async -> DailyNotificationApplyResult {
        let pending = await scheduling.pendingDailyDescriptors()
        let plan = DailyNotificationReconciler.reconcile(desired: desired, pending: pending)
        var result = DailyNotificationApplyResult()
        let desiredIDs = Set(desired.map(\.identifier))
        result.retained = desiredIDs.count - plan.toAdd.count

        for descriptor in plan.toAdd {
            do {
                try await scheduling.schedule(descriptor)
                result.added += 1
            } catch {
                result.failedIdentifiers.append(descriptor.identifier)
                // A previously pending request with this identifier is left untouched.
                if pending.contains(where: { $0.identifier == descriptor.identifier }) {
                    result.retained += 1
                }
            }
        }
        if !plan.toRemove.isEmpty {
            await scheduling.removePending(identifiers: plan.toRemove)
            result.removed = plan.toRemove.count
        }
        return result
    }
}

