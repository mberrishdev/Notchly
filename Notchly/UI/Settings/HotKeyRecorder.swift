import AppKit
import SwiftUI

struct HotKeyRecorder: View {
    @Binding var spec: HotkeySpec
    @State private var isRecording = false

    var body: some View {
        HStack(spacing: 8) {
            Button {
                isRecording.toggle()
            } label: {
                Text(isRecording ? "Press keys…" : HotKeyFormatter.describe(spec))
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 120, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(isRecording ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.07))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(isRecording ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .background(KeyCaptureView(isRecording: $isRecording) { keyCode, modifiers in
                spec = HotkeySpec(keyCode: keyCode, modifiers: modifiers, isEnabled: true)
                isRecording = false
            })

            Button("Clear") {
                spec = HotkeySpec(keyCode: 0, modifiers: 0, isEnabled: false)
            }
            .controlSize(.small)
            .disabled(!spec.isEnabled)
        }
    }
}

/// AppKit shim that swallows key events while recording so the shortcut isn't typed
/// into whatever field happens to be focused.

private struct KeyCaptureView: NSViewRepresentable {
    @Binding var isRecording: Bool
    let onCapture: (UInt32, UInt32) -> Void

    func makeNSView(context: Context) -> CaptureView {
        let view = CaptureView()
        view.onCapture = onCapture
        view.onCancel = { isRecording = false }
        return view
    }

    func updateNSView(_ nsView: CaptureView, context: Context) {
        nsView.onCapture = onCapture
        nsView.isRecording = isRecording
        if isRecording {
            DispatchQueue.main.async { nsView.window?.makeFirstResponder(nsView) }
        }
    }

    final class CaptureView: NSView {
        var onCapture: ((UInt32, UInt32) -> Void)?
        var onCancel: (() -> Void)?
        var isRecording = false

        override var acceptsFirstResponder: Bool { isRecording }

        override func keyDown(with event: NSEvent) {
            guard isRecording else { return super.keyDown(with: event) }
            if event.keyCode == 53 { onCancel?(); return }
            let modifiers = HotKeyFormatter.carbonModifiers(from: event.modifierFlags)
            // A bare key would fire constantly; require at least one modifier.
            guard modifiers != 0 else { NSSound.beep(); return }
            onCapture?(UInt32(event.keyCode), modifiers)
        }

        override func flagsChanged(with event: NSEvent) {
            guard !isRecording else { return }
            super.flagsChanged(with: event)
        }
    }
}
