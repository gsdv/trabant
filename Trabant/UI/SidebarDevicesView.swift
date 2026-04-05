import SwiftUI

struct SidebarDevicesView: View {
    @Environment(AppState.self) var appState
    @State private var renamingDeviceIP: String?
    @State private var renameText = ""

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 14) {
                sidebarHeader

                if appState.captureStore.devices.isEmpty {
                    Spacer(minLength: 0)
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 8) {
                            deviceButton(
                                name: "All Devices",
                                count: appState.captureStore.visibleSessions.count,
                                lastSeen: appState.captureStore.visibleSessions.first?.session.requestTimestamp,
                                isSelected: appState.selectedDeviceIP == nil,
                                symbolName: "square.stack.3d.up.fill",
                                subtitle: "Combined traffic"
                            ) {
                                appState.selectedDeviceIP = nil
                            }

                            ForEach(appState.captureStore.devices) { device in
                                let visibleSessions = appState.captureStore.visibleSessionsForDevice(device.ipAddress)
                                deviceButton(
                                    name: device.displayName,
                                    count: visibleSessions.count,
                                    lastSeen: device.lastSeenAt,
                                    isSelected: appState.selectedDeviceIP == device.ipAddress,
                                    symbolName: symbolName(for: device.displayName, ip: device.ipAddress),
                                    subtitle: appState.redactedModeEnabled ? Redactor.redactIP(device.ipAddress) : device.ipAddress
                                ) {
                                    appState.selectedDeviceIP = device.ipAddress
                                }
                                .contextMenu {
                                    Button("Rename...") {
                                        renameText = device.customName ?? ""
                                        renamingDeviceIP = device.ipAddress
                                    }
                                    if device.customName != nil {
                                        Button("Reset Name") {
                                            appState.captureStore.renameDevice(device.ipAddress, to: nil)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(2)
                    }
                }

                Spacer(minLength: 0)
            }

            if appState.captureStore.devices.isEmpty {
                DashboardEmptyState(
                    systemName: "wifi.slash",
                    title: "No devices yet",
                    //subtitle: "Configure a device to proxy through \(appState.localIP):\(appState.proxyPort).",
                    iconSize: 28,
                    subtitleMaxWidth: 220
                )
                .allowsHitTesting(false)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.clear)
        .alert("Rename Device", isPresented: Binding(
            get: { renamingDeviceIP != nil },
            set: { if !$0 { renamingDeviceIP = nil } }
        )) {
            TextField("Device name", text: $renameText)
            Button("Save") {
                if let ip = renamingDeviceIP {
                    appState.captureStore.renameDevice(ip, to: renameText)
                }
                renamingDeviceIP = nil
            }
            Button("Cancel", role: .cancel) {
                renamingDeviceIP = nil
            }
        } message: {
            if let ip = renamingDeviceIP {
                Text("Enter a name for \(appState.redactedModeEnabled ? Redactor.redactIP(ip) : ip)")
            }
        }
    }

    private var sidebarHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Label {
                    Text("Devices")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(TrabantTheme.primaryText)
                } icon: {
                    Image(systemName: "ipad.and.iphone")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(TrabantTheme.accentLight)
                }
            }

            Text(sidebarStatusText)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(TrabantTheme.secondaryText)
        }
    }

    private func deviceButton(
        name: String,
        count: Int,
        lastSeen: Date?,
        isSelected: Bool,
        symbolName: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            DeviceRow(
                name: name,
                subtitle: subtitle,
                count: count,
                lastSeen: lastSeen,
                isSelected: isSelected,
                symbolName: symbolName
            )
        }
        .buttonStyle(.plain)
    }

    private var sidebarStatusText: String {
        let ip = appState.redactedModeEnabled ? Redactor.redactIP(appState.localIP) : appState.localIP
        if appState.isProxyRunning {
            return "Listening on \(ip):\(appState.proxyPort)"
        }
        if appState.localIP == "No network" {
            return "Proxy stopped"
        }
        return "Ready on \(ip):\(appState.proxyPort)"
    }

    private func symbolName(for deviceName: String, ip: String) -> String {
        let lowercasedName = deviceName.lowercased()

        if lowercasedName.contains("ipad") {
            return "ipad.landscape"
        }
        if lowercasedName.contains("iphone") {
            return "iphone.gen3"
        }
        if lowercasedName.contains("watch") {
            return "applewatch"
        }
        if lowercasedName.contains("macbook") || lowercasedName.contains("mac") {
            return "laptopcomputer"
        }
        if lowercasedName.contains("tv") {
            return "tv"
        }
        if ip.hasPrefix("127.") {
            return "desktopcomputer"
        }
        return "network"
    }
}

private struct DeviceRow: View {
    let name: String
    let subtitle: String
    let count: Int
    let lastSeen: Date?
    let isSelected: Bool
    let symbolName: String

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? TrabantTheme.sidebarRowSelectedFill.opacity(0.85) : TrabantTheme.sidebarIconFill)

                Image(systemName: symbolName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isSelected ? TrabantTheme.accentLight : TrabantTheme.primaryText)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(TrabantTheme.primaryText)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(TrabantTheme.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 6) {
                Text("\(count)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(isSelected ? TrabantTheme.primaryText : TrabantTheme.sidebarBadgeText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        isSelected ? Color.white.opacity(0.12) : TrabantTheme.sidebarBadgeFill,
                        in: Capsule()
                    )

                if let lastSeen {
                    Text(lastSeen, style: .time)
                        .font(.system(size: 10))
                        .foregroundStyle(TrabantTheme.dimText)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(rowBackground)
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(rowBorder, lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder
    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(isSelected ? TrabantTheme.sidebarRowSelectedFill : TrabantTheme.sidebarRowFill)
            .shadow(color: isSelected ? TrabantTheme.accent.opacity(0.18) : .clear, radius: 14, y: 8)
    }

    private var rowBorder: Color {
        isSelected ? TrabantTheme.sidebarRowSelectedBorder : TrabantTheme.sidebarRowBorder
    }
}
