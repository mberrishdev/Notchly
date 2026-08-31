import XCTest
import SwiftUI
@testable import Notchly

final class NotchShapeTests: XCTestCase {
    private let rect = CGRect(x: 0, y: 0, width: 120, height: 200)

    func testShapeStaysInsideItsRectOnEveryEdge() {
        for edge in ScreenEdge.allCases {
            let path = NotchShape(edge: edge, cornerRadius: 24, inverseRadius: 12).path(in: rect)
            let bounds = path.boundingRect
            XCTAssertGreaterThanOrEqual(bounds.minX, rect.minX - 0.001, "\(edge) overflowed left")
            XCTAssertGreaterThanOrEqual(bounds.minY, rect.minY - 0.001, "\(edge) overflowed top")
            XCTAssertLessThanOrEqual(bounds.maxX, rect.maxX + 0.001, "\(edge) overflowed right")
            XCTAssertLessThanOrEqual(bounds.maxY, rect.maxY + 0.001, "\(edge) overflowed bottom")
        }
    }

    func testEachEdgeTouchesTheSideItDocksTo() {
        let cases: [(ScreenEdge, (CGRect) -> CGFloat, CGFloat)] = [
            (.top, { $0.minY }, rect.minY),
            (.bottom, { $0.maxY }, rect.maxY),
            (.leading, { $0.minX }, rect.minX),
            (.trailing, { $0.maxX }, rect.maxX)
        ]
        for (edge, probe, expected) in cases {
            let bounds = NotchShape(edge: edge, cornerRadius: 24, inverseRadius: 12).path(in: rect).boundingRect
            XCTAssertEqual(probe(bounds), expected, accuracy: 0.001, "\(edge) did not reach its edge")
        }
    }

    func testOversizedRadiiAreClampedRatherThanSelfIntersecting() {
        // Mid-animation the radii can briefly exceed the box; the path must stay sane.
        let path = NotchShape(edge: .trailing, cornerRadius: 999, inverseRadius: 999).path(in: rect)
        XCTAssertFalse(path.isEmpty)
        XCTAssertTrue(rect.insetBy(dx: -0.001, dy: -0.001).contains(path.boundingRect))
    }

    func testDegenerateRectProducesAnEmptyPath() {
        let path = NotchShape(edge: .top, cornerRadius: 10, inverseRadius: 5).path(in: .zero)
        XCTAssertTrue(path.isEmpty)
    }

    func testHorizontalAndVerticalEdgesAreTransposesOfEachOther() {
        let square = CGRect(x: 0, y: 0, width: 160, height: 160)
        let top = NotchShape(edge: .top, cornerRadius: 20, inverseRadius: 10).path(in: square).boundingRect
        let leading = NotchShape(edge: .leading, cornerRadius: 20, inverseRadius: 10).path(in: square).boundingRect
        XCTAssertEqual(top.width, leading.height, accuracy: 0.001)
        XCTAssertEqual(top.height, leading.width, accuracy: 0.001)
    }
}
