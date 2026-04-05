import AppKit
import SwiftUI

struct RootView: View {
    @Environment(AppState.self) var appState
    @Environment(\.openWindow) private var openWindow
    @State private var isDevicesSidebarVisible = true
    @State private var devicesSidebarWidth: CGFloat = 280
    @State private var lastVisibleDevicesSidebarWidth: CGFloat = 280
    @State private var requestListWidth: CGFloat = 430

    private let dividerHitWidth: CGFloat = 10
    private let minDevicesSidebarWidth: CGFloat = 250
    private let minRequestListWidth: CGFloat = 320
    private let minRequestDetailWidth: CGFloat = 320
    private let sidebarCollapseThreshold: CGFloat = 120
    private let maxDevicesSidebarFraction: CGFloat = 1.0 / 3.0
    private var minimumWindowSize: NSSize {
        NSSize(
            width: minDevicesSidebarWidth + minRequestListWidth + minRequestDetailWidth + (dividerHitWidth * 2) + 40,
            height: 700
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            if let proxyError = appState.proxyError {
                errorBanner(proxyError)
            }

            dashboardContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(TrabantTheme.windowBackground)
        .frame(minWidth: minimumWindowSize.width, minHeight: minimumWindowSize.height)
        .toolbar { windowToolbar }
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .onChange(of: appState.isShowingCertificateSetup) { _, show in
            if show {
                openWindow(id: "certificate-setup")
                appState.isShowingCertificateSetup = false
            }
        }
        .background(
            WindowChromeConfigurator(
                minimumWindowSize: minimumWindowSize,
                trailingControls: AnyView(
                    TitlebarTrailingControlsView()
                        .environment(appState)
                )
            )
        )
    }

    private var dashboardContent: some View {
        ZStack {
            dashboardBackdrop
            dashboardMainArea
                .padding(.top, 8)
                .padding(.bottom, 12)
        }
    }

    private var dashboardMainArea: some View {
        GeometryReader { geometry in
            let dividerCount: CGFloat = isDevicesSidebarVisible ? 2 : 1
            let layoutLimitedSidebarWidth = max(
                minDevicesSidebarWidth,
                geometry.size.width - (dividerHitWidth * dividerCount) - minRequestListWidth - minRequestDetailWidth
            )
            let sidebarMaximumWidth = max(
                minDevicesSidebarWidth,
                min(layoutLimitedSidebarWidth, geometry.size.width * maxDevicesSidebarFraction)
            )
            let visibleSidebarWidth = isDevicesSidebarVisible
                ? min(max(devicesSidebarWidth, minDevicesSidebarWidth), sidebarMaximumWidth)
                : 0
            let centerContentWidth = geometry.size.width - visibleSidebarWidth - (dividerHitWidth * dividerCount)
            let requestMaximumWidth = max(minRequestListWidth, centerContentWidth - minRequestDetailWidth)
            let visibleRequestListWidth = min(
                max(requestListWidth, minRequestListWidth),
                requestMaximumWidth
            )

            HStack(spacing: 0) {
                if isDevicesSidebarVisible {
                    SidebarDevicesView()
                        .frame(width: visibleSidebarWidth)
                        .frame(maxHeight: .infinity)
                        .transition(.move(edge: .leading).combined(with: .opacity))

                    splitDivider(
                        onChanged: { delta in
                            let proposedWidth = min(max(devicesSidebarWidth + delta, 0), sidebarMaximumWidth)

                            if proposedWidth < sidebarCollapseThreshold {
                                lastVisibleDevicesSidebarWidth = min(
                                    max(devicesSidebarWidth, minDevicesSidebarWidth),
                                    sidebarMaximumWidth
                                )

                                withAnimation(.spring(response: 0.24, dampingFraction: 0.90)) {
                                    isDevicesSidebarVisible = false
                                    devicesSidebarWidth = max(lastVisibleDevicesSidebarWidth, minDevicesSidebarWidth)
                                }
                                return
                            }

                            devicesSidebarWidth = proposedWidth
                        },
                        onEnded: {
                            guard isDevicesSidebarVisible else { return }

                            let clampedWidth = min(max(devicesSidebarWidth, minDevicesSidebarWidth), sidebarMaximumWidth)
                            withAnimation(.spring(response: 0.24, dampingFraction: 0.90)) {
                                devicesSidebarWidth = clampedWidth
                                lastVisibleDevicesSidebarWidth = clampedWidth
                            }
                        }
                    )
                }

                RequestListView()
                    .frame(width: visibleRequestListWidth)
                    .frame(maxHeight: .infinity)

                splitDivider(
                    onChanged: { delta in
                        requestListWidth = min(max(requestListWidth + delta, minRequestListWidth), requestMaximumWidth)
                    },
                    onEnded: {
                        requestListWidth = min(max(requestListWidth, minRequestListWidth), requestMaximumWidth)
                    }
                )

                RequestDetailView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .leading)
        }
    }

    @ToolbarContentBuilder
    private var windowToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            devicesToggleButton
        }

