import XCTest
@testable import Notchly

final class FormatTests: XCTestCase {
    func testRateSwitchesUnitAtEachThreshold() {
        XCTAssertEqual(Format.rate(0), "0 B/s")
        XCTAssertEqual(Format.rate(512), "512 B/s")
        XCTAssertEqual(Format.rate(2048), "2 KB/s")
        XCTAssertEqual(Format.rate(5 * 1_048_576), "5.0 MB/s")
    }

    func testNegativeRatesClampToZero() {
        // Interface counters wrap; a negative delta must not render as "-3 B/s".
        XCTAssertEqual(Format.rate(-100), "0 B/s")
    }

    func testPercentRounds() {
        XCTAssertEqual(Format.percent(0.0), "0%")
        XCTAssertEqual(Format.percent(0.456), "46%")
        XCTAssertEqual(Format.percent(1.0), "100%")
    }

    func testDurationPicksTheCoarsestUsefulUnit() {
        XCTAssertEqual(Format.duration(90), "1m")
        XCTAssertEqual(Format.duration(3_600 * 5 + 60 * 12), "5h 12m")
        XCTAssertEqual(Format.duration(86_400 * 2 + 3_600 * 3), "2d 3h")
        XCTAssertEqual(Format.duration(-10), "0m")
    }

    func testMinutesFormatsHoursOncePastSixty() {
        XCTAssertEqual(Format.minutes(45), "45m")
        XCTAssertEqual(Format.minutes(60), "1h 0m")
        XCTAssertEqual(Format.minutes(135), "2h 15m")
    }
}
