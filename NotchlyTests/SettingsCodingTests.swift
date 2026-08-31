import XCTest
import SwiftUI
@testable import Notchly

final class SettingsCodingTests: XCTestCase {
    func testDefaultsRoundTripThroughJSON() throws {
        let settings = NotchlySettings()
        let data = try JSONEncoder().encode(settings)
        XCTAssertEqual(try JSONDecoder().decode(NotchlySettings.self, from: data), settings)
    }

    func testSettingsFileFromAnOlderVersionStillLoads() throws {
        // Every field has a default, so a settings.json written before a field existed
        // must keep loading instead of resetting the user's whole configuration.
        let json = #"{ "edge": "leading", "panelWidth": 300 }"#
        let settings = try JSONDecoder().decode(NotchlySettings.self, from: Data(json.utf8))
        XCTAssertEqual(settings.edge, .leading)
        XCTAssertEqual(settings.panelWidth, 300)
        XCTAssertEqual(settings.slots.count, NotchlySettings.defaultSlots.count)
        XCTAssertEqual(settings.activation, .hover)
    }

    func testDefaultSlotsMatchTheBuiltInWidgets() {
        let builtInIDs = Set(WidgetRegistry.builtIn.map(\.id))
        for slot in NotchlySettings.defaultSlots {
            XCTAssertEqual(slot.kind, .builtIn)
            XCTAssertTrue(builtInIDs.contains(slot.widgetID), "\(slot.widgetID) has no descriptor")
        }
    }

    func testEveryBuiltInSchemaDefaultMatchesItsDeclaredType() {
        for descriptor in WidgetRegistry.builtIn {
            for field in descriptor.settingsSchema {
                switch field.kind {
                case .boolean: XCTAssertNotNil(field.defaultValue?.boolValue, "\(field.key)")
                case .number: XCTAssertNotNil(field.defaultValue?.doubleValue, "\(field.key)")
                case .string, .select, .color: XCTAssertNotNil(field.defaultValue?.stringValue, "\(field.key)")
                }
                if field.kind == .select {
                    XCTAssertTrue(field.options?.contains(field.defaultValue?.stringValue ?? "") ?? false,
                                  "\(field.key) default is not one of its options")
                }
            }
        }
    }

    func testAccentHexParsesToAColor() {
        XCTAssertNotNil(Color(hex: NotchlySettings().accentHex))
        XCTAssertNil(Color(hex: "not-a-color"))
        XCTAssertNotNil(Color(hex: "#80FF00FF"))
    }
}