        ToolbarItem(placement: .principal) {
            dashboardStatusIndicator
        }
    }

    private var devicesToggleButton: some View {
        Button(action: toggleDevicesSidebar) {
            Image(systemName: isDevicesSidebarVisible ? "iphone.gen3" : "iphone.gen3.slash")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isDevicesSidebarVisible ? TrabantTheme.accentLight : TrabantTheme.secondaryText)
                .frame(width: 34, height: 34)
                .background(toolbarButtonBackground())
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("Toggle devices")
    }

    private var dashboardStatusIndicator: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(appState.isProxyRunning ? TrabantTheme.statusGreen : TrabantTheme.secondaryText.opacity(0.7))
                .frame(width: 10, height: 10)

            Text("Trabant")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(TrabantTheme.primaryText)

            Rectangle()
                .fill(TrabantTheme.separator.opacity(0.8))
                .frame(width: 1, height: 14)

            Text(statusSecondaryLabel)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(TrabantTheme.secondaryText)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(toolbarChipBackground())
        .fixedSize(horizontal: true, vertical: false)
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: statusSecondaryLabel)
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: appState.isProxyRunning)
    }

    private var dashboardBackdrop: some View {
        AnimatedDashboardBackdrop()
    }

    private var statusSecondaryLabel: String {
        let ip = appState.redactedModeEnabled ? Redactor.redactIP(appState.localIP) : appState.localIP
        if appState.isProxyRunning {
            return "Listening on \(ip):\(appState.proxyPort)"
        }
        if appState.localIP == "No network" {
            return "Proxy stopped"
        }
        return "Ready on \(ip):\(appState.proxyPort)"
    }

    private func toggleDevicesSidebar() {
        withAnimation(.spring(response: 0.26, dampingFraction: 0.88)) {
            if isDevicesSidebarVisible {
                lastVisibleDevicesSidebarWidth = max(devicesSidebarWidth, minDevicesSidebarWidth)
                isDevicesSidebarVisible = false
            } else {
                devicesSidebarWidth = max(lastVisibleDevicesSidebarWidth, minDevicesSidebarWidth)
                isDevicesSidebarVisible = true
            }
        }
    }

    private func toolbarChipBackground() -> some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(TrabantTheme.toolbarChipBackground)
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(TrabantTheme.toolbarChipBorder, lineWidth: 1)
            }
    }

    private func toolbarButtonBackground() -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(TrabantTheme.toolbarButtonBackground)
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(TrabantTheme.toolbarButtonBorder, lineWidth: 1)
            }
    }

    private func splitDivider(
        onChanged: @escaping (CGFloat) -> Void,
        onEnded: @escaping () -> Void
    ) -> some View {
        SplitDividerHandle(onChanged: onChanged, onEnded: onEnded)
            .frame(width: dividerHitWidth)
            .overlay {
                Rectangle()
                    .fill(TrabantTheme.separator.opacity(0.9))
                    .frame(width: 1)
            }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(TrabantTheme.statusOrange)

            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(TrabantTheme.primaryText)
                .textSelection(.enabled)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(TrabantTheme.statusRed.opacity(0.12))
    }
}

