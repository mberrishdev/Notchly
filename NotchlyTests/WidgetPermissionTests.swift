import XCTest
@testable import Notchly

final class WidgetPermissionTests: XCTestCase {
    func testSensitivePermissionsRequireAnExplicitGrant() {
        // Clipboard history holds everything the user has copied; shell runs as them;
        // network is how anything leaves the machine. None are granted on install.
        XCTAssertEqual(Set(WidgetPermission.allCases.filter(\.requiresExplicitGrant)),
                       [.shell, .clipboard, .network])
    }

    func testHarmlessPermissionsAreGrantedOnDeclaration() {
        XCTAssertFalse(WidgetPermission.system.requiresExplicitGrant)
        XCTAssertFalse(WidgetPermission.notifications.requiresExplicitGrant)
    }

    func testEverySettingsGrantListHasABackingStore() {
        // A permission that needs a grant but has nowhere to record it would read as
        // permanently denied, which is how the clipboard switch went missing once.
        let settings = NotchlySettings()
        for permission in WidgetPermission.allCases where permission.requiresExplicitGrant {
            switch permission {
            case .shell: XCTAssertTrue(settings.shellApprovedWidgets.isEmpty)
            case .network: XCTAssertTrue(settings.networkApprovedWidgets.isEmpty)
            case .clipboard: XCTAssertTrue(settings.clipboardApprovedWidgets.isEmpty)
            default: XCTFail("\(permission) needs a grant but has no store")
            }
        }
    }

    func testEveryPermissionHasALabelDetailAndSymbol() {
        for permission in WidgetPermission.allCases {
            XCTAssertFalse(permission.label.isEmpty, "\(permission)")
            XCTAssertFalse(permission.detail.isEmpty, "\(permission)")
            XCTAssertFalse(permission.symbol.isEmpty, "\(permission)")
        }
    }

    func testPermissionsSurviveASettingsRoundTrip() throws {
        var settings = NotchlySettings()
        settings.clipboardApprovedWidgets = ["a.b"]
        settings.shellApprovedWidgets = ["c.d"]
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(NotchlySettings.self, from: data)
        XCTAssertEqual(decoded.clipboardApprovedWidgets, ["a.b"])
        XCTAssertEqual(decoded.shellApprovedWidgets, ["c.d"])
        XCTAssertTrue(decoded.networkApprovedWidgets.isEmpty)
    }
}
