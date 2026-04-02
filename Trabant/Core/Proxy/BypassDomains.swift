import Foundation

/// Thread-safe set of domains that should be transparently tunneled instead of MITM'd.
/// Populated when a MITM TLS handshake fails with certificate_unknown (TLS alert 46),
/// which indicates the client is enforcing certificate pinning (e.g. Cronet/net_error -150).
final class BypassDomains: @unchecked Sendable {
    static let shared = BypassDomains()

    private let defaults: UserDefaults
    private let persistenceKey: String
    private var domains = Set<String>()
    private let lock = NSLock()

    init(defaults: UserDefaults = .standard, persistenceKey: String = "me.gsdv.Trabant.BypassDomains") {
        self.defaults = defaults
        self.persistenceKey = persistenceKey
        if let storedDomains = defaults.array(forKey: persistenceKey) as? [String] {
            domains = Set(storedDomains.map { $0.lowercased() })
        }
    }

    func add(_ domain: String) {
        let normalized = domain.lowercased()
        lock.lock()
        let inserted = domains.insert(normalized).inserted
        lock.unlock()
        if inserted {
            persist()
        }
    }

    func contains(_ domain: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return domains.contains(domain.lowercased())
    }

    func clear() {
        lock.lock()
        domains.removeAll()
        lock.unlock()
        persist()
    }

    private func persist() {
        lock.lock()
        let storedDomains = domains.sorted()
        lock.unlock()
        defaults.set(storedDomains, forKey: persistenceKey)
    }
}