private struct WindowChromeConfigurator: NSViewRepresentable {
    let minimumWindowSize: NSSize
    let trailingControls: AnyView

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = false
            window.toolbarStyle = .unified
            window.contentMinSize = minimumWindowSize
            window.minSize = minimumWindowSize
            context.coordinator.installTrailingControls(trailingControls, in: window)
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.removeTrailingControls()
    }

    final class Coordinator {
        private weak var titlebarView: NSView?
        private weak var closeButton: NSButton?
        private var hostingView: NSHostingView<AnyView>?

        func installTrailingControls(_ trailingControls: AnyView, in window: NSWindow) {
            guard
                let closeButton = window.standardWindowButton(.closeButton),
                let titlebarView = closeButton.superview
            else {
                return
            }

            if hostingView?.superview !== titlebarView {
                hostingView?.removeFromSuperview()

                let hostingView = NSHostingView(rootView: trailingControls)
                hostingView.translatesAutoresizingMaskIntoConstraints = false
                hostingView.wantsLayer = true
                hostingView.layer?.backgroundColor = NSColor.clear.cgColor

                titlebarView.addSubview(hostingView)
                NSLayoutConstraint.activate([
                    hostingView.trailingAnchor.constraint(equalTo: titlebarView.trailingAnchor, constant: -18),
                    hostingView.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor)
                ])

                self.hostingView = hostingView
                self.titlebarView = titlebarView
                self.closeButton = closeButton
            }

            hostingView?.rootView = trailingControls
            hostingView?.invalidateIntrinsicContentSize()
            hostingView?.layoutSubtreeIfNeeded()
        }

        func removeTrailingControls() {
            hostingView?.removeFromSuperview()
            hostingView = nil
            titlebarView = nil
            closeButton = nil
        }
    }
}

private struct SplitDividerHandle: NSViewRepresentable {
    let onChanged: (CGFloat) -> Void
    let onEnded: () -> Void

    func makeNSView(context: Context) -> DividerDragView {
        let view = DividerDragView()
        view.onChanged = onChanged
        view.onEnded = onEnded
        return view
    }

    func updateNSView(_ nsView: DividerDragView, context: Context) {
        nsView.onChanged = onChanged
        nsView.onEnded = onEnded
    }
}

private final class DividerDragView: NSView {
    var onChanged: ((CGFloat) -> Void)?
    var onEnded: (() -> Void)?

    private lazy var panGestureRecognizer: NSPanGestureRecognizer = {
        let recognizer = NSPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        recognizer.delaysPrimaryMouseButtonEvents = false
        return recognizer
    }()

    private var lastTranslationX: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        addGestureRecognizer(panGestureRecognizer)
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

    override func resetCursorRects() {
        discardCursorRects()
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    @objc
    private func handlePan(_ recognizer: NSPanGestureRecognizer) {
        let translationX = recognizer.translation(in: self).x

        switch recognizer.state {
        case .began:
            lastTranslationX = translationX
        case .changed:
            let delta = translationX - lastTranslationX
            lastTranslationX = translationX
            onChanged?(delta)
        case .ended, .cancelled, .failed:
            lastTranslationX = 0
            onEnded?()
        default:
            break
        }
    }
}

private struct TitlebarTrailingControlsView: View {
    @Environment(AppState.self) var appState

    var body: some View {
        HStack(spacing: 10) {
            Button(action: { appState.toggleProxy() }) {
                Text(appState.isProxyRunning ? "Stop" : "Start")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.82))
                    .frame(minWidth: 72, minHeight: 34)
                    .padding(.horizontal, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(appState.isProxyRunning ? TrabantTheme.statusOrange : TrabantTheme.accentLight)
                    )
            }
            .buttonStyle(.plain)

            TitlebarIconButton(
                systemName: appState.redactedModeEnabled ? "eye.slash.fill" : "eye.slash",
                tint: appState.redactedModeEnabled ? TrabantTheme.accentLight : TrabantTheme.secondaryText,
                helpText: "Redacted mode"
            ) {
                appState.redactedModeEnabled.toggle()
            }

            TitlebarIconButton(
                systemName: appState.debugLoggingEnabled ? "ladybug.fill" : "ladybug",
                tint: appState.debugLoggingEnabled ? TrabantTheme.accentLight : TrabantTheme.secondaryText,
                helpText: "Verbose proxy logs"
            ) {
                appState.debugLoggingEnabled.toggle()
            }

            TitlebarIconButton(
                systemName: "trash",
                tint: TrabantTheme.secondaryText,
                helpText: "Clear all sessions"
            ) {
                appState.captureStore.clearAll()
            }
        }
    }
}

private struct TitlebarIconButton: View {
    let systemName: String
    let tint: Color
    let helpText: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(TrabantTheme.toolbarButtonBackground)
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(TrabantTheme.toolbarButtonBorder, lineWidth: 1)
                        }
                )
        }
        .buttonStyle(.plain)
        .help(helpText)
    }
}
