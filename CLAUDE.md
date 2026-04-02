# Trabant — CLAUDE.md

## What is Trabant?

Trabant is a **local macOS HTTP/HTTPS debugging proxy** (similar to Proxyman/Charles). It captures traffic from iPhones/iPads configured to use the Mac as a Wi-Fi proxy. All data stays local — no cloud, no accounts, no analytics.

## How it works

1. Mac runs a proxy server on port **9090** (configurable)
2. A local CA certificate is generated and installed/trusted on the iPhone
3. iPhone's Wi-Fi proxy is set to the Mac's LAN IP + port 9090
4. HTTP traffic is forwarded and captured directly
5. HTTPS traffic uses MITM: proxy sends 200 to CONNECT, then terminates TLS with a leaf cert signed by the local CA, connects to upstream over separate TLS, relays and captures cleartext
6. A tiny HTTP file server on port **9091** serves the CA `.cer` file for easy iPhone installation

## Tech stack

- **Swift**, **SwiftUI** (macOS app, dark theme, 3-pane layout)
- **SwiftNIO** (NIOCore, NIOPosix, NIOHTTP1, NIOHTTP2, NIOFoundationCompat) — TCP server, CONNECT upgrade, downstream HTTP/1.1 + HTTP/2 handling
- **NIOSSL** — TLS termination (server-side MITM)
- **swift-certificates** (X509) — CA and leaf certificate generation
- **swift-crypto** (Crypto) — P256 key generation
- **SwiftASN1** — PEM serialization
- **Foundation URLSession** — current upstream HTTP transport (still used for proxy-to-origin requests)
- **CoreImage** — QR code generation for cert download URL

## Project structure

```
  Trabant/
  TrabantApp.swift              — @main entry, injects AppState via .environment(), defines the main dashboard window, detached request inspector windows, and the Certificate menu command
  App/
    AppState.swift              — @MainActor @Observable, owns ProxyServer, CaptureStore, CertificateAuthority, debug logging preference
  Core/
    Models/
      DeviceRecord.swift        — Device identified by IP, with hostname/timestamps/count
      ProxySession.swift        — Request/response capture model with computed helpers
    Store/
      CaptureStore.swift        — @MainActor @Observable, max 2000 raw sessions, groups by device, compacts visible sessions for UI
    Proxy/
      ProxyServer.swift         — NIO ServerBootstrap on 0.0.0.0:9090, named handlers
      ProxyHTTPHandler.swift    — Routes HTTP vs CONNECT, pipeline upgrade for HTTPS MITM
      MITMHandler.swift         — Handles decrypted HTTPS inside the MITM tunnel
      MITMTLSFailureHandler.swift — Detects MITM handshake rejection and marks hosts for tunnel bypass
      TunnelRelayHandler.swift  — Raw byte relay for CONNECT tunneling
      BypassDomains.swift       — Persisted pinned-host / bypass cache
      ProxyFailure.swift        — Structured failure classification
      ProxyTLSSettings.swift    — Shared ALPN/TLS settings
      CertificateAuthority.swift — CA generation, persistence, leaf cert cache
      CertificateFileServer.swift — HTTP server on port 9091 serving .cer file
      Upstream/
        UpstreamRequest.swift   — Protocol-agnostic request/session model
        UpstreamTransport.swift — Current upstream executor (URLSession-backed)
      Logging/
        ProxyLogger.swift       — Verbose proxy logging toggle
    Utilities/
      BodyFormatter.swift       — JSON pretty-printing, binary detection, HostnameResolver
      LocalNetworkInfo.swift    — LAN IP via getifaddrs (prefers en0)
  UI/
    Theme.swift                 — TrabantTheme: code-defined shared palette, animated dashboard backdrop colors, titlebar colors, method/status colors
    RootView.swift              — Main dashboard shell: titlebar controls, animated backdrop, status chip, draggable 3-pane split view, collapsible devices sidebar
    SidebarDevicesView.swift    — Device list with "All Devices" option and centered dashboard empty state
    RequestListView.swift       — Filterable request list using compacted visible sessions; single-click selects, double-click opens detached request window, right-click opens row actions
    RequestDetailView.swift     — Tabbed Request/Response detail for the main pane and detached inspector windows
    AnimatedDashboardBackdrop.swift — Slow-moving morphing blob backdrop behind the dashboard panes
    DashboardEmptyState.swift   — Shared centered empty-state component used by devices, requests, and detail panes
    CertificateSetupSheet.swift — Sheet wrapper for certificate setup, opened from the macOS Certificate menu
    CertificateView.swift       — Certificate setup content: CA actions, QR install card, and setup guide
```

## Build & run

