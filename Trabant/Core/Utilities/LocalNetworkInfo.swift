import Foundation
import Darwin

enum LocalNetworkInfo {
    static func localIPAddress() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var bestIP: String?

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let iface = ptr.pointee
            let family = iface.ifa_addr.pointee.sa_family
            guard family == UInt8(AF_INET) else { continue }

            let name = String(cString: iface.ifa_name)
            // Prefer en0 (Wi-Fi) or en1
            guard name.hasPrefix("en") else { continue }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                iface.ifa_addr,
                socklen_t(iface.ifa_addr.pointee.sa_len),
                &hostname,
                socklen_t(hostname.count),
                nil, 0,
                NI_NUMERICHOST
            )
            if result == 0 {
                let ip = String(cString: hostname)
                if name == "en0" { return ip }
                if bestIP == nil { bestIP = ip }
            }
        }
        return bestIP
    }
}
