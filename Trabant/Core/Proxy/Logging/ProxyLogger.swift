import Foundation
import OSLog

enum ProxyLogger {
    private static let logger = Logger(subsystem: "Trabant", category: "Proxy")

    static var isVerboseEnabled = true

    static func debug(_ message: @autoclosure () -> String) {
        guard isVerboseEnabled else { return }
        let value = message()
        logger.debug("\(value, privacy: .public)")
    }

    static func info(_ message: @autoclosure () -> String) {
        let value = message()
        logger.info("\(value, privacy: .public)")
    }

    static func error(_ message: @autoclosure () -> String) {
        let value = message()
        logger.error("\(value, privacy: .public)")
    }
}
