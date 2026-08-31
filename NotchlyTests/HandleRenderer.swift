import XCTest
import SwiftUI
import AppKit
@testable import Notchly

/// A development aid rather than an assertion: rasterises the Idle handle in each
/// orientation so its layout can actually be looked at, which matters for a surface
/// that only ever appears at the very edge of a live display.
///
/// Skipped unless an output directory is provided:
///
///     TEST_RUNNER_NOTCHLY_RENDER_DIR=/tmp/render xcodebuild … \
///       test -only-testing:NotchlyTests/HandleRenderer
@MainActor
final class HandleRenderer: XCTestCase {
    func testRenderHandles() throws {
        guard let outDir = ProcessInfo.processInfo.environment["NOTCHLY_RENDER_DIR"] else {
            throw XCTSkip("Set NOTCHLY_RENDER_DIR to render the handle previews.")
        }
        let environment = AppEnvironment()
        let settings = SettingsStore.shared

        let cases: [(String, ScreenEdge, [IdleChip])] = [
            ("trailing-clock-media", .trailing, [.clock, .nowPlaying]),
            ("trailing-everything", .trailing, [.clock, .nowPlaying, .cpu, .memory, .battery]),
            ("trailing-icons", .trailing, [.widgetIcons]),
            ("top-everything", .top, [.clock, .nowPlaying, .cpu, .memory, .battery])
        ]

        for (name, edge, chips) in cases {
            let layout = IdleHandleLayout.resolve(chips: chips, edge: edge,
                                                  lineThickness: 5, lineLength: 108,
                                                  contentThickness: 30,
                                                  widgetCount: 5)
            let ir: CGFloat = min(9, layout.depth * 0.3)
            let size = edge.growsHorizontally
                ? CGSize(width: layout.depth, height: layout.extent + ir * 2)
                : CGSize(width: layout.extent + ir * 2, height: layout.depth)
            let shape = NotchShape(edge: edge, cornerRadius: min(layout.depth / 2, 13), inverseRadius: ir)

            let view = ZStack {
                Rectangle().fill(Theme.shellBackground)
                IdleHandleView(edge: edge, chips: chips)
                    .padding(edge.growsHorizontally ? .vertical : .horizontal, ir)
            }
            .frame(width: size.width, height: size.height)
            .clipShape(shape)
            .overlay(shape.stroke(Color.white.opacity(0.14), lineWidth: 0.75))
            .padding(18)
            .background(Color(sRGB: 0x2A3348))
            .environmentObject(environment)
            .environmentObject(settings)
            .environmentObject(environment.metrics)
            .environmentObject(environment.media)
            .environmentObject(environment.clipboard)
            .environmentObject(environment.catalog)
            .environmentObject(environment.registry)
            .environment(\.colorScheme, .dark)

            let renderer = ImageRenderer(content: view)
            renderer.scale = 4
            guard let image = renderer.nsImage, let data = image.notchlyPNGData() else {
                return XCTFail("render failed for \(name)")
            }
            try data.write(to: URL(fileURLWithPath: outDir).appendingPathComponent("\(name).png"))
        }

        try renderShadowComparison(into: outDir)
    }

    /// Renders the panel outline with the shadow treatment the real panel uses, over a
    /// bright ground where a rectangular halo would be obvious.
    private func renderShadowComparison(into outDir: String) throws {
        let shape = NotchShape(edge: .trailing, cornerRadius: 26, inverseRadius: 14)
        let offset = CGSize(width: -8, height: 4)

        let view = ZStack {
            shape
                .fill(Color.black.opacity(0.5))
                .blur(radius: 16)
                .offset(x: offset.width, y: offset.height)
            ZStack {
                Rectangle().fill(Theme.shellBackground.opacity(0.96))
            }
            .frame(width: 150, height: 240)
            .clipShape(shape)
            .overlay(shape.stroke(Theme.hairlineStrong, lineWidth: 0.75))
        }
        .frame(width: 150, height: 240)
        .padding(50)
        .background(Color(sRGB: 0xB43C8C))
        .environment(\.colorScheme, .dark)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        guard let image = renderer.nsImage, let data = image.notchlyPNGData() else {
            return XCTFail("shadow render failed")
        }
        try data.write(to: URL(fileURLWithPath: outDir).appendingPathComponent("shadow.png"))
    }
}
