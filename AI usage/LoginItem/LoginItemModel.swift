import Foundation
import Observation
import ServiceManagement

@MainActor
@Observable
final class LoginItemModel {
    private(set) var isEnabled = false
    private(set) var needsApproval = false
    private(set) var errorMessage: String?

    private let service: any LoginItemService

    convenience init() {
        self.init(service: MainAppLoginItemService())
    }

    init(service: any LoginItemService) {
        self.service = service
        applyStatus()
    }

    /// Re-derive from the system; called on every panel open.
    func refresh() {
        errorMessage = nil
        applyStatus()
    }

    func setEnabled(_ enabled: Bool) {
        errorMessage = nil
        guard !needsApproval, enabled != isEnabled else { return }

        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            errorMessage = "Couldn't \(enabled ? "enable" : "disable") Start at login: \(error.localizedDescription)"
        }

        applyStatus()
    }

    private func applyStatus() {
        let status = service.status
        isEnabled = status == .enabled
        needsApproval = status == .requiresApproval
    }
}
