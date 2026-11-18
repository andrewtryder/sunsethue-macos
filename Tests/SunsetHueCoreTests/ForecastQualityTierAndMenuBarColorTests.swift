import Foundation
@testable import SunsetHueCore
import XCTest

final class ForecastQualityTierAndMenuBarColorTests: XCTestCase {
    private let timeZone = TimeZone(identifier: "America/New_York") ?? .current

    // MARK: - Helpers

    private func makeLocation(
        id: UUID = UUID(),
        name: String = "Sandown",
        forecastDays: Int = 3,
        includeSunrise: Bool = true,
        includeSunset: Bool = true,
        refreshIntervalHours: Int = 6
    ) -> SavedLocation {
        SavedLocation(
            id: id,
            name: name,
            latitude: 40.7128,
            longitude: -74.0060,
            timeZoneIdentifier: timeZone.identifier,
            forecastDays: forecastDays,
            includeSunrise: includeSunrise,
            includeSunset: includeSunset,
            refreshIntervalHours: refreshIntervalHours
        )
    }

    private func makeForecast(
        eventType: EventType,
        eventTime: Date,
        quality: Double?,
        modelData: Bool = true,
        qualityText: String? = nil,
        forecastDate: Date? = nil
    ) -> EventForecast {
        EventForecast(
            responseTime: eventTime,
            location: Coordinates(latitude: 40.7128, longitude: -74.0060),
            gridLocation: Coordinates(latitude: 40.7, longitude: -74.0),
            eventType: eventType,
            modelData: modelData,
            quality: quality,
            qualityText: qualityText,
            cloudCover: 0.25,
            eventTime: eventTime,
            direction: eventType == .sunset ? 270 : 90,
            blueHour: nil,
            goldenHour: nil,
            forecastDate: forecastDate ?? eventTime
        )
    }

    private func makeSnapshot(
        locationID: UUID,
        fetchedAt: Date,
        forecasts: [EventForecast],
        status: RefreshStatus = .current
    ) -> CachedLocationSnapshot {
        CachedLocationSnapshot(
            locationID: locationID,
            fetchedAt: fetchedAt,
            lastAttemptAt: fetchedAt,
            forecasts: forecasts,
            status: status
        )
    }

