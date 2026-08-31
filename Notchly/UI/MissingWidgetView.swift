import SwiftUI

struct MissingWidgetView: View {
    let name: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "questionmark.square.dashed")
                .foregroundStyle(Theme.tertiaryText)
            Text("\(name) is unavailable")
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondaryText)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
    }
}
