import XCTest
@testable import Notchly

final class PanelPlacementTests: XCTestCase {
    /// A wide display, which is where a naive nearest-edge rule breaks down.
    private let screen = CGRect(x: 0, y: 0, width: 3440, height: 1440)

    private func edge(at x: CGFloat, _ y: CGFloat) -> ScreenEdge? {
        PanelPlacement.resolve(pointer: CGPoint(x: x, y: y), in: screen)?.edge
    }

    func testEachCornerRegionPicksTheEdgeYouWouldExpect() {
        XCTAssertEqual(edge(at: 40, 720), .leading)
        XCTAssertEqual(edge(at: 3400, 720), .trailing)
        XCTAssertEqual(edge(at: 1720, 1420), .top)
        XCTAssertEqual(edge(at: 1720, 20), .bottom)
    }

    func testSideEdgesWinInsideTheirOwnHalfOfAWideDisplay() {
        // Measured in raw points, a pointer 500px from the left edge of an ultrawide is
        // "closer" to the top than to the left. Normalising by each dimension is what
        // keeps dragging toward the left side actually docking left.
        XCTAssertEqual(edge(at: 500, 720), .leading)
        XCTAssertEqual(edge(at: 2940, 720), .trailing)
    }

    func testAlignmentRunsTopToBottomOnTheLeftAndRightEdges() {
        let top = PanelPlacement.resolve(pointer: CGPoint(x: 20, y: 1430), in: screen)
        let bottom = PanelPlacement.resolve(pointer: CGPoint(x: 20, y: 10), in: screen)
        XCTAssertEqual(top?.alignment ?? 1, 0, accuracy: 0.01)
        XCTAssertEqual(bottom?.alignment ?? 0, 1, accuracy: 0.01)
    }

    func testAlignmentRunsLeftToRightOnTheTopAndBottomEdges() {
        // Kept clear of the corners, where the left and right edges rightly win.
        let left = PanelPlacement.resolve(pointer: CGPoint(x: 300, y: 1435), in: screen)
        let right = PanelPlacement.resolve(pointer: CGPoint(x: 3140, y: 1435), in: screen)
        XCTAssertEqual(left?.edge, .top)
        XCTAssertEqual(right?.edge, .top)
        XCTAssertEqual(left?.alignment ?? 1, 0.087, accuracy: 0.01)
        XCTAssertEqual(right?.alignment ?? 0, 0.913, accuracy: 0.01)
    }

    func testCornersResolveToTheLeftOrRightEdgeRatherThanTopOrBottom() {
        // A wide display puts every corner proportionally nearer its side edge.
        XCTAssertEqual(edge(at: 3435, 1435), .trailing)
        XCTAssertEqual(edge(at: 5, 5), .leading)
    }

    func testAlignmentIsClampedForPointersJustOutsideTheFrame() {
        let past = PanelPlacement.resolve(pointer: CGPoint(x: -50, y: 2000), in: screen)
        XCTAssertNotNil(past)
        XCTAssertGreaterThanOrEqual(past!.alignment, 0)
        XCTAssertLessThanOrEqual(past!.alignment, 1)
    }

    func testWorksOnADisplayWhoseOriginIsNotZero() {
        // Secondary displays sit at arbitrary global coordinates.
        let offset = CGRect(x: -1710, y: 1112, width: 1710, height: 1112)
        let placement = PanelPlacement.resolve(pointer: CGPoint(x: -1700, y: 1668), in: offset)
        XCTAssertEqual(placement?.edge, .leading)
        XCTAssertEqual(placement?.alignment ?? 0, 0.5, accuracy: 0.02)
    }

    func testDegenerateFrameIsRejectedRatherThanDividingByZero() {
        XCTAssertNil(PanelPlacement.resolve(pointer: .zero, in: .zero))
    }
}
