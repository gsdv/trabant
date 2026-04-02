import Foundation
import XCTest
@testable import Trabant

final class ProxyFailureTests: XCTestCase {
    func testDNSFailuresAreClassifiedSeparately() {
        let failure = ProxyFailureClassifier.classifyUpstream(URLError(.cannotFindHost))
        XCTAssertEqual(failure.kind, .upstreamDNS)
    }

    func testTLSFailuresAreClassifiedSeparately() {
        let failure = ProxyFailureClassifier.classifyUpstream(URLError(.secureConnectionFailed))
        XCTAssertEqual(failure.kind, .upstreamTLS)
    }

    func testConnectFailuresAreClassifiedSeparately() {
        let failure = ProxyFailureClassifier.classifyUpstream(URLError(.cannotConnectToHost))
        XCTAssertEqual(failure.kind, .upstreamConnect)
    }

    func testClientRejectedMITMIncludesHostAndReason() {
        let failure = ProxyFailureClassifier.clientRejectedMITM(
            host: "pbs.twimg.com",
            error: NSError(domain: NSOSStatusErrorDomain, code: -9807)
        )

        XCTAssertEqual(failure.kind, .clientRejectedMITM)
        XCTAssertTrue(failure.message.contains("pbs.twimg.com"))
    }
}
