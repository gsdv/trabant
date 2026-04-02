import XCTest
@testable import Trabant

final class ProxyTLSSettingsTests: XCTestCase {
    func testMITMAdvertisesHTTP2AndHTTP11() {
        XCTAssertTrue(ProxyTLSSettings.mitmApplicationProtocols.contains("h2"))
        XCTAssertTrue(ProxyTLSSettings.mitmApplicationProtocols.contains("http/1.1"))
    }
}
