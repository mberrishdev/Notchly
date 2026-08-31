import SwiftUI
import UniformTypeIdentifiers

struct SlotDropDelegate: DropDelegate {
    let target: WidgetSlot
    let settings: SettingsStore
    @Binding var dragging: UUID?

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != target.id,
              let from = settings.settings.slots.firstIndex(where: { $0.id == dragging }),
              let to = settings.settings.slots.firstIndex(where: { $0.id == target.id }) else { return }
        withAnimation(.easeOut(duration: 0.18)) {
            let moved = settings.settings.slots.remove(at: from)
            settings.settings.slots.insert(moved, at: to)
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}

/// Renders a widget's declared preferences as native controls. Built-ins and custom
/// widgets both go through this, so a folder you drop in gets first-class settings UI.
