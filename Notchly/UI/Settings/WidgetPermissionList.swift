import SwiftUI
import UniformTypeIdentifiers

struct WidgetPermissionList: View {
    let descriptor: WidgetDescriptor
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        let requested = descriptor.requestedPermissions.sorted { $0.rawValue < $1.rawValue }
        VStack(alignment: .leading, spacing: 7) {
            Text("PERMISSIONS")
                .font(.system(size: 9.5, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(.tertiary)

            if requested.isEmpty {
                Text("This widget asked for nothing beyond drawing itself.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            ForEach(requested, id: \.self) { permission in
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: permission.symbol)
                        .font(.system(size: 11))
                        .frame(width: 16)
                        .foregroundStyle(permission == .shell ? Color.orange : .secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(permission.label).font(.system(size: 11.5, weight: .medium))
                        Text(permission.detail)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    if permission.requiresExplicitGrant {
                        Toggle("", isOn: Binding(
                            get: { environment.isPermissionGranted(permission, for: descriptor.id) },
                            set: { environment.setPermission(permission, granted: $0, for: descriptor.id) }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                    } else {
                        Text("Granted")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }
}