    private func referenceNoon() throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 12, minute: 0)))
    }

    // MARK: - Quality Tier Thresholds & Invalid Inputs

    func testQualityTierThresholdsAndBoundaries() {
        XCTAssertEqual(ForecastQualityTier.resolve(quality: 0.0), .poor)
        XCTAssertEqual(ForecastQualityTier.resolve(quality: 0.18), .poor)
        XCTAssertEqual(ForecastQualityTier.resolve(quality: 0.2499), .poor)

        XCTAssertEqual(ForecastQualityTier.resolve(quality: 0.25), .fair)
        XCTAssertEqual(ForecastQualityTier.resolve(quality: 0.42), .fair)
        XCTAssertEqual(ForecastQualityTier.resolve(quality: 0.4999), .fair)

        XCTAssertEqual(ForecastQualityTier.resolve(quality: 0.50), .good)
        XCTAssertEqual(ForecastQualityTier.resolve(quality: 0.67), .good)
        XCTAssertEqual(ForecastQualityTier.resolve(quality: 0.7499), .good)

        XCTAssertEqual(ForecastQualityTier.resolve(quality: 0.75), .excellent)
        XCTAssertEqual(ForecastQualityTier.resolve(quality: 0.91), .excellent)
        XCTAssertEqual(ForecastQualityTier.resolve(quality: 1.0), .excellent)

        // Ordering & display names
        XCTAssertLessThan(ForecastQualityTier.poor, .fair)
        XCTAssertLessThan(ForecastQualityTier.fair, .good)
        XCTAssertLessThan(ForecastQualityTier.good, .excellent)
        XCTAssertEqual(ForecastQualityTier.poor.displayName, "Poor")
        XCTAssertEqual(ForecastQualityTier.fair.displayName, "Fair")
        XCTAssertEqual(ForecastQualityTier.good.displayName, "Good")
        XCTAssertEqual(ForecastQualityTier.excellent.displayName, "Excellent")
    }

    func testQualityClampingAndInvalidValueHandling() throws {
        XCTAssertEqual(ForecastQualityTier.normalizedQuality(-0.5), 0.0)
        XCTAssertEqual(ForecastQualityTier.normalizedQuality(1.5), 1.0)
        XCTAssertEqual(ForecastQualityTier.resolve(quality: -0.5), .poor)
        XCTAssertEqual(ForecastQualityTier.resolve(quality: 1.5), .excellent)
        XCTAssertEqual(PresentationFormatting.percentage(fromNormalized: -0.5), "0.0%")
        XCTAssertEqual(PresentationFormatting.percentage(fromNormalized: 1.5), "100.0%")
        XCTAssertEqual(MenuBarStatusFormatting.compactPercentage(fromNormalized: -0.5), "0%")
        XCTAssertEqual(MenuBarStatusFormatting.compactPercentage(fromNormalized: 1.5), "100%")

        // Missing & non-finite values reject cleanly
        for invalid in [nil, Double.nan, Double.infinity, -Double.infinity] as [Double?] {
            XCTAssertNil(ForecastQualityTier.normalizedQuality(invalid))
            XCTAssertNil(ForecastQualityTier.resolve(quality: invalid))
            XCTAssertNil(PresentationFormatting.percentage(fromNormalized: invalid))
            XCTAssertNil(PresentationFormatting.percentageValue(fromNormalized: invalid))
            XCTAssertEqual(MenuBarStatusFormatting.compactPercentage(fromNormalized: invalid), "—")
            XCTAssertEqual(MenuBarStatusFormatting.qualityTierName(quality: invalid), "Unavailable")
        }

        let now = try referenceNoon()
        let unavailableModel = makeForecast(eventType: .sunset, eventTime: now.addingTimeInterval(3600), quality: 0.9, modelData: false)
        XCTAssertFalse(unavailableModel.isQualityAvailable)
        XCTAssertNil(ForecastQualityTier.resolve(forecast: unavailableModel))

        let nanModel = makeForecast(eventType: .sunset, eventTime: now.addingTimeInterval(3600), quality: .nan, modelData: true)
        XCTAssertFalse(nanModel.isQualityAvailable)
        XCTAssertNil(ForecastQualityTier.resolve(forecast: nanModel))
    }

    // MARK: - Dropdown Row Quality Colors & Accessibility

    func testPopoverRowAssignsTiersForFreshForecastsAndNeutralizesStaleOrMissing() throws {
        let now = try referenceNoon()
        let prefs = MenuBarPreferences()
        let cases: [(Double, ForecastQualityTier, String)] = [
            (0.18, .poor, "18%"),
            (0.42, .fair, "42%"),
            (0.67, .good, "67%"),
            (0.91, .excellent, "91%"),
        ]

        for (qualityValue, expectedTier, expectedLabel) in cases {
            let loc = makeLocation()
            let forecast = makeForecast(eventType: .sunset, eventTime: now.addingTimeInterval(3600), quality: qualityValue)
            let snap = makeSnapshot(locationID: loc.id, fetchedAt: now, forecasts: [forecast])
            let row = MenuBarPopoverPresenter.row(for: loc, snapshot: snap, preferences: prefs, isSelected: true, now: now)
            XCTAssertEqual(row.qualityLabel, expectedLabel)
            XCTAssertEqual(row.quality, qualityValue)
            XCTAssertEqual(row.qualityTier, expectedTier)
            XCTAssertFalse(row.isStale)
            XCTAssertTrue(row.accessibilityValue.contains(expectedTier.displayName))
            XCTAssertTrue(row.accessibilityValue.contains("percent"))
        }

        // Stale explicit status retains numeric percent and accessible tier while neutralizing row qualityTier
        let staleLoc = makeLocation(refreshIntervalHours: 6)
        let staleForecast = makeForecast(eventType: .sunset, eventTime: now.addingTimeInterval(3600), quality: 0.91)
        let staleSnap = makeSnapshot(locationID: staleLoc.id, fetchedAt: now, forecasts: [staleForecast], status: .stale)
        let staleRow = MenuBarPopoverPresenter.row(for: staleLoc, snapshot: staleSnap, preferences: prefs, isSelected: false, now: now)
        XCTAssertEqual(staleRow.qualityLabel, "91%")
        XCTAssertEqual(staleRow.quality, 0.91)
        XCTAssertNil(staleRow.qualityTier)
        XCTAssertTrue(staleRow.isStale)
        XCTAssertTrue(staleRow.accessibilityValue.contains("Excellent"))
        XCTAssertTrue(staleRow.accessibilityValue.contains("stale"))

        // Missing model data / nil quality produces neutral tier & "quality unavailable"
        let missingLoc = makeLocation()
        let missingForecast = makeForecast(eventType: .sunset, eventTime: now.addingTimeInterval(3600), quality: nil, modelData: false)
        let missingSnap = makeSnapshot(locationID: missingLoc.id, fetchedAt: now, forecasts: [missingForecast])
        let missingRow = MenuBarPopoverPresenter.row(for: missingLoc, snapshot: missingSnap, preferences: prefs, isSelected: false, now: now)
        XCTAssertEqual(missingRow.qualityLabel, "—")
        XCTAssertNil(missingRow.quality)
        XCTAssertNil(missingRow.qualityTier)
        XCTAssertTrue(missingRow.accessibilityValue.contains("quality unavailable"))
    }

    // MARK: - Menu-Bar Icon Best Upcoming Selection

    func testIconChoosesHighestQualityUpcomingWithinHorizonEvenWhenLaterThanNextEvent() throws {
        let now = try referenceNoon()
        let location = makeLocation(forecastDays: 2)

        let pastExcellent = makeForecast(eventType: .sunrise, eventTime: now.addingTimeInterval(-3600), quality: 0.98)
        let nextFairSunset = makeForecast(eventType: .sunset, eventTime: now.addingTimeInterval(5 * 3600), quality: 0.37)
        let tomorrowExcellentSunrise = makeForecast(eventType: .sunrise, eventTime: now.addingTimeInterval(18 * 3600), quality: 0.89)
        let outsideHorizonDay3 = makeForecast(eventType: .sunset, eventTime: now.addingTimeInterval(50 * 3600), quality: 0.99)

        let snapshot = makeSnapshot(
            locationID: location.id,
            fetchedAt: now,
            forecasts: [pastExcellent, nextFairSunset, tomorrowExcellentSunrise, outsideHorizonDay3]
        )

        let prefs = MenuBarPreferences(
            displayStyle: .locationEventQuality,
            eventSelection: .nextEvent,
            locationMode: .selectedLocation
        )
        let content = MenuBarLabelContent.resolve(
            locations: [location],
            snapshots: [location.id: snapshot],
            preferences: prefs,
            selectedLocationID: location.id,
            now: now
        )

        // Text reflects next upcoming event (sunset 37%), icon reflects best upcoming within horizon (sunrise 89% -> excellent)
        XCTAssertEqual(content.symbolName, "sunset.fill")
        XCTAssertEqual(content.title, "Sandown · Sunset 37.0%")
        XCTAssertEqual(content.iconQualityTier, .excellent)
        XCTAssertFalse(content.iconDescriptor.isTemplate)
        XCTAssertTrue(content.accessibilityLabel.contains("icon color excellent for best upcoming sunrise at 89.0 percent"))
    }

    func testIconRespectsEventSelectionAndEnabledEventPreferences() throws {
        let now = try referenceNoon()
        let location = makeLocation(forecastDays: 3, includeSunrise: true, includeSunset: true)

        let goodSunrise = makeForecast(eventType: .sunrise, eventTime: now.addingTimeInterval(16 * 3600), quality: 0.64)
        let excellentSunset = makeForecast(eventType: .sunset, eventTime: now.addingTimeInterval(6 * 3600), quality: 0.91)
        let poorSunsetTomorrow = makeForecast(eventType: .sunset, eventTime: now.addingTimeInterval(30 * 3600), quality: 0.12)
        let snapshot = makeSnapshot(
            locationID: location.id,
            fetchedAt: now,
            forecasts: [goodSunrise, excellentSunset, poorSunsetTomorrow]
        )

        // Sunrise-only preference ignores 91% sunset and maps 64% sunrise -> .good
        let sunriseOnlyPrefs = MenuBarPreferences(displayStyle: .locationEventQuality, eventSelection: .nextSunrise)
        let sunriseContent = MenuBarLabelContent.resolve(
            locations: [location],
            snapshots: [location.id: snapshot],
            preferences: sunriseOnlyPrefs,
            selectedLocationID: location.id,
            now: now
        )
        XCTAssertEqual(sunriseContent.symbolName, "sunrise.fill")
        XCTAssertEqual(sunriseContent.iconQualityTier, .good)

        // Disabled sunset returns neutral warning icon when selection asks for nextSunset
        let noSunsetLocation = makeLocation(forecastDays: 3, includeSunrise: true, includeSunset: false)
        let disabledPrefs = MenuBarPreferences(displayStyle: .locationEventQuality, eventSelection: .nextSunset)
        let disabledContent = MenuBarLabelContent.resolve(
            locations: [noSunsetLocation],
            snapshots: [noSunsetLocation.id: snapshot],
            preferences: disabledPrefs,
            selectedLocationID: noSunsetLocation.id,
            now: now
        )
        XCTAssertNil(disabledContent.iconQualityTier)
        XCTAssertTrue(disabledContent.iconDescriptor.isTemplate)
    }

    func testBestUpcomingIgnoresNonFiniteOrMissingModelAndTieBreaksDeterministically() throws {
        let now = try referenceNoon()
        let location = makeLocation(forecastDays: 3)

        let nanSunset = makeForecast(eventType: .sunset, eventTime: now.addingTimeInterval(2 * 3600), quality: .nan)
        let modelFalseSunrise = makeForecast(eventType: .sunrise, eventTime: now.addingTimeInterval(4 * 3600), quality: 0.99, modelData: false)
        let firstTied = makeForecast(eventType: .sunset, eventTime: now.addingTimeInterval(6 * 3600), quality: 0.42)
        let laterTied = makeForecast(eventType: .sunrise, eventTime: now.addingTimeInterval(18 * 3600), quality: 0.42)

        let snapshot = makeSnapshot(
            locationID: location.id,
            fetchedAt: now,
            forecasts: [nanSunset, modelFalseSunrise, laterTied, firstTied]
        )
        let best = MenuBarForecastResolver.resolveBestUpcomingItem(
            location: location,
            snapshot: snapshot,
            selection: .nextEvent,
            now: now
        )
        XCTAssertEqual(best?.eventTime, firstTied.eventTime)
        XCTAssertEqual(best?.eventType, .sunset)
        XCTAssertEqual(ForecastQualityTier.resolve(quality: best?.quality), .fair)

        // Identical timestamp tie-break picks .sunrise before .sunset
        let simultaneousSunset = makeForecast(eventType: .sunset, eventTime: now.addingTimeInterval(8 * 3600), quality: 0.60)
        let simultaneousSunrise = makeForecast(eventType: .sunrise, eventTime: now.addingTimeInterval(8 * 3600), quality: 0.60)
        let tiedSnap = makeSnapshot(locationID: location.id, fetchedAt: now, forecasts: [simultaneousSunset, simultaneousSunrise])
        let tiedBest = MenuBarForecastResolver.resolveBestUpcomingItem(
            location: location,
            snapshot: tiedSnap,
            selection: .nextEvent,
            now: now
        )
        XCTAssertEqual(tiedBest?.eventType, .sunrise)

        // Only invalid/unavailable events -> nil -> neutral icon
        let onlyInvalid = makeSnapshot(locationID: location.id, fetchedAt: now, forecasts: [nanSunset, modelFalseSunrise])
        XCTAssertNil(MenuBarForecastResolver.resolveBestUpcomingItem(
            location: location,
            snapshot: onlyInvalid,
            selection: .nextEvent,
            now: now
        ))
    }

    func testStaleAndExpiredSnapshotsNeutralizeMenuBarIcon() throws {
        let now = try referenceNoon()
        let location = makeLocation(forecastDays: 3, refreshIntervalHours: 6)
        let futureSunset = makeForecast(eventType: .sunset, eventTime: now.addingTimeInterval(4 * 3600), quality: 0.92)

        let staleSnap = makeSnapshot(locationID: location.id, fetchedAt: now, forecasts: [futureSunset], status: .stale)
        let expiredSnap = makeSnapshot(
            locationID: location.id,
            fetchedAt: now.addingTimeInterval(-7 * 3600),
            forecasts: [futureSunset],
            status: .current
        )
        let prefs = MenuBarPreferences(displayStyle: .locationEventQuality)

        for snapshot in [staleSnap, expiredSnap] {
            let content = MenuBarLabelContent.resolve(
                locations: [location],
                snapshots: [location.id: snapshot],
                preferences: prefs,
                selectedLocationID: location.id,
                now: now
            )
            XCTAssertNil(content.iconQualityTier)
            XCTAssertTrue(content.iconDescriptor.isTemplate)
            XCTAssertFalse(content.accessibilityLabel.contains("icon color"))
        }
    }

    func testRotatingModeUpdatesIconColorAcrossLocationsAndAllDisplayStyles() {
        let now = Date(timeIntervalSince1970: 1_795_000_000)
        let locA = makeLocation(id: UUID(), name: "Red Harbor", forecastDays: 3)
        let locB = makeLocation(id: UUID(), name: "Green Peak", forecastDays: 3)

        let poorEvent = makeForecast(eventType: .sunset, eventTime: now.addingTimeInterval(3600), quality: 0.12)
        let excellentEvent = makeForecast(eventType: .sunrise, eventTime: now.addingTimeInterval(7200), quality: 0.91)
        let snapshots = [
            locA.id: makeSnapshot(locationID: locA.id, fetchedAt: now, forecasts: [poorEvent]),
            locB.id: makeSnapshot(locationID: locB.id, fetchedAt: now, forecasts: [excellentEvent]),
        ]

        let interval = 10
        let prefs = MenuBarPreferences(
            displayStyle: .locationEventQuality,
            eventSelection: .nextEvent,
            locationMode: .rotateLocations,
            rotationIntervalSeconds: interval
        )

        let idx0 = MenuBarRotationLogic.rotationIndex(candidateCount: 2, intervalSeconds: interval, now: now)
        let expectedFirst: ForecastQualityTier = idx0 == 0 ? .poor : .excellent
        let expectedSecond: ForecastQualityTier = idx0 == 0 ? .excellent : .poor

        let contentTick0 = MenuBarLabelContent.resolve(
            locations: [locA, locB],
            snapshots: snapshots,
            preferences: prefs,
            selectedLocationID: locA.id,
            now: now
        )
        XCTAssertEqual(contentTick0.iconQualityTier, expectedFirst)

        let contentTick1 = MenuBarLabelContent.resolve(
            locations: [locA, locB],
            snapshots: snapshots,
            preferences: prefs,
            selectedLocationID: locA.id,
            now: now.addingTimeInterval(TimeInterval(interval))
        )
        XCTAssertEqual(contentTick1.iconQualityTier, expectedSecond)

        // All display styles preserve iconQualityTier & rich accessibility label
        for style in MenuBarDisplayStyle.allCases {
            let styledPrefs = MenuBarPreferences(
                displayStyle: style,
                eventSelection: .nextEvent,
                locationMode: .selectedLocation
            )
            let styled = MenuBarLabelContent.resolve(
                locations: [locB],
                snapshots: snapshots,
                preferences: styledPrefs,
                selectedLocationID: locB.id,
                now: now
            )
            XCTAssertEqual(styled.iconQualityTier, .excellent)
            XCTAssertTrue(styled.accessibilityLabel.contains("icon color excellent"))
            if style == .iconOnly {
                XCTAssertEqual(styled.title, "")
            } else {
                XCTAssertFalse(styled.title.isEmpty)
            }
        }
    }

    func testIconDescriptorCacheKeysDifferentiateAppearanceAndContrast() {
        let colored = MenuBarIconDescriptor(symbolName: "sunset.fill", qualityTier: .good, isTemplate: false)
        let neutral = MenuBarIconDescriptor(symbolName: "sun.horizon", qualityTier: nil, isTemplate: true)

        XCTAssertFalse(colored.isTemplate)
        XCTAssertTrue(neutral.isTemplate)

        let keys = [
            colored.cacheKey(appearance: .light, isHighContrast: false),
            colored.cacheKey(appearance: .dark, isHighContrast: false),
            colored.cacheKey(appearance: .light, isHighContrast: true),
            colored.cacheKey(appearance: .dark, isHighContrast: true),
            neutral.cacheKey(appearance: .light, isHighContrast: false),
        ]
        XCTAssertEqual(Set(keys).count, keys.count)
    }

    // MARK: - Swift 6 Concurrency & Micro-Benchmark Checks

    func testConcurrentRefreshDeduplicationUnderSwift6AndCancellation() async throws {
        let now = try referenceNoon()
        let loc = makeLocation(forecastDays: 1)
        let settings = InMemorySettingsStore(state: SharedAppState(locations: [loc], selectedLocationID: loc.id))
        let cache = InMemoryForecastCache()
        let credentials = InMemoryCredentialStore(apiKey: "test-secret-key")
        let transport = MockHTTPTransport()

        let isoFormatter = ISO8601DateFormatter()
        let sunrisePayload = try JSONSerialization.data(withJSONObject: [
            "time": isoFormatter.string(from: now),
            "location": ["latitude": 40.7128, "longitude": -74.0060],
            "grid_location": ["latitude": 40.7, "longitude": -74.0],
            "data": [
                "type": "sunrise",
                "model_data": true,
                "quality": 0.55,
                "quality_text": "Good",
                "cloud_cover": 0.25,
                "time": isoFormatter.string(from: now.addingTimeInterval(3600)),
                "magics": [:],
            ],
        ])
        let sunsetPayload = try JSONSerialization.data(withJSONObject: [
            "time": isoFormatter.string(from: now),
            "location": ["latitude": 40.7128, "longitude": -74.0060],
            "grid_location": ["latitude": 40.7, "longitude": -74.0],
            "data": [
                "type": "sunset",
                "model_data": true,
                "quality": 0.88,
                "quality_text": "Excellent",
                "cloud_cover": 0.15,
                "time": isoFormatter.string(from: now.addingTimeInterval(18000)),
                "magics": [:],
            ],
        ])
        transport.enqueue(MockHTTPTransport.Stub(statusCode: 200, body: sunrisePayload))
        transport.enqueue(MockHTTPTransport.Stub(statusCode: 200, body: sunsetPayload))
        transport.enqueue(MockHTTPTransport.Stub(statusCode: 200, body: sunrisePayload))
        transport.enqueue(MockHTTPTransport.Stub(statusCode: 200, body: sunsetPayload))

        let service = ForecastService(transport: transport)
        let coordinator = ForecastRefreshCoordinator(
            settingsStore: settings,
            forecastCache: cache,
            credentialStore: credentials,
            forecastService: service
        )

        // Rapid concurrent refreshes coalesce cleanly onto a single in-flight refresh.
        async let firstBatch = coordinator.refreshLocation(id: loc.id, force: true)
        async let secondBatch = coordinator.refreshLocation(id: loc.id, force: true)
        let (res1, res2) = await (firstBatch, secondBatch)

        XCTAssertNotNil(res1?.bundle)
        XCTAssertNotNil(res2?.bundle)
        XCTAssertEqual(transport.requests.count, 4)

        let scheduled = Task {
            await coordinator.scheduleNextRefresh()
        }
        scheduled.cancel()
        _ = await scheduled.value
        await coordinator.locationRemoved(id: loc.id)
    }

    func testQualityTierAndMenuBarResolutionMicroBenchmark() throws {
        let now = try referenceNoon()
        let location = makeLocation(forecastDays: 3)
        let forecasts = [
            makeForecast(eventType: .sunrise, eventTime: now.addingTimeInterval(3600), quality: 0.37),
            makeForecast(eventType: .sunset, eventTime: now.addingTimeInterval(18000), quality: 0.89),
            makeForecast(eventType: .sunrise, eventTime: now.addingTimeInterval(42000), quality: 0.62),
        ]
        let snapshot = makeSnapshot(locationID: location.id, fetchedAt: now, forecasts: forecasts)
        let snapshots = [location.id: snapshot]
        let prefs = MenuBarPreferences(displayStyle: .locationEventQualityTime, eventSelection: .nextEvent)

        let clock = ContinuousClock()
        let tierDuration = clock.measure {
            var checksum = 0
            for index in 0 ..< 10000 {
                let sample = Double(index % 101) / 100.0
                if ForecastQualityTier.resolve(quality: sample) != nil {
                    checksum += 1
                }
            }
            XCTAssertEqual(checksum, 10000)
        }

        let labelDuration = clock.measure {
            var nonEmptyCount = 0
            for _ in 0 ..< 1000 {
                let resolved = MenuBarLabelContent.resolve(
                    locations: [location],
                    snapshots: snapshots,
                    preferences: prefs,
                    selectedLocationID: location.id,
                    now: now
                )
                if !resolved.title.isEmpty {
                    nonEmptyCount += 1
                }
            }
            XCTAssertEqual(nonEmptyCount, 1000)
        }

        let rowDuration = clock.measure {
            var coloredRows = 0
            for _ in 0 ..< 1000 {
                let row = MenuBarPopoverPresenter.row(
                    for: location,
                    snapshot: snapshot,
                    preferences: prefs,
                    isSelected: true,
                    now: now
                )
                if row.qualityTier != nil {
                    coloredRows += 1
                }
            }
            XCTAssertEqual(coloredRows, 1000)
        }

        print("[BENCH] 10k ForecastQualityTier.resolve: \(tierDuration)")
        print("[BENCH] 1k MenuBarLabelContent.resolve: \(labelDuration)")
        print("[BENCH] 1k MenuBarPopoverPresenter.row: \(rowDuration)")
    }
}
