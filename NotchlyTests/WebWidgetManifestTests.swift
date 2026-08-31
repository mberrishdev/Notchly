import XCTest
@testable import Notchly

final class WebWidgetManifestTests: XCTestCase {
    private func decode(_ json: String) throws -> WebWidgetManifest {
        try JSONDecoder().decode(WebWidgetManifest.self, from: Data(json.utf8))
    }

    func testMinimalManifestDecodesAndDefaultsTheEntryFile() throws {
        let manifest = try decode(#"{ "id": "a.b", "name": "Thing" }"#)
        XCTAssertEqual(manifest.id, "a.b")
        XCTAssertEqual(manifest.entryFile, "index.html")
        XCTAssertNil(manifest.permissions)
    }

    func testFullManifestDecodesPermissionsAndSettingsSchema() throws {
        let manifest = try decode("""
        {
          "id": "a.b", "name": "Thing", "entry": "main.html",
          "permissions": ["network", "shell"],
          "settings": [
            { "key": "city", "type": "string", "label": "City", "default": "Berlin" },
            { "key": "size", "type": "number", "label": "Size", "default": 3, "minimum": 1, "maximum": 9 }
          ]
        }
        """)
        XCTAssertEqual(manifest.entryFile, "main.html")
        XCTAssertEqual(manifest.permissions, [.network, .shell])
        XCTAssertEqual(manifest.settings?.count, 2)
        XCTAssertEqual(manifest.settings?[0].defaultValue, .string("Berlin"))
        XCTAssertEqual(manifest.settings?[1].maximum, 9)
    }

    func testMissingRequiredKeyIsRejected() {
        XCTAssertThrowsError(try decode(#"{ "name": "No id here" }"#))
    }

    func testUnknownPermissionIsRejectedRatherThanSilentlyIgnored() {
        // Better to show the author a load error than to run with a permission
        // they think they asked for.
        XCTAssertThrowsError(try decode(#"{ "id": "a", "name": "b", "permissions": ["root"] }"#))
    }

    func testDescriptorCarriesManifestMetadataThrough() throws {
        let manifest = try decode("""
        { "id": "a.b", "name": "Thing", "version": "2.1", "author": "Someone",
          "description": "Does things", "icon": "bolt", "height": 200,
          "permissions": ["system"] }
        """)
        let package = WebWidgetPackage(manifest: manifest,
                                       folderURL: URL(fileURLWithPath: "/tmp/thing"),
                                       revision: 0)
        let descriptor = package.descriptor
        XCTAssertEqual(descriptor.kind, .web)
        XCTAssertEqual(descriptor.name, "Thing")
        XCTAssertEqual(descriptor.version, "2.1")
        XCTAssertEqual(descriptor.symbol, "bolt")
        XCTAssertEqual(descriptor.preferredHeight, 200)
        XCTAssertEqual(descriptor.requestedPermissions, [.system])
        XCTAssertEqual(package.entryURL.lastPathComponent, "index.html")
    }
}
