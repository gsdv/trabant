import Foundation

@MainActor
@Observable
final class CaptureStore {
    var devices: [DeviceRecord] = []
    var sessions: [ProxySession] = []

    private static let deviceNicknamesKey = "me.gsdv.Trabant.DeviceNicknames"

    private let maxSessions = 2000
    private let tunnelRetryWindow: TimeInterval = 15
    private let repeatedMediaWindow: TimeInterval = 2
    private let repeatedTunnelWindow: TimeInterval = 5

    var visibleSessions: [DisplayedProxySession] {
        compactForDisplay(sessions)
    }

    func addSession(_ session: ProxySession) {
        sessions.insert(session, at: 0)
        trimIfNeeded()
        updateDevice(for: session)
    }

    func updateSession(_ session: ProxySession) {
        if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[idx] = session
        }
        updateDevice(for: session)
    }

    func sessionsForDevice(_ deviceIP: String) -> [ProxySession] {
        sessions.filter { $0.deviceIP == deviceIP }
    }

    func visibleSessionsForDevice(_ deviceIP: String) -> [DisplayedProxySession] {
        compactForDisplay(sessionsForDevice(deviceIP))
    }

    func clearAll() {
        sessions.removeAll()
        devices.removeAll()
    }

    func removeDisplayedSession(_ displayedSession: DisplayedProxySession) {
        sessions.removeAll { displayedSession.representedSessionIDs.contains($0.id) }
        rebuildDevices()
    }

    func session(id: UUID) -> ProxySession? {
        sessions.first { $0.id == id }
    }

    func renameDevice(_ ip: String, to name: String?) {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = (trimmed?.isEmpty ?? true) ? nil : trimmed

        if let idx = devices.firstIndex(where: { $0.ipAddress == ip }) {
            devices[idx].customName = finalName
        }

        var nicknames = persistedNicknames()
        if let finalName {
            nicknames[ip] = finalName
        } else {
            nicknames.removeValue(forKey: ip)
        }
        UserDefaults.standard.set(nicknames, forKey: Self.deviceNicknamesKey)
    }

    private func persistedNicknames() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: Self.deviceNicknamesKey) as? [String: String] ?? [:]
    }

    private func trimIfNeeded() {
        if sessions.count > maxSessions {
            sessions.removeLast(sessions.count - maxSessions)
            rebuildDevices()
        }
    }

    private func updateDevice(for session: ProxySession) {
        let ip = session.deviceIP
        if let idx = devices.firstIndex(where: { $0.ipAddress == ip }) {
            devices[idx].lastSeenAt = session.requestTimestamp
            devices[idx].sessionCount = sessionsForDevice(ip).count
            if devices[idx].detectedName == nil {
                devices[idx].detectedName = detectDeviceName(from: session)
            }
        } else {
            let device = DeviceRecord(
                ipAddress: ip,
                hostname: nil,
                customName: persistedNicknames()[ip],
                detectedName: detectDeviceName(from: session),
                firstSeenAt: session.requestTimestamp,
                lastSeenAt: session.requestTimestamp,
                sessionCount: 1
            )
            devices.insert(device, at: 0)
            resolveHostname(for: ip)
        }
    }

    private func detectDeviceName(from session: ProxySession) -> String? {
        guard let ua = session.requestHeaders.first(where: {
            $0.0.lowercased() == "user-agent"
        })?.1 else {
            return nil
        }
        return UserAgentDeviceParser.parse(ua)?.displayName
    }

    private func resolveHostname(for ip: String) {
        Task.detached {
            let hostname = await HostnameResolver.resolve(ip: ip)
            await MainActor.run {
                if let idx = self.devices.firstIndex(where: { $0.ipAddress == ip }) {
                    self.devices[idx].hostname = hostname
                }
            }
        }
    }

    private func rebuildDevices() {
        let hostnamesByIP = Dictionary(uniqueKeysWithValues: devices.map { ($0.ipAddress, $0.hostname) })
        let customNamesByIP = Dictionary(uniqueKeysWithValues: devices.map { ($0.ipAddress, $0.customName) })
        let detectedNamesByIP = Dictionary(uniqueKeysWithValues: devices.map { ($0.ipAddress, $0.detectedName) })
        let nicknames = persistedNicknames()
        var rebuilt: [DeviceRecord] = []

        let grouped = Dictionary(grouping: sessions, by: \.deviceIP)
        for (ip, deviceSessions) in grouped {
            guard let first = deviceSessions.min(by: { $0.requestTimestamp < $1.requestTimestamp }),
                  let last = deviceSessions.max(by: { $0.requestTimestamp < $1.requestTimestamp })
            else { continue }

            rebuilt.append(
                DeviceRecord(
                    ipAddress: ip,
                    hostname: hostnamesByIP[ip] ?? nil,
                    customName: customNamesByIP[ip] ?? nicknames[ip],
                    detectedName: detectedNamesByIP[ip] ?? nil,
                    firstSeenAt: first.requestTimestamp,
                    lastSeenAt: last.requestTimestamp,
                    sessionCount: deviceSessions.count
                )
            )
        }

        devices = rebuilt.sorted { $0.lastSeenAt > $1.lastSeenAt }
    }

    private func compactForDisplay(_ source: [ProxySession]) -> [DisplayedProxySession] {
        var displayed: [DisplayedProxySession] = []
        var recentTunnelSuccesses: [TunnelHostKey: (timestamp: Date, index: Int)] = [:]
        var recentCollapsedKeys: [CollapsedSessionKey: (timestamp: Date, index: Int)] = [:]

        for session in source {
            let tunnelKey = TunnelHostKey(deviceIP: session.deviceIP, host: session.host, port: session.port)

            if session.isTunnelLearningFailure,
               let success = recentTunnelSuccesses[tunnelKey],
               success.timestamp.timeIntervalSince(session.requestTimestamp) <= tunnelRetryWindow {
                displayed[success.index].collapsedCount += 1
                displayed[success.index].representedSessionIDs.insert(session.id)
                continue
            }

            if let key = collapseKey(for: session),
               let existing = recentCollapsedKeys[key],
               collapseWindow(for: session) >= existing.timestamp.timeIntervalSince(session.requestTimestamp) {
                displayed[existing.index].collapsedCount += 1
                displayed[existing.index].representedSessionIDs.insert(session.id)
                continue
            }

            displayed.append(DisplayedProxySession(session: session, collapsedCount: 1))
            let insertedIndex = displayed.count - 1

            if session.isSuccessfulTunnel {
                recentTunnelSuccesses[tunnelKey] = (session.requestTimestamp, insertedIndex)
            }

            if let key = collapseKey(for: session) {
                recentCollapsedKeys[key] = (session.requestTimestamp, insertedIndex)
            }
        }

        return displayed
    }

    private func collapseKey(for session: ProxySession) -> CollapsedSessionKey? {
        if session.captureMode == .tunnel {
            return CollapsedSessionKey(
                category: .tunnel,
                deviceIP: session.deviceIP,
                method: session.method,
                host: session.host,
                port: session.port,
                path: session.path,
                statusCode: session.responseStatusCode,
                outcomeTag: session.responseStatusCode == 200 ? "success" : "failure"
            )
        }

        guard session.isLowSignalMediaRequest else { return nil }
        return CollapsedSessionKey(
            category: .media,
            deviceIP: session.deviceIP,
            method: session.method,
            host: session.host,
            port: session.port,
            path: session.path,
            statusCode: session.responseStatusCode,
            outcomeTag: session.contentTypeShort
        )
    }

    private func collapseWindow(for session: ProxySession) -> TimeInterval {
        session.captureMode == .tunnel ? repeatedTunnelWindow : repeatedMediaWindow
    }
}

private struct TunnelHostKey: Hashable {
    let deviceIP: String
    let host: String
    let port: Int
}

private struct CollapsedSessionKey: Hashable {
    enum Category: Hashable {
        case tunnel
        case media
    }

    let category: Category
    let deviceIP: String
    let method: String
    let host: String
    let port: Int
    let path: String
    let statusCode: Int?
    let outcomeTag: String
}
