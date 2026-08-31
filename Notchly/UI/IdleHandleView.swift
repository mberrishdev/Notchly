import SwiftUI

/// What the Panel shows while it is Idle.
///
/// The handle is a strip against the bezel, so the layout flips axis with the Edge:
/// chips stack in a column on the left and right, and sit in a row on the top and
/// bottom. Each chip renders differently in the two orientations rather than being
/// rotated, because rotated text is unreadable at this size.
struct IdleHandleView: View {
    let edge: ScreenEdge
    let chips: [IdleChip]

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var metrics: SystemMetrics
    @EnvironmentObject private var media: MediaController
    @EnvironmentObject private var clipboard: ClipboardService
    @EnvironmentObject private var registry: WidgetRegistry
    @EnvironmentObject private var settings: SettingsStore

    private var isStacked: Bool { edge.growsHorizontally }

    var body: some View {
        Group {
            if isStacked {
                VStack(spacing: IdleHandleLayout.spacing) { content }
                    .padding(.vertical, IdleHandleLayout.endPadding)
            } else {
                HStack(spacing: IdleHandleLayout.spacing) { content }
                    .padding(.horizontal, IdleHandleLayout.endPadding)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var content: some View {
        ForEach(chips) { chip in
            view(for: chip)
        }
    }

    @ViewBuilder
    private func view(for chip: IdleChip) -> some View {
        switch chip {
        case .clock: clock
        case .date: date
        case .cpu: reading(symbol: "cpu",
                           value: Format.percent(metrics.cpu.total),
                           tint: loadTint(metrics.cpu.total))
        case .memory: reading(symbol: "memorychip",
                              value: Format.percent(metrics.memory.fraction),
                              tint: loadTint(metrics.memory.fraction))
        case .battery: battery
        case .nowPlaying: nowPlaying
        case .clipboard: reading(symbol: "doc.on.clipboard",
                                 value: "\(clipboard.items.count)",
                                 tint: Theme.secondaryText)
        case .widgetIcons: widgetIcons
        }
    }

    private var clock: some View {
        // Follows whatever the Clock widget is set to, so the two never disagree.
        let use24Hour = environment.widgetSetting(key: "format", widgetID: "clock")?
            .stringValue != "12-hour"
        return TimelineView(.periodic(from: .now, by: 20)) { context in
            let hour = (use24Hour ? Self.hour24Formatter : Self.hour12Formatter).string(from: context.date)
            let minute = Self.minuteFormatter.string(from: context.date)
            if isStacked {
                VStack(spacing: -1) {
                    Text(hour)
                    Text(minute).foregroundStyle(Theme.secondaryText)
                }
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.primaryText)
            } else {
                Text("\(hour):\(minute)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.primaryText)
            }
        }
    }

    private var date: some View {
        TimelineView(.periodic(from: .now, by: 600)) { context in
            let day = Self.dayFormatter.string(from: context.date)
            let weekday = Self.weekdayFormatter.string(from: context.date)
            if isStacked {
                VStack(spacing: -1) {
                    Text(day).font(.system(size: 11, weight: .semibold, design: .rounded))
                    Text(weekday).font(.system(size: 8, weight: .medium))
                        .foregroundStyle(Theme.tertiaryText)
                }
                .foregroundStyle(Theme.primaryText)
            } else {
                HStack(spacing: 3) {
                    Text(weekday).font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Theme.tertiaryText)
                    Text(day).font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.primaryText)
                }
            }
        }
    }

    private func reading(symbol: String, value: String, tint: Color) -> some View {
        Group {
            if isStacked {
                VStack(spacing: 1) {
                    Image(systemName: symbol).font(.system(size: 9, weight: .medium))
                    Text(value).font(.system(size: 9, weight: .semibold))
                }
            } else {
                HStack(spacing: 3) {
                    Image(systemName: symbol).font(.system(size: 9, weight: .medium))
                    Text(value).font(.system(size: 10, weight: .semibold))
                }
            }
        }
        .monospacedDigit()
        .foregroundStyle(tint)
    }

    private var battery: some View {
        let sample = metrics.battery
        // A machine with no battery reads 0%, which must not be shown as critical.
        let tint: Color = {
            guard sample.isPresent else { return Theme.tertiaryText }
            if sample.isCharging { return Theme.healthy }
            if sample.percentage < 0.15 { return Theme.danger }
            if sample.percentage < 0.3 { return Theme.caution }
            return Theme.secondaryText
        }()
        let symbol = sample.isPresent
            ? (sample.isCharging ? "bolt.fill" : "battery.100")
            : "powerplug"
        return reading(symbol: symbol,
                       value: sample.isPresent ? Format.percent(sample.percentage) : "AC",
                       tint: tint)
    }

    /// A three-bar meter that animates only while something is actually playing —
    /// perpetual motion in the corner of the eye is exhausting.
    private var nowPlaying: some View {
        let isPlaying = media.nowPlaying?.isPlaying ?? false
        return TimelineView(.animation(minimumInterval: 0.18, paused: !isPlaying)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<3, id: \.self) { index in
                    Capsule()
                        .fill(isPlaying ? settings.settings.accentColor : Theme.tertiaryText)
                        .frame(width: 2, height: barHeight(index: index, phase: phase, playing: isPlaying))
                }
            }
            .frame(width: 12, height: 12)
        }
    }

    private func barHeight(index: Int, phase: TimeInterval, playing: Bool) -> CGFloat {
        guard playing else { return index == 1 ? 7 : 4 }
        let wave = sin(phase * 5 + Double(index) * 1.4)
        return 4 + CGFloat((wave + 1) / 2) * 7
    }

    private var widgetIcons: some View {
        let symbols = registry.activeSlots().map(\.descriptor.symbol)
        return Group {
            if isStacked {
                VStack(spacing: 6) { icons(symbols) }
            } else {
                HStack(spacing: 7) { icons(symbols) }
            }
        }
    }

    @ViewBuilder
    private func icons(_ symbols: [String]) -> some View {
        if symbols.isEmpty {
            Image(systemName: "square.dashed")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.tertiaryText)
        } else {
            ForEach(Array(symbols.enumerated()), id: \.offset) { _, symbol in
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }

    private func loadTint(_ value: Double) -> Color {
        switch value {
        case ..<0.6: return Theme.secondaryText
        case ..<0.85: return Theme.caution
        default: return Theme.danger
        }
    }

    private static let hour24Formatter = formatter("HH")
    private static let hour12Formatter = formatter("h")
    private static let minuteFormatter = formatter("mm")
    private static let dayFormatter = formatter("d")
    private static let weekdayFormatter = formatter("EEE")

    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        return formatter
    }
}
