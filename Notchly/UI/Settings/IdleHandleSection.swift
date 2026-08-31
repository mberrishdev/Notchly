import SwiftUI

/// Chooses what the Panel shows while it is closed — the plain line, or an ordered set
/// of chips. Mirrors the widget list's shape so reordering works the same way in both.
struct IdleHandleSection: View {
    @EnvironmentObject private var settings: SettingsStore
    @State private var dragging: IdleChip?

    private var chips: [IdleChip] { settings.settings.handleChips }
    private var available: [IdleChip] { IdleChip.allCases.filter { !chips.contains($0) } }

    var body: some View {
        SettingsSection(title: "Idle handle", footer: footer) {
            LabeledControl(label: "Preset") {
                Menu(currentPresetName) {
                    ForEach(IdleChip.presets, id: \.name) { preset in
                        Button(preset.name) { settings.settings.handleChips = preset.chips }
                    }
                }
                .frame(width: 160)
            }

            Divider()

            if chips.isEmpty {
                Text("The handle is a plain line. Add something below to make it show information.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                ValueSlider(label: "Line thickness", value: $settings.settings.handleThickness, range: 2...16)
                ValueSlider(label: "Line length", value: $settings.settings.handleLength, range: 40...320)
            } else {
                VStack(spacing: 4) {
                    ForEach(chips) { chip in
                        chipRow(chip)
                    }
                }
                ValueSlider(label: "Thickness",
                            help: "How far the handle reaches out from the edge.",
                            value: $settings.settings.handleContentThickness, range: 20...56)
            }

            if !available.isEmpty {
                Divider()
                Text("ADD")
                    .font(.system(size: 9.5, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(.tertiary)
                FlowRow(spacing: 6) {
                    ForEach(available) { chip in
                        Button {
                            settings.settings.handleChips.append(chip)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: chip.symbol).font(.system(size: 9))
                                Text(chip.label).font(.system(size: 11))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.primary.opacity(0.07)))
                        }
                        .buttonStyle(.plain)
                        .help(chip.detail)
                    }
                }
            }
        }
    }

    private var footer: String {
        let live = chips.filter { $0.needsMetrics || $0.needsMedia }
        guard !live.isEmpty else {
            return "Nothing here needs polling, so a closed panel costs nothing."
        }
        let names = live.map(\.label).joined(separator: ", ")
        return "\(names) keep sampling while the panel is closed, at a slower rate than when it is open."
    }

    private var currentPresetName: String {
        IdleChip.presets.first { $0.chips == chips }?.name ?? "Custom"
    }

    private func chipRow(_ chip: IdleChip) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Image(systemName: chip.symbol)
                .frame(width: 18)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 1) {
                Text(chip.label).font(.system(size: 12, weight: .medium))
                Text(chip.detail).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Button {
                settings.settings.handleChips.removeAll { $0 == chip }
            } label: {
                Image(systemName: "minus.circle").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove from the handle")
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(dragging == chip ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.03))
        )
        .contentShape(Rectangle())
        .onDrag {
            dragging = chip
            return NSItemProvider(object: chip.rawValue as NSString)
        }
        .onDrop(of: [.text], delegate: ChipDropDelegate(target: chip, settings: settings, dragging: $dragging))
    }
}

/// Reorders handle chips as a dragged row passes over its neighbours.
struct ChipDropDelegate: DropDelegate {
    let target: IdleChip
    let settings: SettingsStore
    @Binding var dragging: IdleChip?

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != target,
              let from = settings.settings.handleChips.firstIndex(of: dragging),
              let to = settings.settings.handleChips.firstIndex(of: target) else { return }
        withAnimation(.easeOut(duration: 0.18)) {
            let moved = settings.settings.handleChips.remove(at: from)
            settings.settings.handleChips.insert(moved, at: to)
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
}
