import AppKit
import SwiftUI

enum Theme {
    static let shellBackground = Color(sRGB: 0x0B0C0F)
    static let plateTop = Color(sRGB: 0x1C2130)
    static let plateBottom = Color(sRGB: 0x0B0D12)

    /// Semantic accents for readings the user should react to. Kept apart from the
    /// user's chosen accent colour, which carries no meaning of its own.
    static let danger = Color(sRGB: 0xFF6B6B)
    static let caution = Color(sRGB: 0xFFC46B)
    static let healthy = Color(sRGB: 0x7FD1AE)
    static let download = Color(sRGB: 0x7FB2FF)
    static let upload = Color(sRGB: 0xFFB86B)
    static let systemLoad = Color(sRGB: 0xFF8A65)
    static let cardBackground = Color.white.opacity(0.055)
    static let cardBackgroundHover = Color.white.opacity(0.085)
    static let hairline = Color.white.opacity(0.09)
    static let hairlineStrong = Color.white.opacity(0.16)

    static let primaryText = Color.white.opacity(0.95)
    static let secondaryText = Color.white.opacity(0.58)
    static let tertiaryText = Color.white.opacity(0.36)

    static let cardRadius: CGFloat = 14
    static let contentPadding: CGFloat = 14
    static let cardSpacing: CGFloat = 10

    static func openSpring(reduced: Bool) -> Animation {
        reduced ? .easeOut(duration: 0.16) : .spring(response: 0.38, dampingFraction: 0.78, blendDuration: 0.1)
    }

    static func closeSpring(reduced: Bool) -> Animation {
        reduced ? .easeIn(duration: 0.14) : .spring(response: 0.3, dampingFraction: 0.9)
    }

    static let contentTransition: Animation = .spring(response: 0.28, dampingFraction: 0.85)
}
