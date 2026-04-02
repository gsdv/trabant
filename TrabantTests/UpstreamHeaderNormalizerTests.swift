import XCTest
@testable import Trabant

final class UpstreamHeaderNormalizerTests: XCTestCase {
    func testRequestHeadersForceIdentityEncoding() {
        let headers = UpstreamHeaderNormalizer.sanitizedRequestHeaders([
            ("Accept-Encoding", "gzip, deflate, br"),
            ("User-Agent", "Twitter"),
            ("Host", "pbs.twimg.com"),
        ])

        XCTAssertEqual(headers.count, 1)
        XCTAssertEqual(headers.first?.0, "User-Agent")
    }

    func testResponseHeadersDropEncodingSensitiveValues() {
        let headers = UpstreamHeaderNormalizer.sanitizedResponseHeaders([
            "Content-Type": "text/plain",
            "Content-Length": "12",
            "Content-Encoding": "gzip",
            "Connection": "keep-alive",
        ])

        XCTAssertEqual(headers.count, 1)
        XCTAssertEqual(headers.first?.0, "Content-Type")
        XCTAssertEqual(headers.first?.1, "text/plain")
    }
}
