import XCTest
@testable import Trabant

final class MITMTLSFailureHandlerTests: XCTestCase {
    func testCertificateUnknownBypassesHost() {
        XCTAssertTrue(
            MITMTLSFailureHandler.shouldBypassHost(
                for: "handshakeFailed(...SSLV3_ALERT_CERTIFICATE_UNKNOWN...)",
                sawApplicationData: false
            )
        )
    }

    func testEarlyEOFBypassesHost() {
        XCTAssertTrue(
            MITMTLSFailureHandler.shouldBypassHost(
                for: "handshakeFailed(...EOF during handshake...)",
                sawApplicationData: false
            )
        )
    }

    func testEOFDoesNotBypassAfterApplicationData() {
        XCTAssertFalse(
            MITMTLSFailureHandler.shouldBypassHost(
                for: "handshakeFailed(...EOF during handshake...)",
                sawApplicationData: true
            )
        )
    }
}
