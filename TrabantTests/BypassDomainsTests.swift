import XCTest
@testable import Trabant

final class BypassDomainsTests: XCTestCase {
    func testDomainsPersistAcrossInstances() {
        let suiteName = "BypassDomainsTests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Unable to create isolated defaults suite")
            return
        }
        let key = "test-bypass-domains"
        defaults.removePersistentDomain(forName: suiteName)

        let first = BypassDomains(defaults: defaults, persistenceKey: key)
        first.add("API.Twitter.com")

        let second = BypassDomains(defaults: defaults, persistenceKey: key)
        XCTAssertTrue(second.contains("api.twitter.com"))
        XCTAssertTrue(second.contains("API.TWITTER.COM"))

        defaults.removePersistentDomain(forName: suiteName)
    }
}
