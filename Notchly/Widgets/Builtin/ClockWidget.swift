import SwiftUI

struct ClockWidget: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var settings: SettingsStore

    private var prefs: WidgetPreferences { WidgetPreferences(widgetID: "clock", environment: environment) }

    var body: some View {
        let showSeconds = prefs.bool("showSeconds", default: false)
        let use24Hour = prefs.string("format", default: "24-hour") == "24-hour"
        let secondaryZone = prefs.string("secondaryTimeZone", default: "")

        WidgetCard(title: "Clock", symbol: "clock") {
            TimelineView(.periodic(from: .now, by: showSeconds ? 1 : 30)) { context in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text(primaryTime(context.date, use24Hour: use24Hour, seconds: showSeconds))
                            .font(.system(size: 34, weight: .light, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Theme.primaryText)
                            .contentTransition(.numericText())
                        if !use24Hour {
                            Text(meridiem(context.date))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Theme.tertiaryText)
                                .padding(.bottom, 3)
                        }
                        Spacer(minLength: 0)
                    }

                    HStack(spacing: 6) {
                        Text(dateLine(context.date))
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(Theme.secondaryText)
                        Spacer(minLength: 0)
                        Text(weekLine(context.date))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Theme.tertiaryText)
                    }

                    if let zone = resolvedZone(secondaryZone) {
                        Divider().overlay(Theme.hairline)
                        HStack(spacing: 6) {
                            Image(systemName: "globe")
                                .font(.system(size: 9.5))
                                .foregroundStyle(Theme.tertiaryText)
                            Text(zoneLabel(zone))
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.secondaryText)
                            Spacer(minLength: 8)
                            Text(secondaryTime(context.date, zone: zone, use24Hour: use24Hour))
                                .font(.system(size: 12, weight: .medium))
                                .monospacedDigit()
                                .foregroundStyle(Theme.primaryText)
                            Text(offsetLabel(zone))
                                .font(.system(size: 9.5))
                                .foregroundStyle(Theme.tertiaryText)
                        }
                    }
                }
                .animation(.easeOut(duration: 0.2), value: showSeconds)
            }
        }
    }

    private func primaryTime(_ date: Date, use24Hour: Bool, seconds: Bool) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: use24Hour ? "en_GB" : "en_US_POSIX")
        formatter.dateFormat = use24Hour
            ? (seconds ? "HH:mm:ss" : "HH:mm")
            : (seconds ? "h:mm:ss" : "h:mm")
        return formatter.string(from: date)
    }

    private func meridiem(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "a"
        return formatter.string(from: date)
    }

    private func dateLine(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    private func weekLine(_ date: Date) -> String {
        let week = Calendar.current.component(.weekOfYear, from: date)
        return "Week \(week)"
    }

    private func resolvedZone(_ identifier: String) -> TimeZone? {
        let trimmed = identifier.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return TimeZone(identifier: trimmed) ?? TimeZone(abbreviation: trimmed.uppercased())
    }

    private func zoneLabel(_ zone: TimeZone) -> String {
        zone.identifier.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") } ?? zone.identifier
    }

    private func secondaryTime(_ date: Date, zone: TimeZone, use24Hour: Bool) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: use24Hour ? "en_GB" : "en_US_POSIX")
        formatter.dateFormat = use24Hour ? "HH:mm" : "h:mm a"
        formatter.timeZone = zone
        return formatter.string(from: date)
    }

    private func offsetLabel(_ zone: TimeZone) -> String {
        let delta = (zone.secondsFromGMT() - TimeZone.current.secondsFromGMT()) / 3600
        if delta == 0 { return "same" }
        return delta > 0 ? "+\(delta)h" : "\(delta)h"
    }
}
