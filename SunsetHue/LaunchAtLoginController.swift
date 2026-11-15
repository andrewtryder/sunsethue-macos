import Foundation
import ServiceManagement

enum LaunchAtLoginStatus: Equatable, Sendable {
    case notRegistered
    case enabled
    case requiresApproval
    case unavailable

    static func current() -> LaunchAtLoginStatus {
        switch SMAppService.mainApp.status {
        case .enabled:
            .enabled
        case .requiresApproval:
            .requiresApproval
        case .notFound:
            .unavailable
        case .notRegistered:
            .notRegistered
        @unknown default:
            .unavailable
        }
    }
}

@MainActor
final class LaunchAtLoginController: ObservableObject {
    @Published private(set) var status: LaunchAtLoginStatus = .current()
    @Published var errorMessage: String?

    var isEnabled: Bool {
        status == .enabled
    }

    static var isEnabled: Bool {
        LaunchAtLoginStatus.current() == .enabled
    }

    func refresh() {
        status = LaunchAtLoginStatus.current()
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            refresh()
            errorMessage = nil
        } catch {
            refresh()
            errorMessage = error.localizedDescription.isEmpty
                ? "macOS did not allow the login-item change."
                : error.localizedDescription
        }
    }
}
