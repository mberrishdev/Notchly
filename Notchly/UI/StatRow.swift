import AppKit
import SwiftUI

struct StatRow: View {
    let label: String
    let value: String
    var detail: String?

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondaryText)
            Spacer(minLength: 8)
            if let detail {
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.tertiaryText)
            }
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Theme.primaryText)
        }
    }
}

struct EmptyStateView: View {
    let symbol: String
    let title: String
    var detail: String?

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(Theme.tertiaryText)
            Text(title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Theme.secondaryText)
            if let detail {
                Text(detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.tertiaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }
}

/// AppKit-backed search field: SwiftUI's TextField won't take first responder reliably
/// inside a non-activating panel, and this also gives us arrow-key handling for free.
