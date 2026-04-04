import XCTest
@testable import Trabant

@MainActor
final class CaptureStoreDisplayTests: XCTestCase {
    func testSuccessfulTunnelCollapsesEarlierLearningFailure() {
        let store = CaptureStore()
        let base = Date(timeIntervalSince1970: 1_000)

        store.addSession(
            makeSession(
                host: "api.twitter.com",
                port: 443,
                path: "/",
                timestamp: base,
                statusCode: nil,
                responseHeaders: [],
                captureMode: .tunnel,
                failureReason: "Client rejected MITM certificate: api.twitter.com rejected the generated certificate. Future requests will use a raw tunnel."
            )
        )
        store.addSession(
            makeSession(
                host: "api.twitter.com",
                port: 443,
                path: "/",
                timestamp: base.addingTimeInterval(1),
                statusCode: 200,
                responseHeaders: [],
                captureMode: .tunnel,
                failureReason: "Client previously rejected the MITM certificate for this host. Using a raw CONNECT tunnel."
            )
        )
        store.flushPendingChanges()

        let visible = store.visibleSessions
        XCTAssertEqual(visible.count, 1)
        XCTAssertEqual(visible.first?.session.host, "api.twitter.com")
        XCTAssertEqual(visible.first?.session.responseStatusCode, 200)
        XCTAssertEqual(visible.first?.collapsedCount, 2)
    }

    func testRapidDuplicateMediaRequestsCollapseIntoSingleVisibleRow() {
        let store = CaptureStore()
        let base = Date(timeIntervalSince1970: 2_000)
        let headers = [("Content-Type", "image/jpeg")]

        store.addSession(
            makeSession(
                host: "pbs.twimg.com",
                port: 443,
                path: "/profile_images/123/avatar.jpg",
                timestamp: base,
                statusCode: 200,
                responseHeaders: headers,
                captureMode: .mitm
            )
        )
        store.addSession(
            makeSession(
                host: "pbs.twimg.com",
                port: 443,
                path: "/profile_images/123/avatar.jpg",
                timestamp: base.addingTimeInterval(1),
                statusCode: 200,
                responseHeaders: headers,
                captureMode: .mitm
            )
        )
        store.flushPendingChanges()

        let visible = store.visibleSessions
        XCTAssertEqual(visible.count, 1)
        XCTAssertEqual(visible.first?.session.path, "/profile_images/123/avatar.jpg")
        XCTAssertEqual(visible.first?.collapsedCount, 2)
    }

    private func makeSession(
        host: String,
        port: Int,
        path: String,
        timestamp: Date,
        statusCode: Int?,
        responseHeaders: [(String, String)],
        captureMode: ProxyCaptureMode,
        failureReason: String? = nil
    ) -> ProxySession {
        ProxySession(
            id: UUID(),
            deviceIP: "192.168.1.10",
            scheme: port == 80 ? "http" : "https",
            method: captureMode == .tunnel ? "CONNECT" : "GET",
            host: host,
            port: port,
            path: path,
            url: "\(port == 80 ? "http" : "https")://\(host)\(port == 443 || port == 80 ? "" : ":\(port)")\(path)",
            requestHeaders: [],
            requestBody: nil,
            responseStatusCode: statusCode,
            responseHeaders: responseHeaders,
            responseBody: nil,
            requestTimestamp: timestamp,
            responseTimestamp: statusCode == nil ? timestamp : timestamp.addingTimeInterval(0.05),
            error: nil,
            requestProtocol: captureMode == .tunnel ? "tunnel" : "h2",
            upstreamProtocol: nil,
            captureMode: captureMode,
            failureReason: failureReason,
            isDecrypted: captureMode == .mitm
        )
    }
}
