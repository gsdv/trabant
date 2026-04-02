import Foundation
import XCTest
import zlib
@testable import Trabant

final class BodyFormatterTests: XCTestCase {
    func testPrettyPrintedJSONIsReturnedForJSONBodies() throws {
        let source = #"{"b":1,"a":2}"#.data(using: .utf8)
        let formatted = BodyFormatter.format(data: source, mimeType: "application/json")

        XCTAssertTrue(formatted.contains("\n"))
        XCTAssertTrue(formatted.contains("\"a\""))
    }

    func testGzipBodiesAreDecodedBeforeDisplay() throws {
        let source = #"{"message":"hello"}"#.data(using: .utf8)!
        let compressed = try gzip(source)

        let formatted = BodyFormatter.format(
            data: compressed,
            mimeType: "application/json",
            contentEncoding: "gzip"
        )

        XCTAssertTrue(formatted.contains("\"message\""))
        XCTAssertTrue(formatted.contains("hello"))
    }

    func testHeaderLookupIsCaseInsensitive() {
        let headers = [("Content-Encoding", "gzip")]
        XCTAssertEqual(BodyFormatter.headerValue("content-encoding", in: headers), "gzip")
    }

    private func gzip(_ data: Data) throws -> Data {
        guard !data.isEmpty else { return Data() }

        var stream = z_stream()
        let initStatus = deflateInit2_(
            &stream,
            Z_DEFAULT_COMPRESSION,
            Z_DEFLATED,
            31,
            8,
            Z_DEFAULT_STRATEGY,
            ZLIB_VERSION,
            Int32(MemoryLayout<z_stream>.size)
        )
        guard initStatus == Z_OK else {
            throw CompressionError.initializationFailed
        }
        defer { deflateEnd(&stream) }

        let chunkSize = 16 * 1024
        var output = Data()
        var buffer = [UInt8](repeating: 0, count: chunkSize)

        try data.withUnsafeBytes { inputBytes in
            guard let baseAddress = inputBytes.bindMemory(to: Bytef.self).baseAddress else {
                throw CompressionError.invalidInput
            }

            stream.next_in = UnsafeMutablePointer(mutating: baseAddress)
            stream.avail_in = uInt(inputBytes.count)

            repeat {
                let result = buffer.withUnsafeMutableBytes { outputBytes -> Int32 in
                    guard let destination = outputBytes.bindMemory(to: Bytef.self).baseAddress else {
                        return Z_BUF_ERROR
                    }

                    stream.next_out = destination
                    stream.avail_out = uInt(chunkSize)
                    return deflate(&stream, Z_FINISH)
                }

                let produced = chunkSize - Int(stream.avail_out)
                if produced > 0 {
                    output.append(contentsOf: buffer.prefix(produced))
                }

                switch result {
                case Z_STREAM_END:
                    return
                case Z_OK:
                    continue
                default:
                    throw CompressionError.compressionFailed
                }
            } while true
        }

        return output
    }

    private enum CompressionError: Error {
        case initializationFailed
        case invalidInput
        case compressionFailed
    }
}
