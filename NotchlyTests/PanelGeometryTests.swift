import XCTest
import AppKit
@testable import Notchly

@MainActor
final class PanelGeometryTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)

    private func geometry(edge: ScreenEdge, alignment: Double = 0.5) -> PanelGeometry {
        var settings = NotchlySettings()
        settings.edge = edge
        settings.alignment = alignment
        settings.panelWidth = 372
        settings.panelHeight = 540
        settings.handleThickness = 5
        settings.handleLength = 108
        var value = PanelGeometry(settings: settings, screen: NSScreen.screens[0])
        value.screenFrame = screen
        return value
    }

    func testOpenFrameIsFlushWithItsDockedEdge() {
        XCTAssertEqual(geometry(edge: .trailing).windowFrame(expanded: true).maxX, screen.maxX, accuracy: 0.001)
        XCTAssertEqual(geometry(edge: .leading).windowFrame(expanded: false).minX, screen.minX, accuracy: 0.001)
        XCTAssertEqual(geometry(edge: .top).windowFrame(expanded: true).maxY, screen.maxY, accuracy: 0.001)
        XCTAssertEqual(geometry(edge: .bottom).windowFrame(expanded: false).minY, screen.minY, accuracy: 0.001)
    }

    func testIdleFrameIsMuchSmallerThanTheOpenOne() {
        // The whole point of shrinking the window when closed is that Notchly stops
        // intercepting clicks meant for the desktop.
        let value = geometry(edge: .trailing)
        let idle = value.windowFrame(expanded: false)
        let open = value.windowFrame(expanded: true)
        XCTAssertLessThan(idle.width * idle.height, open.width * open.height / 8)
    }

    func testAlignmentZeroIsTopForVerticalEdgesAndLeftForHorizontalOnes() {
        XCTAssertGreaterThan(geometry(edge: .trailing, alignment: 0).edgeCenter(expanded: true),
                             geometry(edge: .trailing, alignment: 1).edgeCenter(expanded: true))
        XCTAssertLessThan(geometry(edge: .top, alignment: 0).edgeCenter(expanded: true),
                          geometry(edge: .top, alignment: 1).edgeCenter(expanded: true))
    }

    func testPanelNeverHangsOffTheEndsOfItsEdge() {
        for alignment in [0.0, 0.25, 0.5, 0.75, 1.0] {
            let frame = geometry(edge: .trailing, alignment: alignment).windowFrame(expanded: true)
            XCTAssertGreaterThanOrEqual(frame.minY, screen.minY - 0.001, "alignment \(alignment)")
            XCTAssertLessThanOrEqual(frame.maxY, screen.maxY + 0.001, "alignment \(alignment)")
        }
    }

    func testWidthAndHeightSwapRolesOnHorizontalEdges() {
        // Docking to the top shouldn't force the user to re-tune both sliders: the
        // "width" setting always means the extent along the edge.
        let side = geometry(edge: .trailing)
        let top = geometry(edge: .top)
        XCTAssertEqual(side.bodyDepth, 372)
        XCTAssertEqual(side.bodyExtent, 540)
        XCTAssertEqual(top.bodyDepth, 540)
        XCTAssertEqual(top.bodyExtent, 372)
    }
}
