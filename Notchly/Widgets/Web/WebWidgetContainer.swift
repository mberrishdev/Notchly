import SwiftUI

struct WebWidgetContainer: View {
    let package: WebWidgetPackage

    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var settings: SettingsStore
    @State private var height: CGFloat = 0
    @State private var isCollapsed = false

    private var descriptor: WidgetDescriptor { package.descriptor }

    private var resolvedHeight: CGFloat {
        let requested = package.manifest.height.map { CGFloat($0) } ?? height
        let minimum = package.manifest.minHeight.map { CGFloat($0) } ?? 40
        let maximum = package.manifest.maxHeight.map { CGFloat($0) } ?? 520
        return min(max(requested == 0 ? 120 : requested, minimum), maximum)
    }

    var body: some View {
        WidgetCard(title: descriptor.name, symbol: descriptor.symbol,
                   isCollapsible: true, isCollapsed: $isCollapsed,
                   content: { body(for: package) },
                   accessory: {
                       HStack(spacing: 6) {
                           if !ungrantedPermissions.isEmpty {
                               Image(systemName: "lock.fill")
                                   .font(.system(size: 8.5))
                                   .foregroundStyle(Theme.caution)
                                   .help("Waiting on: " + ungrantedPermissions.map(\.label).joined(separator: ", "))
                           }
                           Button { environment.webWidgets.bumpRevision(for: package.id) } label: {
                               Image(systemName: "arrow.clockwise")
                                   .font(.system(size: 9, weight: .semibold))
                                   .foregroundStyle(Theme.tertiaryText)
                           }
                           .buttonStyle(.plain)
                           .help("Reload \(descriptor.name)")
                       }
                   })
    }

    private var ungrantedPermissions: [WidgetPermission] {
        descriptor.requestedPermissions
            .filter(\.requiresExplicitGrant)
            .filter { !environment.isPermissionGranted($0, for: package.id) }
            .sorted { $0.rawValue < $1.rawValue }
    }

    private func body(for package: WebWidgetPackage) -> some View {
        WebWidgetView(package: package, environment: environment, measuredHeight: $height)
            .frame(height: resolvedHeight)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .animation(.spring(response: 0.32, dampingFraction: 0.85), value: resolvedHeight)
    }
}
