# Trabant 🛰️

A local macOS HTTP/HTTPS debugging proxy for iOS devices. Inspect network traffic from iPhones and iPads routed through your Mac — no cloud, no accounts, no analytics. All data stays on your machine.

Think [Proxyman](https://proxyman.io) or [Charles](https://www.charlesproxy.com), but open source and free.

## How it works

```
iPhone/iPad ──Wi-Fi proxy──▶ Mac (port 9090) ──▶ Internet
                                    │
                              Trabant captures
                              & displays traffic
```

1. Trabant runs a proxy server on your Mac (default port **9090**)
2. You generate a local CA certificate and install it on your iOS device
3. Point your device's Wi-Fi proxy to your Mac's IP
4. HTTP traffic is captured directly; HTTPS traffic is decrypted via MITM using certificates signed by your local CA
5. Hosts with certificate pinning (e.g. Twitter, Snapchat) automatically fall back to raw tunneling — the app still works, those requests just appear as opaque `TUNNEL` rows

## Features

- **HTTPS decryption** — MITM with locally generated certificates, TLS 1.3, HTTP/1.1 & HTTP/2
- **Automatic pinned-host bypass** — certificate-pinned hosts fall back to raw tunneling so apps keep working
- **Device grouping** — traffic organized by connected device with nicknames
- **Request inspector** — headers, body (with JSON pretty-printing), timing, and protocol info
- **Detached windows** — double-click any request to open it in its own window
- **QR code setup** — scan to install the CA certificate on your device from Safari
- **Smart compaction** — noisy tunnel-learning and duplicate media requests are collapsed in the UI
- **Zero telemetry** — no analytics, no network calls, no cloud. Everything stays local and in-memory

## Download

Grab the latest `.dmg` from [**Releases**](https://github.com/gsdv/trabant/releases).

Requires **macOS 15.0** or later. Distributed as a notarized app outside the Mac App Store.

## Setup

1. **Download and launch** Trabant
2. **Generate the CA** — menu bar: `Certificate` → `Show Setup` → Generate CA
3. **Install on iPhone** — scan the QR code in Safari (not Chrome/Firefox — Apple restriction)
4. **Trust the certificate** on iPhone:
   - Settings → General → VPN & Device Management → install the profile
   - Settings → General → About → Certificate Trust Settings → enable full trust
5. **Configure Wi-Fi proxy** on iPhone:
   - Settings → Wi-Fi → your network → Configure Proxy → Manual
   - Server: your Mac's IP (shown in Trabant)
   - Port: `9090`
6. **Start the proxy** in Trabant and browse on your device — traffic appears in real time

## Build from source

```bash
git clone https://github.com/gsdv/trabant.git
cd trabant
open Trabant.xcodeproj
```

Build and run in Xcode (macOS target). Requires **Xcode 16+**.

Dependencies are managed via SPM and declared in the Xcode project:

| Package | Purpose |
|---------|---------|
| [SwiftNIO](https://github.com/apple/swift-nio) | TCP server, HTTP handling |
| [SwiftNIO SSL](https://github.com/apple/swift-nio-ssl) | TLS termination for MITM |
| [SwiftNIO HTTP/2](https://github.com/apple/swift-nio-http2) | HTTP/2 protocol support |
| [Swift Certificates](https://github.com/apple/swift-certificates) | X.509 certificate generation |
| [Swift Crypto](https://github.com/apple/swift-crypto) | P256 ECDSA key generation |
| [Swift ASN1](https://github.com/apple/swift-asn1) | PEM serialization |

## Architecture

```
Trabant/
├── App/                    # AppState, lifecycle
├── Core/
│   ├── Models/             # ProxySession, DeviceRecord
│   ├── Store/              # CaptureStore (in-memory, max 2000 sessions)
│   ├── Proxy/              # NIO proxy server, MITM, tunnel relay, cert authority
│   └── Utilities/          # Body formatting, LAN IP detection
└── UI/                     # SwiftUI views, theme, dashboard
```

**Proxy pipeline:** SwiftNIO server → HTTP routing → CONNECT upgrade → TLS termination (NIOSSL) → cleartext capture → upstream forwarding (URLSession)

**Pinned-host handling:** If a client rejects the MITM certificate during TLS handshake, the host is added to a persistent bypass list. Future connections to that host use a raw byte-relay tunnel instead of MITM.

## Known limitations

- **In-memory only** — captured sessions are lost when the app quits
- **No HTTP/3 / QUIC** — out of scope for now
- **Certificate pinned hosts** are tunneled, not decrypted
- **App Sandbox is disabled** — required for binding server sockets; distributed outside the Mac App Store
- **iOS certificate install requires Safari** — Chrome/Firefox cannot trigger the profile install flow

## License

[MIT](LICENSE)
