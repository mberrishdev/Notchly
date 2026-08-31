import SwiftUI

struct SystemWidget: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var metrics: SystemMetrics
    @EnvironmentObject private var settings: SettingsStore
    @State private var isCollapsed = false

    private var prefs: WidgetPreferences { WidgetPreferences(widgetID: "system", environment: environment) }

    var body: some View {
        WidgetCard(title: "System", symbol: "chart.bar.xaxis",
                   isCollapsible: true, isCollapsed: $isCollapsed,
                   content: { content },
                   accessory: {
                       Text(Format.duration(metrics.uptime) + " up")
                           .font(.system(size: 9.5, weight: .medium))
                           .monospacedDigit()
                           .foregroundStyle(Theme.tertiaryText)
                   })
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            cpuSection
            memorySection
            if prefs.bool("showDisk", default: true) { diskSection }
            if prefs.bool("showNetwork", default: true) { networkSection }
            if prefs.bool("showBattery", default: true), metrics.battery.isPresent { batterySection }
            if prefs.bool("showProcesses", default: true), !metrics.topProcesses.isEmpty { processSection }
        }
    }

    private var cpuSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("CPU")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
                Spacer(minLength: 8)
                Text(Format.percent(metrics.cpu.total))
                    .font(.system(size: 15, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.primaryText)
                    .contentTransition(.numericText())
            }
            Sparkline(values: metrics.cpuHistory, color: loadColor(metrics.cpu.total))
                .frame(height: 30)
            HStack(spacing: 10) {
                legend("user", metrics.cpu.user, settings.settings.accentColor)
                legend("sys", metrics.cpu.system, Theme.systemLoad)
                Spacer(minLength: 0)
            }
        }
    }

    private func legend(_ label: String, _ value: Double, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(label).font(.system(size: 9.5)).foregroundStyle(Theme.tertiaryText)
            Text(Format.percent(value))
                .font(.system(size: 9.5, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Theme.secondaryText)
        }
    }

    private var memorySection: some View {
        VStack(alignment: .leading, spacing: 5) {
            StatRow(label: "Memory",
                    value: Format.bytes(metrics.memory.used),
                    detail: "of \(Format.bytes(metrics.memory.total))")
            MeterBar(fraction: metrics.memory.fraction, color: pressureColor(metrics.memory.pressure))
            HStack(spacing: 10) {
                Text("compressed \(Format.bytes(metrics.memory.compressed))")
                Text("wired \(Format.bytes(metrics.memory.wired))")
                Spacer(minLength: 0)
            }
            .font(.system(size: 9.5))
            .foregroundStyle(Theme.tertiaryText)
        }
    }

    private var diskSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            StatRow(label: "Disk",
                    value: Format.bytes(metrics.disk.free) + " free",
                    detail: Format.percent(metrics.disk.fraction) + " used")
            MeterBar(fraction: metrics.disk.fraction,
                     color: metrics.disk.fraction > 0.9 ? Theme.danger : Theme.healthy)
        }
    }

    private var networkSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text("Network")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
                Spacer(minLength: 8)
                rateLabel("arrow.down", Format.rate(metrics.network.downBytesPerSecond), Theme.download)
                rateLabel("arrow.up", Format.rate(metrics.network.upBytesPerSecond), Theme.upload)
            }
            Sparkline(values: metrics.networkHistory, color: Theme.download, normalize: true)
                .frame(height: 22)
        }
    }

    private func rateLabel(_ symbol: String, _ text: String, _ color: Color) -> some View {
        HStack(spacing: 2) {
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(color)
            Text(text)
                .font(.system(size: 10, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Theme.secondaryText)
        }
    }

    private var batterySection: some View {
        let battery = metrics.battery
        return HStack(spacing: 10) {
            ZStack {
                RingGauge(fraction: battery.percentage, color: batteryColor(battery), lineWidth: 3.5)
                Image(systemName: battery.isCharging ? "bolt.fill" : "battery.100")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(batteryColor(battery))
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(Format.percent(battery.percentage))
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.primaryText)
                Text(batteryDetail(battery))
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.tertiaryText)
            }
            Spacer(minLength: 0)
            if let cycles = battery.cycleCount {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(cycles)")
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(Theme.secondaryText)
                    Text("cycles")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.tertiaryText)
                }
            }
        }
    }

    private func batteryDetail(_ battery: BatterySample) -> String {
        if battery.isCharging {
            if let minutes = battery.minutesRemaining { return "\(Format.minutes(minutes)) to full" }
            return "Charging"
        }
        if battery.isPluggedIn { return "Plugged in" }
        if let minutes = battery.minutesRemaining { return "\(Format.minutes(minutes)) remaining" }
        return battery.health ?? "On battery"
    }

    private var processSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("TOP PROCESSES")
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Theme.tertiaryText)
                .padding(.top, 2)
            ForEach(metrics.topProcesses.prefix(3)) { process in
                HStack(spacing: 6) {
                    Text(process.name)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    Text(Format.bytes(process.memory))
                        .font(.system(size: 9.5))
                        .monospacedDigit()
                        .foregroundStyle(Theme.tertiaryText)
                    Text(Format.percent(process.cpu))
                        .font(.system(size: 10, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(loadColor(process.cpu))
                        .frame(width: 38, alignment: .trailing)
                }
            }
        }
    }

    private func loadColor(_ value: Double) -> Color {
        switch value {
        case ..<0.5: return settings.settings.accentColor
        case ..<0.8: return Theme.caution
        default: return Theme.danger
        }
    }

    private func pressureColor(_ value: Double) -> Color {
        value > 0.75 ? Theme.danger : (value > 0.5 ? Theme.caution : Theme.healthy)
    }

    private func batteryColor(_ battery: BatterySample) -> Color {
        if battery.isCharging { return Theme.healthy }
        if battery.percentage < 0.15 { return Theme.danger }
        if battery.percentage < 0.3 { return Theme.caution }
        return Theme.primaryText
    }
}
