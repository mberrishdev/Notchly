import Foundation

/// One piece of information the Panel shows while it is Idle.
///
/// The handle is a strip, so every chip has to work in two orientations: stacked in a
/// narrow column on the left and right Edges, laid side by side on the top and bottom.
/// Each chip declares how much room it needs along the Edge in each case, which is what
/// lets the window frame be computed up front instead of measured after layout.
enum IdleChip: String, Codable, CaseIterable, Identifiable, Sendable {
    case clock
    case date
    case cpu
    case memory
    case battery
    case nowPlaying
    case clipboard
    case widgetIcons

    var id: String { rawValue }

    var label: String {
        switch self {
        case .clock: return "Time"
        case .date: return "Date"
        case .cpu: return "CPU"
        case .memory: return "Memory"
        case .battery: return "Battery"
        case .nowPlaying: return "Now playing"
        case .clipboard: return "Clipboard count"
        case .widgetIcons: return "Widget icons"
        }
    }

    var detail: String {
        switch self {
        case .clock: return "Hours and minutes, stacked on the side edges."
        case .date: return "Day of the month and the weekday."
        case .cpu: return "Total load, tinted as it climbs."
        case .memory: return "Memory in use as a share of the total."
        case .battery: return "Charge level, with a bolt while charging."
        case .nowPlaying: return "Lights up while something is playing."
        case .clipboard: return "How many entries are in the history."
        case .widgetIcons: return "One glyph per widget in your panel."
        }
    }

    var symbol: String {
        switch self {
        case .clock: return "clock"
        case .date: return "calendar"
        case .cpu: return "cpu"
        case .memory: return "memorychip"
        case .battery: return "battery.100"
        case .nowPlaying: return "waveform"
        case .clipboard: return "doc.on.clipboard"
        case .widgetIcons: return "square.grid.2x2"
        }
    }

    /// True when the chip's value has to be sampled from the system while the Panel is
    /// closed. Chips that don't need this cost nothing to display.
    var needsMetrics: Bool {
        switch self {
        case .cpu, .memory, .battery: return true
        default: return false
        }
    }

    var needsMedia: Bool { self == .nowPlaying }

    /// Room this chip needs along the Edge. Reserved whether or not the chip currently
    /// has a value, so the handle never resizes underneath the pointer.
    ///
    /// `growsHorizontally` is true on the left and right Edges, where chips are stacked
    /// in a column — so it asks for the chip's *height*. On the top and bottom Edges
    /// they sit side by side and it asks for the chip's *width*, which is larger for
    /// anything that renders text on one line.
    func extent(growsHorizontally: Bool, widgetCount: Int) -> CGFloat {
        if self == .widgetIcons {
            let each: CGFloat = growsHorizontally ? 19 : 21
            return max(each, each * CGFloat(widgetCount))
        }
        if growsHorizontally {
            switch self {
            case .clock, .date: return 30
            case .cpu, .memory, .battery: return 28
            case .nowPlaying, .clipboard: return 24
            case .widgetIcons: return 0
            }
        }
        switch self {
        case .clock: return 40
        case .date: return 44
        case .cpu, .memory, .battery: return 44
        case .nowPlaying: return 26
        case .clipboard: return 32
        case .widgetIcons: return 0
        }
    }

    /// Starting points offered in Settings, so the common cases are one click away.
    static let presets: [(name: String, chips: [IdleChip])] = [
        ("Line", []),
        ("Clock", [.clock]),
        ("Now playing", [.clock, .nowPlaying]),
        ("Widget icons", [.widgetIcons]),
        ("System", [.cpu, .memory, .battery]),
        ("Everything", [.clock, .nowPlaying, .cpu, .memory, .battery])
    ]
}
