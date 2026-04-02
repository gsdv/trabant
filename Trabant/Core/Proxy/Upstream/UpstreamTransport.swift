import Foundation
import NIOCore
import NIOHTTP1

enum UpstreamHeaderNormalizer {
    private static let blockedRequestHeaders = Set([
        "connection",
        "proxy-connection",
        "keep-alive",
        "transfer-encoding",
        "upgrade",
        "proxy-authenticate",
        "proxy-authorization",
        "te",
        "trailer",
        "content-length",
        "host",
        "accept-encoding",
    ])

    private static let blockedResponseHeaders = Set([
        "connection",
        "keep-alive",
        "proxy-authenticate",
        "proxy-authorization",
        "te",
        "trailer",
        "transfer-encoding",
        "upgrade",
        "content-length",
        "content-encoding",
    ])

    static func sanitizedRequestHeaders(_ headers: [(String, String)]) -> [(String, String)] {
        headers.compactMap { name, value in
            blockedRequestHeaders.contains(name.lowercased()) ? nil : (name, value)
        }
    }

    static func sanitizedResponseHeaders(_ headerFields: [AnyHashable: Any]) -> [(String, String)] {
        headerFields.compactMap { key, value in
            guard let name = key as? String else { return nil }
            guard !blockedResponseHeaders.contains(name.lowercased()) else { return nil }
            return (name, "\(value)")
        }
    }
}

final class UpstreamTransport: NSObject, @unchecked Sendable {
    static let shared = UpstreamTransport()

    private let taskLock = NSLock()
    private var tasks: [Int: TaskContext] = [:]
    private let maxBodyCapture = 5 * 1024 * 1024
    private let delegateQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "Trabant.UpstreamTransport"
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpMaximumConnectionsPerHost = 12
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        config.waitsForConnectivity = false
        config.connectionProxyDictionary = [:]
        return URLSession(configuration: config, delegate: self, delegateQueue: delegateQueue)
    }()

    private override init() {
        super.init()
    }

    func execute(
        request: UpstreamRequest,
        clientChannel: Channel,
        onSessionUpdated: @escaping @Sendable (ProxySession) -> Void
    ) {
        guard let url = request.urlObject else {
            let failure = ProxyFailure(kind: .upstreamHTTP, message: "Invalid upstream URL: \(request.url)")
            onSessionUpdated(request.failedSession(failure))
            sendProxyFailure(to: clientChannel, failure: failure)
            return
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.requestBody
        urlRequest.timeoutInterval = 30

        for (name, value) in UpstreamHeaderNormalizer.sanitizedRequestHeaders(request.requestHeaders) {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }
        urlRequest.setValue("identity", forHTTPHeaderField: "Accept-Encoding")

        let task = session.dataTask(with: urlRequest)
        let context = TaskContext(
            request: request,
            clientChannel: clientChannel,
            onSessionUpdated: onSessionUpdated
        )

        store(context, for: task.taskIdentifier)
        ProxyLogger.debug("upstream start session=\(request.sessionID) \(request.method) \(request.url)")
        task.resume()
    }

    private func store(_ context: TaskContext, for taskID: Int) {
        taskLock.lock()
        tasks[taskID] = context
        taskLock.unlock()
    }

    private func mutateContext(taskID: Int, _ update: (inout TaskContext) -> Void) -> TaskContext? {
        taskLock.lock()
        defer { taskLock.unlock() }
        guard var context = tasks[taskID] else { return nil }
        update(&context)
        tasks[taskID] = context
        return context
    }

    private func removeContext(taskID: Int) -> TaskContext? {
        taskLock.lock()
        defer { taskLock.unlock() }
        return tasks.removeValue(forKey: taskID)
    }

    private func sanitizedResponseHeaders(_ response: HTTPURLResponse) -> [(String, String)] {
        UpstreamHeaderNormalizer.sanitizedResponseHeaders(response.allHeaderFields)
    }

    private func writeResponseHead(_ response: HTTPURLResponse, context: TaskContext) {
        let headers = sanitizedResponseHeaders(response)
        let httpHeaders = HTTPHeaders(headers)
        let status = HTTPResponseStatus(statusCode: response.statusCode)
        let responseHead = HTTPResponseHead(version: .http1_1, status: status, headers: httpHeaders)
        context.clientChannel.eventLoop.execute {
            context.clientChannel.write(NIOAny(HTTPServerResponsePart.head(responseHead)), promise: nil)
            context.clientChannel.flush()
        }
    }

    private func writeResponseBody(_ data: Data, context: TaskContext) {
        context.clientChannel.eventLoop.execute {
            var buffer = context.clientChannel.allocator.buffer(capacity: data.count)
            buffer.writeBytes(data)
            context.clientChannel.writeAndFlush(NIOAny(HTTPServerResponsePart.body(.byteBuffer(buffer))), promise: nil)
        }
    }

    private func writeResponseEnd(context: TaskContext) {
        context.clientChannel.eventLoop.execute {
            context.clientChannel.writeAndFlush(NIOAny(HTTPServerResponsePart.end(nil)), promise: nil)
        }
    }

    private func sendProxyFailure(to channel: Channel, failure: ProxyFailure) {
        channel.eventLoop.execute {
            let body = failure.displayText.data(using: .utf8) ?? Data()
            var headers = HTTPHeaders()
            headers.add(name: "Content-Type", value: "text/plain; charset=utf-8")
            headers.add(name: "Content-Length", value: "\(body.count)")
            headers.add(name: "Connection", value: "close")

            let head = HTTPResponseHead(version: .http1_1, status: .badGateway, headers: headers)
            channel.write(NIOAny(HTTPServerResponsePart.head(head)), promise: nil)

            var buffer = channel.allocator.buffer(capacity: body.count)
            buffer.writeBytes(body)
            channel.write(NIOAny(HTTPServerResponsePart.body(.byteBuffer(buffer))), promise: nil)
            channel.writeAndFlush(NIOAny(HTTPServerResponsePart.end(nil)), promise: nil)
        }
    }

    private struct TaskContext: Sendable {
        let request: UpstreamRequest
        let clientChannel: Channel
        let onSessionUpdated: @Sendable (ProxySession) -> Void
        var responseStatusCode: Int?
        var responseHeaders: [(String, String)] = []
        var responseBody = Data()
        var responseHeadWritten = false
        var upstreamProtocol: String?
    }
}

