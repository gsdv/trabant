import AppKit
import SwiftUI

struct RequestDetailView: View {
    @Environment(AppState.self) var appState

    private var session: ProxySession? {
        guard let id = appState.selectedSessionID else { return nil }
        return appState.captureStore.session(id: id)
    }

    var body: some View {
        Group {
            if let session {
                DetailContent(session: session)
            } else {
                RequestDetailEmptyState(title: "Select a request to inspect")
            }
        }
        .background(Color.clear)
    }
}

struct DetachedRequestDetailView: View {
    @Environment(AppState.self) var appState
    let sessionID: UUID?

    private var session: ProxySession? {
        guard let sessionID else { return nil }
        return appState.captureStore.session(id: sessionID)
    }

    private var windowTitle: String {
        guard let session else { return "Request Detail" }
        let path = appState.redactedModeEnabled ? Redactor.redactURL(session.path) : session.path
        let title = "\(session.method) \(session.host)\(path)"
        return String(title.prefix(90))
    }

    var body: some View {
        Group {
            if let session {
                DetailContent(session: session)
            } else {
                RequestDetailEmptyState(title: "This request is no longer available")
            }
        }
        .frame(minWidth: 760, minHeight: 560)
        .background(TrabantTheme.panelBackground)
        .background(RequestWindowConfigurator(title: windowTitle))
    }
}

private struct DetailContent: View {
    @Environment(AppState.self) var appState
    let session: ProxySession
    @State private var selectedTab = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Overview bar
            overviewBar

            Divider().background(TrabantTheme.separator)

            // Tab picker
            Picker("", selection: $selectedTab) {
                Text("Request").tag(0)
                Text("Response").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(8)

            Divider().background(TrabantTheme.separator)

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if selectedTab == 0 {
                        requestContent
                    } else {
                        responseContent
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var overviewBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(session.method)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(TrabantTheme.colorForMethod(session.method))

                if let code = session.responseStatusCode {
                    Text("\(code)")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(TrabantTheme.colorForStatus(code))
                }

                Text(session.requestProtocolBadge)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(TrabantTheme.dimText)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(TrabantTheme.dimText.opacity(0.2), in: RoundedRectangle(cornerRadius: 3))

                Text(session.captureMode.label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(session.captureMode == .mitm ? TrabantTheme.statusGreen : TrabantTheme.statusOrange)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(TrabantTheme.windowBackground, in: RoundedRectangle(cornerRadius: 3))

                Spacer()

                if let dur = session.durationMs {
                    Text(String(format: "%.0f ms", dur))
                        .font(TrabantTheme.monoSmall)
                        .foregroundStyle(TrabantTheme.secondaryText)
                }
            }

            Text(appState.redactedModeEnabled ? Redactor.redactURL(session.url) : session.url)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(TrabantTheme.primaryText)
                .lineLimit(2)
                .textSelection(.enabled)

            if let upstreamProtocol = session.upstreamProtocol {
                Text("Upstream: \(upstreamProtocol.uppercased())")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(TrabantTheme.secondaryText)
            }

            if let error = session.error {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(TrabantTheme.statusRed)
            }

            if let failureReason = session.failureReason, failureReason != session.error {
                Text(failureReason)
                    .font(.system(size: 11))
                    .foregroundStyle(TrabantTheme.statusOrange)
            }
        }
        .padding(12)
        .background(TrabantTheme.windowBackground.opacity(0.5))
    }

    private var redacted: Bool { appState.redactedModeEnabled }

    private var requestContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Request Line")
            MonoText("\(session.method) \(redacted ? Redactor.redactURL(session.path) : session.path) \(httpVersionLabel(for: session.requestProtocol))")

            SectionHeader("Headers")
            MonoText(BodyFormatter.formatHeaders(redacted ? Redactor.redactHeaders(session.requestHeaders) : session.requestHeaders))

            SectionHeader("Body")
            MonoText(redactIfNeeded(
                BodyFormatter.format(
                    data: session.requestBody,
                    mimeType: requestContentType,
                    contentEncoding: BodyFormatter.headerValue("content-encoding", in: session.requestHeaders)
                )
            ))
        }
    }

    private var responseContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let code = session.responseStatusCode {
                SectionHeader("Status")
                MonoText("\(httpVersionLabel(for: session.requestProtocol)) \(code)")
            }

            SectionHeader("Headers")
            if session.responseHeaders.isEmpty {
                MonoText("(no headers)")
            } else {
                MonoText(BodyFormatter.formatHeaders(redacted ? Redactor.redactHeaders(session.responseHeaders) : session.responseHeaders))
            }

            SectionHeader("Body")
            MonoText(redactIfNeeded(
                BodyFormatter.format(
                    data: session.responseBody,
                    mimeType: session.mimeType,
                    contentEncoding: BodyFormatter.headerValue("content-encoding", in: session.responseHeaders)
                )
            ))
        }
    }

    private var requestContentType: String? {
        session.requestHeaders.first(where: { $0.0.lowercased() == "content-type" })?.1
    }

    private func redactIfNeeded(_ text: String) -> String {
        redacted ? Redactor.redactBodyText(text) : text
    }

    private func httpVersionLabel(for requestProtocol: String) -> String {
        switch requestProtocol.lowercased() {
        case "h2":
            return "HTTP/2"
        case "http/1.1":
            return "HTTP/1.1"
        default:
            return requestProtocol.uppercased()
        }
    }
}

private struct RequestDetailEmptyState: View {
    let title: String

    var body: some View {
        DashboardEmptyState(
            systemName: "doc.text.magnifyingglass",
            title: title,
            iconSize: 32
        )
    }
}

private struct SectionHeader: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(TrabantTheme.accent)
            .textCase(.uppercase)
    }
}

private struct MonoText: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(TrabantTheme.monoSmall)
            .foregroundStyle(TrabantTheme.primaryText)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(TrabantTheme.windowBackground, in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct RequestWindowConfigurator: NSViewRepresentable {
    let title: String

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            nsView.window?.title = title
        }
    }
}
