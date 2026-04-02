import Foundation

enum ProxyFailureKind: String, Sendable {
    case clientRejectedMITM = "Client rejected MITM certificate"
    case unsupportedDownstreamProtocol = "Unsupported downstream protocol"
    case upstreamDNS = "Upstream DNS failure"
    case upstreamConnect = "Upstream connect failure"
    case upstreamTLS = "Upstream TLS failure"
    case upstreamHTTP = "Upstream HTTP failure"
    case localProxy = "Local proxy failure"

    var label: String { rawValue }
}

struct ProxyFailure: Sendable {
    let kind: ProxyFailureKind
    let message: String

    var displayText: String {
        "\(kind.label): \(message)"
    }
}

enum ProxyFailureClassifier {
    static func localProxy(operation: String, port: Int, error: Error) -> ProxyFailure {
        ProxyFailure(
            kind: .localProxy,
            message: "\(operation) on port \(port) failed: \(String(describing: error))"
        )
    }

    static func clientRejectedMITM(host: String, error: Error) -> ProxyFailure {
        let description = String(describing: error)
        return ProxyFailure(
            kind: .clientRejectedMITM,
            message: "\(host) rejected the generated certificate. Future requests will use a raw tunnel. Underlying error: \(description)"
        )
    }

    static func unsupportedDownstreamProtocol(_ error: Error) -> ProxyFailure {
        ProxyFailure(kind: .unsupportedDownstreamProtocol, message: String(describing: error))
    }

    static func classifyUpstream(_ error: Error) -> ProxyFailure {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cannotFindHost, .dnsLookupFailed:
                return ProxyFailure(kind: .upstreamDNS, message: urlError.localizedDescription)
            case .secureConnectionFailed,
                 .serverCertificateHasBadDate,
                 .serverCertificateUntrusted,
                 .serverCertificateHasUnknownRoot,
                 .serverCertificateNotYetValid,
                 .clientCertificateRejected,
                 .clientCertificateRequired:
                return ProxyFailure(kind: .upstreamTLS, message: urlError.localizedDescription)
            case .cannotConnectToHost,
                 .networkConnectionLost,
                 .notConnectedToInternet,
                 .timedOut,
                 .internationalRoamingOff,
                 .callIsActive,
                 .dataNotAllowed:
                return ProxyFailure(kind: .upstreamConnect, message: urlError.localizedDescription)
            default:
                return ProxyFailure(kind: .upstreamHTTP, message: urlError.localizedDescription)
            }
        }

        let description = String(describing: error)
        if description.contains("handshake") || description.contains("certificate") {
            return ProxyFailure(kind: .upstreamTLS, message: description)
        }
        if description.contains("dns") || description.contains("lookup") {
            return ProxyFailure(kind: .upstreamDNS, message: description)
        }
        if description.contains("connect") || description.contains("Connection errors") {
            return ProxyFailure(kind: .upstreamConnect, message: description)
        }
        return ProxyFailure(kind: .upstreamHTTP, message: description)
    }
}
