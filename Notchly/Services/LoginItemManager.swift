import Foundation
import ServiceManagement

/// Launch-at-login toggle. `SMAppService` only works for a bundled, registered app, so
/// the failure path matters: report it rather than silently leaving the switch on.
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @discardableResult
    static func set(_ enabled: Bool) -> String? {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else {
                if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
