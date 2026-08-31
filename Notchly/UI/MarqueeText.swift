import SwiftUI

struct MarqueeText: View {
    let text: String
    var font: Font
    var color: Color

    @State private var offset: CGFloat = 0
    @State private var overflow: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            Text(text)
                .font(font)
                .foregroundStyle(color)
                .lineLimit(1)
                .fixedSize()
                .offset(x: offset)
                .background(
                    GeometryReader { inner in
                        Color.clear.onAppear {
                            overflow = max(0, inner.size.width - geo.size.width)
                        }
                        .onChange(of: text) { _, _ in
                            offset = 0
                            overflow = max(0, inner.size.width - geo.size.width)
                        }
                    }
                )
                .frame(width: geo.size.width, alignment: .leading)
                .clipped()
                .onHover { hovering in
                    guard overflow > 0 else { return }
                    if hovering {
                        withAnimation(.linear(duration: Double(overflow) / 26).repeatForever(autoreverses: true)) {
                            offset = -overflow
                        }
                    } else {
                        withAnimation(.easeOut(duration: 0.25)) { offset = 0 }
                    }
                }
        }
        .frame(height: 17)
    }
}
