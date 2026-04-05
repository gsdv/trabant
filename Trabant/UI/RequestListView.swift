import SwiftUI

struct RequestListView: View {
    @Environment(AppState.self) var appState
    @Environment(\.openWindow) private var openWindow
    @State private var filterText = ""
    @State private var contextMenuSessionID: UUID?

    private var needsOnboarding: Bool {
        !appState.certificateStatus.isReady || !appState.isProxyRunning || appState.captureStore.devices.isEmpty
    }

    private var filteredSessions: [DisplayedProxySession] {
        let base: [DisplayedProxySession]
        if let deviceIP = appState.selectedDeviceIP {
            base = appState.captureStore.visibleSessionsForDevice(deviceIP)
        } else {
            base = appState.captureStore.visibleSessions
        }

        if filterText.isEmpty { return base }
        let query = filterText.lowercased()
        return base.filter {
            $0.session.host.lowercased().contains(query) || $0.session.path.lowercased().contains(query)
        }
    }

    var body: some View {
        @Bindable var appState = appState

        ZStack {
            VStack(spacing: 0) {
                HStack {
                    Text("Requests")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(TrabantTheme.secondaryText)
                    Spacer()
                    Text("\(filteredSessions.count)")
                        .font(TrabantTheme.monoSmall)
                        .foregroundStyle(TrabantTheme.dimText)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(TrabantTheme.dimText)
                    TextField("Filter host/path...", text: $filterText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(TrabantTheme.primaryText)
                    if !filterText.isEmpty {
                        Button(action: { filterText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(TrabantTheme.dimText)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(TrabantTheme.windowBackground)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .padding(.horizontal, 8)
                .padding(.bottom, 6)

                Divider().background(TrabantTheme.separator)

                if filteredSessions.isEmpty && filterText.isEmpty && appState.captureStore.visibleSessions.isEmpty && needsOnboarding {
                    OnboardingCardView()
                } else if filteredSessions.isEmpty {
                    Spacer(minLength: 0)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 1) {
                            ForEach(filteredSessions) { displayedSession in
                                InteractiveRequestRow(
                                    displayedSession: displayedSession,
                                    isSelected: appState.selectedSessionID == displayedSession.id,
                                    isContextMenuPresented: contextMenuSessionID == displayedSession.id,
                                    onSelect: {
                                        contextMenuSessionID = nil
                                        appState.selectedSessionID = displayedSession.id
                                    },
                                    onOpenInWindow: {
                                        contextMenuSessionID = nil
                                        appState.selectedSessionID = displayedSession.id
                                        openWindow(id: "request-inspector", value: displayedSession.id)
                                    },
                                    onShowContextMenu: {
                                        appState.selectedSessionID = displayedSession.id
                                        withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
                                            contextMenuSessionID = displayedSession.id
                                        }
                                    },
                                    onRemove: {
                                        let removedIDs = displayedSession.representedSessionIDs
                                        contextMenuSessionID = nil
                                        appState.captureStore.removeDisplayedSession(displayedSession)
                                        if let selectedSessionID = appState.selectedSessionID,
                                           removedIDs.contains(selectedSessionID) {
                                            appState.selectedSessionID = nil
                                        }
                                    }
                                )
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .contentShape(Rectangle())
                    .simultaneousGesture(
                        TapGesture().onEnded {
                            guard contextMenuSessionID != nil else { return }
                            withAnimation(.spring(response: 0.22, dampingFraction: 0.90)) {
                                contextMenuSessionID = nil
                            }
                        }
                    )
                }
            }

            if filteredSessions.isEmpty && !(filterText.isEmpty && appState.captureStore.visibleSessions.isEmpty && needsOnboarding) {
                DashboardEmptyState(
                    systemName: filterText.isEmpty ? "network.slash" : "magnifyingglass",
                    title: filterText.isEmpty ? "No requests captured" : "No matching requests",
                    iconSize: 28
                )
                .allowsHitTesting(false)
            }
        }
        .onChange(of: filterText) { _, _ in
            contextMenuSessionID = nil
        }
        .background(Color.clear)
    }
}

private struct InteractiveRequestRow: View {
    let displayedSession: DisplayedProxySession
    let isSelected: Bool
    let isContextMenuPresented: Bool
    let onSelect: () -> Void
    let onOpenInWindow: () -> Void
    let onShowContextMenu: () -> Void
    let onRemove: () -> Void

    var body: some View {
        RequestRow(
            session: displayedSession.session,
            collapsedCount: displayedSession.collapsedCount,
            isSelected: isSelected
        )
        .overlay {
            RequestRowInteractionLayer(
                onPrimaryClick: onSelect,
                onDoubleClick: onOpenInWindow,
                onSecondaryClick: onShowContextMenu
            )
        }
        .overlay(alignment: .topTrailing) {
            if isContextMenuPresented {
                RequestRowContextMenu(
                    onOpenInWindow: onOpenInWindow,
                    onRemove: onRemove
                )
                .padding(.top, 8)
                .padding(.trailing, 10)
                .transition(.scale(scale: 0.94, anchor: .topTrailing).combined(with: .opacity))
            }
        }
        .zIndex(isContextMenuPresented ? 10 : 0)
    }
}

private struct RequestRow: View {
    @Environment(AppState.self) var appState
    let session: ProxySession
    let collapsedCount: Int
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            // Method badge
            Text(session.method)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(TrabantTheme.colorForMethod(session.method))
                .frame(width: 58, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.requestProtocolBadge)
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .foregroundStyle(TrabantTheme.secondaryText)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(TrabantTheme.windowBackground, in: RoundedRectangle(cornerRadius: 3))

                Text(session.captureMode.label)
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .foregroundStyle(session.captureMode == .mitm ? TrabantTheme.statusGreen : TrabantTheme.statusOrange)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(TrabantTheme.windowBackground, in: RoundedRectangle(cornerRadius: 3))
            }

            // Host + path
            VStack(alignment: .leading, spacing: 1) {
                Text(session.host)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(TrabantTheme.primaryText)
                    .lineLimit(1)
                Text(appState.redactedModeEnabled ? Redactor.redactURL(session.path) : session.path)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(TrabantTheme.secondaryText)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 6) {
                    if collapsedCount > 1 {
                        Text("x\(collapsedCount)")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(TrabantTheme.dimText)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(TrabantTheme.windowBackground, in: RoundedRectangle(cornerRadius: 3))
                    }

                    // Content type
                    if !session.contentTypeShort.isEmpty {
                        Text(session.contentTypeShort)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(TrabantTheme.dimText)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(TrabantTheme.dimText.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
                    }

                    // Status code (always rightmost)
                    if let code = session.responseStatusCode {
                        Text("\(code)")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(TrabantTheme.colorForStatus(code))
                    } else if session.captureMode == .tunnel, session.error == nil {
                        Text("TUN")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(TrabantTheme.statusOrange)
                    } else if session.error != nil || session.failureReason != nil {
                        Text("ERR")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(TrabantTheme.statusRed)
                    } else {
                        ProgressView()
                            .controlSize(.mini)
                    }
                }

                // Timestamp
                Text(session.requestTimestamp, style: .time)
                    .font(.system(size: 10))
                    .foregroundStyle(TrabantTheme.dimText)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(isSelected ? TrabantTheme.selectedBackground : .clear)
        .contentShape(Rectangle())
    }
}

private struct RequestRowContextMenu: View {
    let onOpenInWindow: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RequestRowContextMenuButton(
                title: "Open in Pop-Up",
                systemName: "uiwindow.split.2x1",
                tint: TrabantTheme.primaryText,
                action: onOpenInWindow
            )

            RequestRowContextMenuButton(
                title: "Remove from List",
                systemName: "trash",
                tint: TrabantTheme.statusRed,
                action: onRemove
            )
        }
        .padding(8)
        .frame(width: 180, alignment: .leading)
        .background {
            LiquidGlassBackground(cornerRadius: 16, strokeOpacity: 0.14)
        }
    }
}

private struct RequestRowContextMenuButton: View {
    let title: String
    let systemName: String
    let tint: Color
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 14)

                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(TrabantTheme.primaryText)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isHovering ? Color.white.opacity(0.08) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

private struct RequestRowInteractionLayer: NSViewRepresentable {
    let onPrimaryClick: () -> Void
    let onDoubleClick: () -> Void
    let onSecondaryClick: () -> Void

    func makeNSView(context: Context) -> RequestRowInteractionView {
        let view = RequestRowInteractionView()
        view.onPrimaryClick = onPrimaryClick
        view.onDoubleClick = onDoubleClick
        view.onSecondaryClick = onSecondaryClick
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }

    func updateNSView(_ nsView: RequestRowInteractionView, context: Context) {
        nsView.onPrimaryClick = onPrimaryClick
        nsView.onDoubleClick = onDoubleClick
        nsView.onSecondaryClick = onSecondaryClick
    }
}

private final class RequestRowInteractionView: NSView {
    var onPrimaryClick: (() -> Void)?
    var onDoubleClick: (() -> Void)?
    var onSecondaryClick: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var mouseDownCanMoveWindow: Bool {
        false
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            onSecondaryClick?()
            return
        }

        onPrimaryClick?()
        if event.clickCount == 2 {
            onDoubleClick?()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        onSecondaryClick?()
    }
}