- Open `Trabant.xcodeproj` in Xcode, build and run (macOS target)
- **Deployment target is macOS 15.0** — distributed outside the App Store via notarized direct download (not Mac App Store)
- **App Sandbox is disabled** (`ENABLE_APP_SANDBOX = NO`) — required for binding server sockets
- SPM dependencies are declared in the Xcode project (not a Package.swift)
- Uses `PBXFileSystemSynchronizedRootGroup` (Xcode 16+) — files in `Trabant/` are auto-discovered
- **Liquid Glass APIs** (`GlassEffectContainer`, `.glassProminent`, `.glass`) are guarded behind `#available(macOS 26.0, *)` with standard SwiftUI fallbacks for older OS versions
- Verbose proxy logging is **off by default**; the dashboard header ladybug toggles it and the choice persists in `UserDefaults`
- Certificate setup is opened from the macOS menu bar via `Certificate` → `Show Setup`, not from an in-app dashboard tab

## Key architecture details

### NIO pipeline (proxy)

Handlers are added with **explicit names** for later removal during CONNECT upgrade:
```
http-decoder → http-encoder → proxy-handler
```

### CONNECT / HTTPS MITM flow

1. `ProxyHTTPHandler` receives CONNECT in `.head`
2. Sends `200 Connection Established` with `Content-Length: 0` header via `writeAndFlush(.head)` only — **must NOT send `.end(nil)`** because NIOHTTP1's encoder emits chunked transfer-encoding terminator bytes (`0\r\n\r\n`) that leak into the tunnel as garbage, causing `WRONG_VERSION_NUMBER` (see [apple/swift-nio-ssl#539](https://github.com/apple/swift-nio-ssl/issues/539))
3. **Defers pipeline upgrade to the flush completion callback** — this is critical; upgrading synchronously causes TLS handshake failures
4. For MITM, removes old handlers by name, adds `ssl-server`, then `MITMTLSFailureHandler`, then `configureCommonHTTPServerPipeline` with `MITMHandler`
5. NIOSSLServerHandler performs TLS handshake with the client using a leaf cert for the target host
6. If the client rejects the generated cert (explicit TLS alert or early EOF during handshake), the host is added to `BypassDomains` and future requests use a raw CONNECT tunnel
7. `MITMHandler` sees cleartext HTTP, records the downstream protocol (`http/1.1` or `h2`), and forwards to the current upstream transport

### Raw CONNECT tunnel flow

When a host is in `BypassDomains`, `ProxyHTTPHandler` does **not** attempt MITM:

1. Sends `200 Connection Established`
2. Immediately switches the client pipeline to raw-byte relay mode
3. Buffers any early client tunnel bytes until the upstream TCP socket is attached
4. Relays bytes bidirectionally with `TunnelRelayHandler`

This path is what currently keeps pinned Twitter/Snapchat hosts working.

### TLS configuration

