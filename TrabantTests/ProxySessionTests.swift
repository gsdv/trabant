import XCTest
@testable import Trabant

final class ProxySessionTests: XCTestCase {
    func testRequestProtocolBadgesReflectCapturedProtocol() {
        XCTAssertEqual(makeSession(requestProtocol: "http/1.1").requestProtocolBadge, "H1")
        XCTAssertEqual(makeSession(requestProtocol: "h2").requestProtocolBadge, "H2")
        XCTAssertEqual(makeSession(requestProtocol: "tunnel").requestProtocolBadge, "TUNNEL")
    }

    func testFailureReasonMarksSessionComplete() {
        var session = makeSession()
        XCTAssertFalse(session.isComplete)

        session.failureReason = "Client rejected MITM certificate"

        XCTAssertTrue(session.isComplete)
    }

    func testContentTypeShortRecognizesImages() {
        let session = makeSession(responseHeaders: [("Content-Type", "image/jpeg")])
        XCTAssertEqual(session.contentTypeShort, "IMG")
    }

    func testCompletedUpstreamSessionPreservesOriginalPort() {
        let request = UpstreamRequest(
            sessionID: UUID(),
            deviceIP: "192.168.1.10",
            scheme: "https",
            method: "GET",
            host: "example.com",
            port: 8443,
            path: "/feed",
            url: "https://example.com:8443/feed",
            requestHeaders: [],
            requestBody: nil,
            requestTimestamp: Date(),
            requestProtocol: "h2",
            captureMode: .mitm,
            isDecrypted: true
        )

        let session = request.completedSession(
            responseStatusCode: 200,
            responseHeaders: [],
            responseBody: nil,
            responseTimestamp: Date(),
            upstreamProtocol: "h2"
        )

        XCTAssertEqual(session.port, 8443)
        XCTAssertEqual(session.upstreamProtocol, "h2")
        XCTAssertEqual(session.requestProtocol, "h2")
    }

    private func makeSession(
        responseHeaders: [(String, String)] = [],
        requestProtocol: String = "http/1.1"
    ) -> ProxySession {
        ProxySession(
            id: UUID(),
            deviceIP: "192.168.1.10",
            scheme: "https",
            method: "GET",
            host: "example.com",
            port: 443,
            path: "/feed",
            url: "https://example.com/feed",
            requestHeaders: [],
            requestBody: nil,
            responseStatusCode: nil,
            responseHeaders: responseHeaders,
            responseBody: nil,
            requestTimestamp: Date(),
            responseTimestamp: nil,
            error: nil,
            requestProtocol: requestProtocol,
            upstreamProtocol: nil,
            captureMode: .mitm,
            failureReason: nil,
            isDecrypted: true
        )
    }
}
