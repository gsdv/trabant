import Foundation
import Compression
import zlib

enum BodyFormatter {
    static let maxDisplaySize = 5 * 1024 * 1024 // 5 MB

    static func format(data: Data?, mimeType: String?, contentEncoding: String? = nil) -> String {
        guard let data = data, !data.isEmpty else {
            return "(empty body)"
        }

        if data.count > maxDisplaySize {
            return "(body too large: \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)))"
        }

        if let encoding = contentEncoding?.lowercased(),
           encoding != "identity",
           let decoded = decodeEncodedBody(data, encoding: encoding) {
            return formatDecodedText(decoded, mimeType: mimeType)
        }

        return formatDecodedText(data, mimeType: mimeType)
    }

    private static func formatDecodedText(_ data: Data, mimeType: String?) -> String {
        // Try to decode as UTF-8 text
        guard let text = String(data: data, encoding: .utf8) else {
            return "(binary body, \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)))"
        }

        // Pretty-print JSON if applicable
        let mime = mimeType?.lowercased() ?? ""
        if mime.contains("json") || looksLikeJSON(text) {
            return prettyJSON(text) ?? text
        }

        return text
    }

    private static func decodeEncodedBody(_ data: Data, encoding: String) -> Data? {
        let encodings = encoding
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }

        guard !encodings.isEmpty else { return nil }

        return encodings.reversed().reduce(Optional(data)) { partial, step in
            guard let partial else { return nil }

            switch step {
            case "identity":
                return partial
            case "gzip":
                return gunzip(partial)
            case "deflate":
                return inflate(partial)
            case "br":
                return decompress(partial, algorithm: COMPRESSION_BROTLI)
            default:
                return nil
            }
        }
    }

    private static func gunzip(_ data: Data) -> Data? {
        inflateZlib(data, windowBits: 47)
    }

    private static func inflate(_ data: Data) -> Data? {
        inflateZlib(data, windowBits: 47) ?? inflateZlib(data, windowBits: -15)
    }

    private static func inflateZlib(_ data: Data, windowBits: Int32) -> Data? {
        guard !data.isEmpty else { return Data() }

        var stream = z_stream()
        let status = data.withUnsafeBytes { bytes -> Int32 in
            guard let baseAddress = bytes.bindMemory(to: Bytef.self).baseAddress else {
                return Z_DATA_ERROR
            }
            stream.next_in = UnsafeMutablePointer(mutating: baseAddress)
            stream.avail_in = uInt(bytes.count)
            return inflateInit2_(&stream, windowBits, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        }

        guard status == Z_OK else { return nil }
        defer { inflateEnd(&stream) }

        let chunkSize = 32 * 1024
        var output = Data()
        var buffer = [UInt8](repeating: 0, count: chunkSize)

        while true {
            let result = buffer.withUnsafeMutableBytes { outputBytes -> Int32 in
                guard let baseAddress = outputBytes.bindMemory(to: Bytef.self).baseAddress else {
                    return Z_BUF_ERROR
                }
                stream.next_out = baseAddress
                stream.avail_out = uInt(chunkSize)
                return zlib.inflate(&stream, Z_NO_FLUSH)
            }

            let produced = chunkSize - Int(stream.avail_out)
            if produced > 0 {
                output.append(contentsOf: buffer.prefix(produced))
            }

            switch result {
            case Z_STREAM_END:
                return output
            case Z_OK:
                continue
            case Z_BUF_ERROR where stream.avail_in == 0:
                return output.isEmpty ? nil : output
            default:
                return nil
            }
        }
    }

    private static func decompress(_ data: Data, algorithm: compression_algorithm) -> Data? {
        guard !data.isEmpty else { return Data() }

        let destinationBufferSize = 64 * 1024
        let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: destinationBufferSize)
        defer { destinationBuffer.deallocate() }
        let placeholderBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 1)
        defer { placeholderBuffer.deallocate() }

        var stream = compression_stream(
            dst_ptr: placeholderBuffer,
            dst_size: 0,
            src_ptr: UnsafePointer(placeholderBuffer),
            src_size: 0,
            state: nil
        )
        var status = compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, algorithm)
        guard status != COMPRESSION_STATUS_ERROR else { return nil }
        defer { compression_stream_destroy(&stream) }

        var output = Data()

        return data.withUnsafeBytes { inputBytes -> Data? in
            guard let sourceBase = inputBytes.bindMemory(to: UInt8.self).baseAddress else {
                return nil
            }

            stream.src_ptr = sourceBase
            stream.src_size = inputBytes.count

            repeat {
                stream.dst_ptr = destinationBuffer
                stream.dst_size = destinationBufferSize

                status = compression_stream_process(&stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                let produced = destinationBufferSize - stream.dst_size
                if produced > 0 {
                    output.append(destinationBuffer, count: produced)
                }
            } while status == COMPRESSION_STATUS_OK

            guard status == COMPRESSION_STATUS_END else { return nil }
            return output
        }
    }

    static func prettyJSON(_ text: String) -> String? {
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let result = String(data: pretty, encoding: .utf8)
        else { return nil }
        return result
    }

    private static func looksLikeJSON(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed.hasPrefix("{") && trimmed.hasSuffix("}"))
            || (trimmed.hasPrefix("[") && trimmed.hasSuffix("]"))
    }

    static func formatHeaders(_ headers: [(String, String)]) -> String {
        headers.map { "\($0.0): \($0.1)" }.joined(separator: "\n")
    }

    static func headerValue(_ name: String, in headers: [(String, String)]) -> String? {
        headers.first(where: { $0.0.caseInsensitiveCompare(name) == .orderedSame })?.1
    }
}

enum HostnameResolver {
    static func resolve(ip: String) async -> String? {
        await withCheckedContinuation { continuation in
            var hints = addrinfo()
            hints.ai_flags = AI_NUMERICHOST
            hints.ai_family = AF_INET

            var result: UnsafeMutablePointer<addrinfo>?
            guard getaddrinfo(ip, nil, &hints, &result) == 0, let res = result else {
                continuation.resume(returning: nil)
                return
            }
            defer { freeaddrinfo(result) }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let err = getnameinfo(
                res.pointee.ai_addr,
                res.pointee.ai_addrlen,
                &hostname,
                socklen_t(hostname.count),
                nil, 0, 0
            )
            if err == 0 {
                let name = String(cString: hostname)
                // Don't return the IP as "hostname"
                continuation.resume(returning: name != ip ? name : nil)
            } else {
                continuation.resume(returning: nil)
            }
        }
    }
}
