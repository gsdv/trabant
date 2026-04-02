import Foundation
import Crypto
import X509
import SwiftASN1
import NIOSSL

/// Manages the local root CA and on-demand leaf certificate generation for HTTPS interception.
final class CertificateAuthority: @unchecked Sendable {
    private struct CachedLeafMaterial {
        let certPEM: String
        let keyPEM: String
    }

    private var caKey: P256.Signing.PrivateKey?
    private var caCert: X509.Certificate?
    private var leafCache: [String: CachedLeafMaterial] = [:]
    private let lock = NSLock()

    private static let appSupportDir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Trabant/ca", isDirectory: true)
    }()

    private static let exportDir: URL = {
        appSupportDir.appendingPathComponent("exported", isDirectory: true)
    }()

    private var caKeyPath: URL { Self.appSupportDir.appendingPathComponent("trabant-root-ca-key.pem") }
    private var caCertPath: URL { Self.appSupportDir.appendingPathComponent("trabant-root-ca.pem") }
    private var exportedCerPath: URL { Self.exportDir.appendingPathComponent("trabant-root-ca.cer") }

    // MARK: - CA Generation

    func generateCA() throws {
        let key = P256.Signing.PrivateKey()

        let name = try DistinguishedName {
            CommonName("Trabant Root CA")
            OrganizationName("Trabant Local Proxy")
        }

        let now = Date()
        let caPublicKey = Certificate.PublicKey(key.publicKey)
        let cert = try X509.Certificate(
            version: .v3,
            serialNumber: X509.Certificate.SerialNumber(),
            publicKey: caPublicKey,
            notValidBefore: now - 86400,
            notValidAfter: now + (365.25 * 24 * 3600 * 10), // 10 years
            issuer: name,
            subject: name,
            signatureAlgorithm: .ecdsaWithSHA256,
            extensions: X509.Certificate.Extensions {
                Critical(BasicConstraints.isCertificateAuthority(maxPathLength: 0))
                Critical(KeyUsage(keyCertSign: true, cRLSign: true))
                SubjectKeyIdentifier(hash: caPublicKey)
            },
            issuerPrivateKey: .init(key)
        )

        caKey = key
        caCert = cert

        // Persist to disk
        try FileManager.default.createDirectory(at: Self.appSupportDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: Self.exportDir, withIntermediateDirectories: true)

        let keyPEM = key.pemRepresentation
        try keyPEM.write(to: caKeyPath, atomically: true, encoding: .utf8)

        let certPEM = try cert.serializeAsPEM().pemString
        try certPEM.write(to: caCertPath, atomically: true, encoding: .utf8)

        // Export DER (.cer) for iPhone
        try exportDER(cert: cert)

        // Clear leaf cache since CA changed
        lock.lock()
        leafCache.removeAll()
        lock.unlock()
    }

    // MARK: - Load Existing

    func loadExistingCA() throws -> Bool {
        guard FileManager.default.fileExists(atPath: caKeyPath.path),
              FileManager.default.fileExists(atPath: caCertPath.path) else {
            return false
        }

        let keyPEM = try String(contentsOf: caKeyPath, encoding: .utf8)
        let certPEM = try String(contentsOf: caCertPath, encoding: .utf8)

        caKey = try P256.Signing.PrivateKey(pemRepresentation: keyPEM)
        let pemDoc = try PEMDocument(pemString: certPEM)
        caCert = try X509.Certificate(pemDocument: pemDoc)
        lock.lock()
        leafCache.removeAll()
        lock.unlock()
        return true
    }

    // MARK: - Export

    func exportedCertPath() throws -> URL {
        if !FileManager.default.fileExists(atPath: exportedCerPath.path), let cert = caCert {
            try exportDER(cert: cert)
        }
        return exportedCerPath
    }

    func exportedCertData() throws -> Data {
        try Data(contentsOf: exportedCerPath)
    }

    private func exportDER(cert: X509.Certificate) throws {
        // PEM to DER: strip headers and base64-decode
        let pem = try cert.serializeAsPEM().pemString
        let base64 = pem
            .replacingOccurrences(of: "-----BEGIN CERTIFICATE-----", with: "")
            .replacingOccurrences(of: "-----END CERTIFICATE-----", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
        guard let der = Data(base64Encoded: base64) else {
            throw CertError.exportFailed
        }
        try der.write(to: exportedCerPath, options: .atomic)
    }

    // MARK: - Leaf Certificates

    /// Returns the full NIOSSL certificate chain (leaf + CA) and key for the given hostname.
    func leafCertificate(for hostname: String) throws -> (chain: [NIOSSLCertificate], key: NIOSSLPrivateKey) {
        lock.lock()
        if let cached = leafCache[hostname] {
            lock.unlock()
            return try makeLeafArtifacts(from: cached, hostname: hostname)
        }
        lock.unlock()

        guard let caKey = caKey, let caCert = caCert else {
            throw CertError.caNotGenerated
        }

        let leafKey = P256.Signing.PrivateKey()
        let leafPublicKey = Certificate.PublicKey(leafKey.publicKey)
        let caPublicKey = Certificate.PublicKey(caKey.publicKey)

        let leafName = try DistinguishedName {
            CommonName(hostname)
        }

        let now = Date()
        let leafCert = try X509.Certificate(
            version: .v3,
            serialNumber: X509.Certificate.SerialNumber(),
            publicKey: leafPublicKey,
            notValidBefore: now - 86400,
            notValidAfter: now + (365.25 * 24 * 3600), // 1 year
            issuer: caCert.subject,
            subject: leafName,
            signatureAlgorithm: .ecdsaWithSHA256,
            extensions: X509.Certificate.Extensions {
                Critical(BasicConstraints.notCertificateAuthority)
                Critical(KeyUsage(digitalSignature: true))
                try ExtendedKeyUsage([.serverAuth])
                SubjectAlternativeNames([.dnsName(hostname)])
                AuthorityKeyIdentifier(keyIdentifier: try SubjectKeyIdentifier(hash: caPublicKey).keyIdentifier)
                SubjectKeyIdentifier(hash: leafPublicKey)
            },
            issuerPrivateKey: .init(caKey)
        )

        let certPEM = try leafCert.serializeAsPEM().pemString
        let keyPEM = leafKey.pemRepresentation
        let cached = CachedLeafMaterial(certPEM: certPEM, keyPEM: keyPEM)

        lock.lock()
        leafCache[hostname] = cached
        lock.unlock()

        return try makeLeafArtifacts(from: cached, hostname: hostname)
    }

    var isReady: Bool { caKey != nil && caCert != nil }

    private func makeLeafArtifacts(from cached: CachedLeafMaterial, hostname: String) throws -> (chain: [NIOSSLCertificate], key: NIOSSLPrivateKey) {
        guard let caCert else {
            throw CertError.caNotGenerated
        }

        let caPEM = try caCert.serializeAsPEM().pemString
        let sslLeafCert = try NIOSSLCertificate(bytes: Array(cached.certPEM.utf8), format: .pem)
        let caSSLCert = try NIOSSLCertificate(bytes: Array(caPEM.utf8), format: .pem)
        let sslKey = try NIOSSLPrivateKey(bytes: Array(cached.keyPEM.utf8), format: .pem)

        return ([sslLeafCert, caSSLCert], sslKey)
    }
}

enum CertError: Error, LocalizedError {
    case caNotGenerated
    case exportFailed

    var errorDescription: String? {
        switch self {
        case .caNotGenerated: return "CA certificate has not been generated yet"
        case .exportFailed: return "Failed to export certificate"
        }
    }
}
