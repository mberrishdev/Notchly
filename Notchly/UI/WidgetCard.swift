import AppKit
import SwiftUI

struct WidgetCard<Content: View, Accessory: View>: View {
    let title: String
    let symbol: String
    var isCollapsible: Bool = false
    @Binding var isCollapsed: Bool
    @ViewBuilder var content: () -> Content
    @ViewBuilder var accessory: () -> Accessory

    @State private var isHovering = false

    init(title: String, symbol: String,
         isCollapsible: Bool = false,
         isCollapsed: Binding<Bool> = .constant(false),
         @ViewBuilder content: @escaping () -> Content,
         @ViewBuilder accessory: @escaping () -> Accessory) {
        self.title = title
        self.symbol = symbol
        self.isCollapsible = isCollapsible
        self._isCollapsed = isCollapsed
        self.content = content
        self.accessory = accessory
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if !isCollapsed {
                content()
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .fill(isHovering ? Theme.cardBackgroundHover : Theme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 0.5)
        )
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.14)) { isHovering = hovering }
        }
    }

    private var header: some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.tertiaryText)
                .frame(width: 13)
            Text(title.uppercased())
                .font(.system(size: 9.5, weight: .semibold))
                .tracking(0.7)
                .foregroundStyle(Theme.tertiaryText)
            Spacer(minLength: 6)
            accessory()
            if isCollapsible {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Theme.tertiaryText)
                    .rotationEffect(.degrees(isCollapsed ? -90 : 0))
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, isCollapsed ? 10 : 8)
        .contentShape(Rectangle())
        .onTapGesture {
            guard isCollapsible else { return }
            withAnimation(Theme.contentTransition) { isCollapsed.toggle() }
        }
    }
}

extension WidgetCard where Accessory == EmptyView {
    init(title: String, symbol: String, isCollapsible: Bool = false,
         isCollapsed: Binding<Bool> = .constant(false),
         @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, symbol: symbol, isCollapsible: isCollapsible,
                  isCollapsed: isCollapsed, content: content, accessory: { EmptyView() })
    }
}