extension UpstreamTransport: URLSessionDataDelegate, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let httpResponse = response as? HTTPURLResponse else {
            completionHandler(.allow)
            return
        }

        guard let context = mutateContext(taskID: dataTask.taskIdentifier, {
            $0.responseStatusCode = httpResponse.statusCode
            $0.responseHeaders = sanitizedResponseHeaders(httpResponse)
            $0.responseHeadWritten = true
        }) else {
            completionHandler(.cancel)
            return
        }

        ProxyLogger.debug("upstream response session=\(context.request.sessionID) status=\(httpResponse.statusCode) url=\(context.request.url)")
        writeResponseHead(httpResponse, context: context)
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let context = mutateContext(taskID: dataTask.taskIdentifier, {
            if $0.responseBody.count < maxBodyCapture {
                let remaining = maxBodyCapture - $0.responseBody.count
                $0.responseBody.append(data.prefix(remaining))
            }
        }) else {
            return
        }

        writeResponseBody(data, context: context)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        _ = mutateContext(taskID: task.taskIdentifier) {
            $0.upstreamProtocol = metrics.transactionMetrics.last?.networkProtocolName
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let context = removeContext(taskID: task.taskIdentifier) else { return }

        if let error {
            let failure = ProxyFailureClassifier.classifyUpstream(error)
            ProxyLogger.error("upstream failure session=\(context.request.sessionID) kind=\(failure.kind.rawValue) url=\(context.request.url) error=\(failure.message)")
            if context.responseHeadWritten {
                writeResponseEnd(context: context)
            } else {
                sendProxyFailure(to: context.clientChannel, failure: failure)
            }
            context.onSessionUpdated(context.request.failedSession(failure))
            return
        }

        writeResponseEnd(context: context)

        let session = context.request.completedSession(
            responseStatusCode: context.responseStatusCode,
            responseHeaders: context.responseHeaders,
            responseBody: context.responseBody.isEmpty ? nil : context.responseBody,
            responseTimestamp: Date(),
            upstreamProtocol: context.upstreamProtocol ?? "http/1.1"
        )
        context.onSessionUpdated(session)
    }
}
