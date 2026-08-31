import SwiftUI
import UniformTypeIdentifiers

struct WidgetSettingsPane: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var registry: WidgetRegistry

    @State private var expandedSlot: UUID?
    @State private var draggingSlot: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSection(title: "In your panel",
                            footer: "Drag rows to reorder. The panel updates as you go.") {
                if settings.settings.slots.isEmpty {
                    Text("No widgets yet — add one below.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 4) {
                        ForEach(settings.settings.slots) { slot in
                            slotRow(slot)
                        }
                    }
                }
            }

            SettingsSection(title: "Available") {
                let available = registry.availableDescriptors()
                if available.isEmpty {
                    Text("Every widget Notchly knows about is already in your panel.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 4) {
                        ForEach(available) { descriptor in
                            HStack(spacing: 10) {
                                Image(systemName: descriptor.symbol)
                                    .frame(width: 18)
                                    .foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(descriptor.name).font(.system(size: 12, weight: .medium))
                                    Text(descriptor.summary)
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 8)
                                if descriptor.kind == .web {
                                    Text("Custom")
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 5).padding(.vertical, 2)
                                        .background(Capsule().fill(Color.primary.opacity(0.08)))
                                }
                                Button("Add") { add(descriptor) }
                                    .controlSize(.small)
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }
            }
        }
    }

    private func slotRow(_ slot: WidgetSlot) -> some View {
        let descriptor = registry.descriptor(for: slot.widgetID)
        let isExpanded = expandedSlot == slot.id

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)

                Image(systemName: descriptor?.symbol ?? "questionmark.square.dashed")
                    .frame(width: 18)
                    .foregroundStyle(slot.isEnabled ? Color.accentColor : .secondary)

                VStack(alignment: .leading, spacing: 1) {
                    Text(descriptor?.name ?? slot.widgetID)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(descriptor == nil ? .secondary : .primary)
                    Text(descriptor?.summary ?? "This widget is no longer installed.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if let descriptor, !descriptor.settingsSchema.isEmpty || descriptor.kind == .web {
                    Button {
                        withAnimation(.easeOut(duration: 0.18)) {
                            expandedSlot = isExpanded ? nil : slot.id
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Toggle("", isOn: binding(for: slot.id))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)

                Button {
                    remove(slot)
                } label: {
                    Image(systemName: "minus.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Remove from panel")
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(draggingSlot == slot.id ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.03))
            )
            .contentShape(Rectangle())

            if isExpanded, let descriptor {
                VStack(alignment: .leading, spacing: 10) {
                    if !descriptor.settingsSchema.isEmpty {
                        WidgetSettingsForm(descriptor: descriptor)
                    }
                    if descriptor.kind == .web {
                        WidgetPermissionList(descriptor: descriptor)
                    }
                }
                .padding(.leading, 36)
                .padding(.trailing, 8)
                .padding(.vertical, 10)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .onDrag {
            draggingSlot = slot.id
            return NSItemProvider(object: slot.id.uuidString as NSString)
        }
        .onDrop(of: [.text], delegate: SlotDropDelegate(target: slot,
                                                        settings: settings,
                                                        dragging: $draggingSlot))
    }

    private func binding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { settings.settings.slots.first { $0.id == id }?.isEnabled ?? false },
            set: { newValue in
                guard let index = settings.settings.slots.firstIndex(where: { $0.id == id }) else { return }
                settings.settings.slots[index].isEnabled = newValue
            }
        )
    }

    private func add(_ descriptor: WidgetDescriptor) {
        settings.settings.slots.append(WidgetSlot(kind: descriptor.kind, widgetID: descriptor.id))
    }

    private func remove(_ slot: WidgetSlot) {
        settings.settings.slots.removeAll { $0.id == slot.id }
        if expandedSlot == slot.id { expandedSlot = nil }
    }
}

/// Reorders slots as a dragged row passes over its neighbours.
