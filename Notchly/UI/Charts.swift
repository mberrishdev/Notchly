import AppKit
import SwiftUI

struct Sparkline: View {
    let values: [Double]
    var color: Color
    var normalize: Bool = false

    var body: some View {
        GeometryReader { geo in
            let peak = normalize ? max(values.max() ?? 1, 1) : 1
            let points = pointList(in: geo.size, peak: peak)
            ZStack {
                if points.count > 1 {
                    fillPath(points, in: geo.size)
                        .fill(LinearGradient(colors: [color.opacity(0.28), color.opacity(0.01)],
                                             startPoint: .top, endPoint: .bottom))
                    linePath(points)
                        .stroke(color.opacity(0.85), style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                }
            }
        }
    }

    private func pointList(in size: CGSize, peak: Double) -> [CGPoint] {
        guard values.count > 1 else { return [] }
        let step = size.width / CGFloat(values.count - 1)
        return values.enumerated().map { index, value in
            let clamped = min(max(value / peak, 0), 1)
            return CGPoint(x: CGFloat(index) * step, y: size.height * (1 - CGFloat(clamped)))
        }
    }

    private func linePath(_ points: [CGPoint]) -> Path {
        var path = Path()
        path.move(to: points[0])
        for point in points.dropFirst() { path.addLine(to: point) }
        return path
    }

    private func fillPath(_ points: [CGPoint], in size: CGSize) -> Path {
        var path = linePath(points)
        path.addLine(to: CGPoint(x: points.last!.x, y: size.height))
        path.addLine(to: CGPoint(x: points.first!.x, y: size.height))
        path.closeSubpath()
        return path
    }
}

/// Slim capsule meter used for memory and disk.

struct MeterBar: View {
    let fraction: Double
    var color: Color
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.09))
                Capsule()
                    .fill(LinearGradient(colors: [color.opacity(0.75), color],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(height, geo.size.width * CGFloat(min(max(fraction, 0), 1))))
            }
        }
        .frame(height: height)
        .animation(.easeOut(duration: 0.45), value: fraction)
    }
}

struct RingGauge: View {
    let fraction: Double
    var color: Color
    var lineWidth: CGFloat = 4
    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.1), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(min(max(fraction, 0), 1)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.45), value: fraction)
        }
    }
}

/// Label/value pair, aligned so a column of them lines up.
