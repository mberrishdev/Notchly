import XCTest
@testable import Notchly

final class AppSearchTests: XCTestCase {
    private let apps: [LaunchableApp] = [
        "Safari", "System Settings", "Sublime Text", "Visual Studio Code",
        "Activity Monitor", "Mail", "Music", "Terminal", "Notes"
    ].map { LaunchableApp(name: $0, url: URL(fileURLWithPath: "/Applications/\($0).app"), bundleID: "test.\($0)") }

    private func names(_ query: String, limit: Int = 8) -> [String] {
        AppCatalog.rank(query, in: apps, limit: limit).map(\.name)
    }

    func testPrefixMatchesOutrankScatteredOnes() {
        XCTAssertEqual(names("saf").first, "Safari")
        XCTAssertEqual(names("term").first, "Terminal")
    }

    func testInitialsMatchMultiWordNames() {
        XCTAssertEqual(names("vsc").first, "Visual Studio Code")
        XCTAssertEqual(names("am").first, "Activity Monitor")
    }

    func testExactNameWinsOverALongerPrefixMatch() {
        XCTAssertEqual(names("mail").first, "Mail")
    }

    func testSearchIsCaseInsensitiveAndIgnoresSurroundingSpace() {
        XCTAssertEqual(names("  SAFARI "), ["Safari"])
    }

    func testEmptyQueryReturnsNothingRatherThanEverything() {
        XCTAssertTrue(names("").isEmpty)
        XCTAssertTrue(names("   ").isEmpty)
    }

    func testNonMatchingQueryReturnsNothing() {
        XCTAssertTrue(names("zzzz").isEmpty)
    }

    func testLimitIsRespected() {
        XCTAssertLessThanOrEqual(names("s", limit: 2).count, 2)
    }

    func testScatteredSubsequenceStillMatches() {
        // "vlc" isn't a prefix or an initialism, but it is in order within the name.
        XCTAssertTrue(names("vsl").contains("Visual Studio Code"))
    }
}
