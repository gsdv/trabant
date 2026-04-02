import Foundation

struct DeviceRecord: Identifiable, Hashable, Sendable {
    var id: String { ipAddress }
    let ipAddress: String
    var hostname: String?
    var customName: String?
    var detectedName: String?
    var firstSeenAt: Date
    var lastSeenAt: Date
    var sessionCount: Int

    var displayName: String {
        customName ?? detectedName ?? hostname ?? ipAddress
    }
}
