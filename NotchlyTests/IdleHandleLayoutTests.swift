import XCTest
@testable import Notchly

final class IdleHandleLayoutTests: XCTestCase {
    private func layout(_ chips: [IdleChip], edge: ScreenEdge = .trailing, widgets: Int = 5) -> IdleHandleLayout {
        IdleHandleLayout.resolve(chips: chips,
                                 edge: edge,
                                 lineThickness: 5,
                                 lineLength: 108,
                                 contentThickness: 30,
                                 widgetCount: widgets)
    }

    func testNoChipsGivesThePlainLineAtTheConfiguredSize() {
        let line = layout([])
        XCTAssertFalse(line.showsContent)
        XCTAssertEqual(line.depth, 5)
        XCTAssertEqual(line.extent, 108)
    }

    func testChipsSwitchToTheContentThickness() {
        let handle = layout([.clock])
        XCTAssertTrue(handle.showsContent)
        XCTAssertEqual(handle.depth, 30)
    }

    func testExtentGrowsWithEachAddedChip() {
        let one = layout([.clock]).extent
        let two = layout([.clock, .nowPlaying]).extent
        let three = layout([.clock, .nowPlaying, .cpu]).extent
        XCTAssertLessThan(one, two)
        XCTAssertLessThan(two, three)
    }

    func testExtentAccountsForSpacingBetweenChips() {
        let padding = IdleHandleLayout.endPadding * 2
        let chips: [IdleChip] = [.clock, .cpu, .battery]
        let content = chips.reduce(CGFloat.zero) { $0 + $1.extent(growsHorizontally: true, widgetCount: 5) }
        let expected = content + IdleHandleLayout.spacing * 2 + padding
        XCTAssertEqual(layout(chips).extent, expected, accuracy: 0.001)
    }

    func testWidgetIconsChipScalesWithTheNumberOfWidgets() {
        XCTAssertLessThan(layout([.widgetIcons], widgets: 2).extent,
                          layout([.widgetIcons], widgets: 6).extent)
    }

    func testWidgetIconsChipStillReservesRoomWithNoWidgets() {
        // An empty panel draws a placeholder glyph, so the handle can't collapse to nothing.
        XCTAssertGreaterThan(layout([.widgetIcons], widgets: 0).extent, IdleHandleLayout.endPadding * 2)
    }

    func testSideEdgesStackAndSoNeedLessRoomPerChipThanTopEdges() {
        // Stacked chips are shorter than the same chip rendered on one line.
        XCTAssertLessThan(IdleChip.clock.extent(growsHorizontally: true, widgetCount: 0),
                          IdleChip.clock.extent(growsHorizontally: false, widgetCount: 0))
        XCTAssertLessThan(layout([.clock, .cpu], edge: .trailing).extent,
                          layout([.clock, .cpu], edge: .top).extent)
    }

    func testOnlySystemBackedChipsRequestSampling() {
        XCTAssertEqual(Set(IdleChip.allCases.filter(\.needsMetrics)), [.cpu, .memory, .battery])
        XCTAssertEqual(Set(IdleChip.allCases.filter(\.needsMedia)), [.nowPlaying])
        for chip in [IdleChip.clock, .date, .clipboard, .widgetIcons] {
            XCTAssertFalse(chip.needsMetrics, "\(chip) should not poll")
            XCTAssertFalse(chip.needsMedia, "\(chip) should not poll")
        }
    }

    func testEveryPresetOnlyUsesKnownChipsAndHasNoDuplicates() {
        for preset in IdleChip.presets {
            XCTAssertEqual(Set(preset.chips).count, preset.chips.count, "\(preset.name) repeats a chip")
        }
        XCTAssertTrue(IdleChip.presets.contains { $0.chips.isEmpty }, "the plain line must stay reachable")
    }

    func testDefaultSettingsMatchAPresetSoTheMenuHasSomethingSelected() {
        let defaults = NotchlySettings().handleChips
        XCTAssertTrue(IdleChip.presets.contains { $0.chips == defaults })
    }
}