- **TLS 1.3 is supported** for the server-side (proxy-to-client) handshake. No version cap needed.
- **ALPN** is advertised on the server TLS config via `NIOHTTP2SupportedALPNProtocols` (`["h2", "http/1.1"]`). Native iOS apps negotiate ALPN during the handshake and may abort if the server doesn't advertise protocols.
- Downstream MITM currently handles both HTTP/1.1 and HTTP/2 enough for native iOS clients like Twitter to function.
- Upstream transport is still URLSession-backed, not a custom NIO HTTP/2 client pool.
- **CA cert extensions**: `BasicConstraints.isCertificateAuthority(maxPathLength: 0)` (critical), `KeyUsage(keyCertSign: true, cRLSign: true)` (critical), `SubjectKeyIdentifier`
- **Leaf cert extensions**: `BasicConstraints.notCertificateAuthority` (critical), `KeyUsage(digitalSignature: true)` (critical), `ExtendedKeyUsage([.serverAuth])`, `SubjectAlternativeNames([.dnsName(hostname)])`, `AuthorityKeyIdentifier` (links to CA's SubjectKeyIdentifier), `SubjectKeyIdentifier`
- Full chain is served: `[leafCert, caCert]`
- **iOS ATS compliance**: AuthorityKeyIdentifier + SubjectKeyIdentifier are required for iOS native apps (not just browsers) to accept the cert chain. Without these, apps get `SSLV3_ALERT_CERTIFICATE_UNKNOWN`.

### Certificate storage

```
~/Library/Application Support/Trabant/ca/
  trabant-root-ca.pem          — CA certificate (PEM)
  trabant-root-ca-key.pem      — CA private key (PEM)
  exported/
    trabant-root-ca.cer        — DER export for iPhone installation
```

Implementation note:
- Do **not** cache live `NIOSSLCertificate` objects across requests. Cache PEM material and rebuild fresh `NIOSSLCertificate` / `NIOSSLPrivateKey` objects per handshake. Caching the live objects caused a retain-count / dangling-reference crash in `NIOSSLCertificate` deinit.

### Cert file server

- Port 9091, serves `/trabant-ca.cer` with `Content-Type: application/x-x509-ca-cert` (no `Content-Disposition: attachment` — this is important; the attachment header prevents iOS Safari from triggering the profile install prompt)
- `/` serves an HTML landing page with download link

### Bypass cache

- `BypassDomains` persists learned bypass hosts in `UserDefaults`
- Once a host has rejected MITM, future launches should tunnel it immediately instead of failing once per app launch
- Clearing the bypass cache is separate from clearing captured sessions

### UI-visible sessions vs raw sessions

- `CaptureStore.sessions` is the raw feed. It keeps every captured session/update for debugging.
- `CaptureStore.visibleSessions` and `visibleSessionsForDevice(_:)` are the UI-facing compacted feed and should be the default source for request lists, counters, and "Proxyman-like" views.
- The compaction layer currently merges:
  - MITM-learning tunnel failures that are quickly followed by a successful tunnel for the same host
  - rapid duplicate low-signal media/image requests (for example repeated `pbs.twimg.com` profile images or `video-s.twimg.com` playlist/media fetches)
- The detail pane and detached request inspector windows still open real underlying `ProxySession` values from `CaptureStore.sessions`; compaction is a display concern, not a data-loss mechanism.

## Known constraints & gotchas

- **Certificate installation requires Safari** — Chrome/Firefox on iOS cannot trigger profile installation; this is an Apple restriction
- **CONNECT 200 must not include `.end(nil)`** — NIOHTTP1 adds chunked terminator bytes that corrupt the TLS tunnel (apple/swift-nio-ssl#539, apple/swift-nio#3260)
- **Raw CONNECT handoff is order-sensitive** — on the client side, add the raw relay before removing the HTTP decoder, and tolerate the trailing HTTP parser `.end(nil)` event after CONNECT. Otherwise the tunnel crashes trying to decode an HTTP part as a `ByteBuffer`.
- **Tunnel relays must buffer early bytes** until the upstream socket is attached, or the client's first TLS records can be lost.
- **App sandbox must be off** — the app binds to `0.0.0.0` on ports 9090/9091
- **In-memory only** — captured sessions are lost when the app quits (max 2000 sessions)
- **Detached request windows are session-ID backed** — they resolve against the in-memory raw store, so a window can fall back to an unavailable placeholder if its session has been evicted or cleared
- **No HTTP/3 / QUIC support** — anything that truly requires QUIC is out of scope right now
- **Pinned hosts no longer have to fail outright** — many pinned/native-app hosts can fall back to raw CONNECT tunneling and remain visible as `TUNNEL` rows. They are not decrypted, but the app can still work.
- **Some `TUNNEL` rows with failure text are expected on first contact** — they are often the learning attempt where the client rejected MITM and Trabant switched that host to tunnel. After bypass persistence, future launches should produce fewer of these.
- **Some red `CONNECT/TUNNEL` rows are abandoned speculative connections** — if the app opens a pinned host speculatively and then drops it before retrying or using it, Trabant may still show the first rejected attempt even though the app continues normally.
- **Visible request counts intentionally differ from raw captured session counts** — the UI now compacts noisy tunnel-learning and repeated media rows so the app feels closer to Proxyman. If you need the exact raw feed for debugging, inspect `CaptureStore.sessions`.
- **Apple services vary** — some Apple hosts MITM fine, others reject the cert and are tunneled, and some truly pinned/system-critical flows may remain impossible to intercept.
- **App Store behavior is not a guaranteed regression target** — if it happens to work in a given build/network state, treat that as a bonus, not a stable parity promise.
- **`StreamClosed(... Cancel)` and `uncleanShutdown` are usually noise** for HTTP/2/media traffic, not proxy regressions
- The `whenSuccess`/`whenFailure` pattern on NIO futures does NOT chain — use `whenComplete` with a switch instead

## Testing / validation notes

- There is now an Xcode test target (`TrabantTests`)
- Current tests cover:
  - body formatting / decompression
  - ALPN advertisement
  - failure classification
  - session metadata
  - UI/session compaction for tunnel-learning rows and repeated media requests
  - MITM handshake rejection heuristics
  - bypass-domain persistence
- Device validation still matters for native iOS apps. Twitter and Snapchat are useful real-world regression targets because they exercise:
  - downstream HTTP/2
  - pinned-host fallback to raw CONNECT
  - mixed MITM + tunneled traffic in one app session
- Current real-world status:
  - Twitter works, including refresh/search, with a mix of MITM and raw tunnel traffic
  - Snapchat works with pinned-host tunnel fallback

## Testing the proxy

1. Build & run in Xcode
2. Click "Start" in the dashboard header
3. Use the macOS menu bar: `Certificate` → `Show Setup`, then generate the CA if needed
4. On iPhone: scan the QR code (or open the URL) **in Safari** to install the cert profile
5. Install profile: Settings → General → VPN & Device Management
6. Trust CA: Settings → General → About → Certificate Trust Settings
7. Configure proxy: Settings → Wi-Fi → your network → Configure Proxy → Manual → Mac IP, port 9090
8. Browse on iPhone — traffic appears in Trabant
