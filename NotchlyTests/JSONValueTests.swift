import XCTest
@testable import Notchly

final class JSONValueTests: XCTestCase {
    func testRoundTripsThroughCodable() throws {
        let value = JSONValue.object([
            "name": .string("widget"),
            "count": .number(3),
            "on": .bool(true),
            "tags": .array([.string("a"), .null]),
            "nested": .object(["deep": .number(1.5)])
        ])
        let data = try JSONEncoder().encode(value)
        XCTAssertEqual(try JSONDecoder().decode(JSONValue.self, from: data), value)
    }

    func testBridgingFromWebKitDistinguishesBoolFromNumber() {
        // NSNumber erases Bool, so `true` arriving over the bridge must not become 1.
        let bridged = JSONValue(any: ["flag": true, "count": 1] as [String: Any])
        XCTAssertEqual(bridged.objectValue?["flag"], .bool(true))
        XCTAssertEqual(bridged.objectValue?["count"], .number(1))
    }

    func testBridgingSurvivesARoundTripBackToFoundation() {
        let original: [String: Any] = ["a": "x", "b": 2.5, "c": [1.0, 2.0]]
        let restored = JSONValue(any: original).anyValue as? [String: Any]
        XCTAssertEqual(restored?["a"] as? String, "x")
        XCTAssertEqual(restored?["b"] as? Double, 2.5)
        XCTAssertEqual((restored?["c"] as? [Any])?.count, 2)
    }

    func testUnsupportedValuesBecomeNullRatherThanCrashing() {
        XCTAssertEqual(JSONValue(any: Date()), .null)
        XCTAssertEqual(JSONValue(any: NSNull()), .null)
    }

    func testTypedAccessorsReturnNilForTheWrongCase() {
        XCTAssertNil(JSONValue.string("5").doubleValue)
        XCTAssertNil(JSONValue.number(5).stringValue)
        XCTAssertEqual(JSONValue.number(5).doubleValue, 5)
    }
}
