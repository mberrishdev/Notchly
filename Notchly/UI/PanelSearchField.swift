import AppKit
import SwiftUI

struct PanelSearchField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var focusToken: Int
    var onMove: ((Int) -> Void)?
    var onSubmit: (() -> Void)?
    var onCancel: (() -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.placeholderString = placeholder
        field.delegate = context.coordinator
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 12.5)
        field.textColor = .white
        field.cell?.usesSingleLineMode = true
        field.cell?.wraps = false
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text { nsView.stringValue = text }
        nsView.placeholderString = placeholder
        context.coordinator.parent = self
        if context.coordinator.appliedToken != focusToken {
            context.coordinator.appliedToken = focusToken
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: PanelSearchField
        var appliedToken = -1

        init(_ parent: PanelSearchField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.moveDown(_:)): parent.onMove?(1); return true
            case #selector(NSResponder.moveUp(_:)): parent.onMove?(-1); return true
            case #selector(NSResponder.insertNewline(_:)): parent.onSubmit?(); return true
            case #selector(NSResponder.cancelOperation(_:)): parent.onCancel?(); return true
            default: return false
            }
        }
    }

}
