import Foundation
import Combine
import Darwin
import IOKit.ps

struct CPUSample: Equatable, Sendable {
    var user: Double = 0
    var system: Double = 0
    var idle: Double = 1
    var total: Double { max(0, min(1, user + system)) }
}

struct MemorySample: Equatable, Sendable {
    var used: UInt64 = 0
    var total: UInt64 = 1
    var compressed: UInt64 = 0
    var wired: UInt64 = 0
    var cached: UInt64 = 0
    var fraction: Double { total == 0 ? 0 : Double(used) / Double(total) }
    /// Rough analogue of Activity Monitor's pressure gauge.
    var pressure: Double { total == 0 ? 0 : min(1, Double(wired + compressed) / Double(total) * 2.2) }
}

struct DiskSample: Equatable, Sendable {
    var free: UInt64 = 0
    var total: UInt64 = 1
    var used: UInt64 { total > free ? total - free : 0 }
    var fraction: Double { total == 0 ? 0 : Double(used) / Double(total) }
}

struct NetworkSample: Equatable, Sendable {
    var downBytesPerSecond: Double = 0
    var upBytesPerSecond: Double = 0
    var totalIn: UInt64 = 0
    var totalOut: UInt64 = 0
}

struct BatterySample: Equatable, Sendable {
    var isPresent = false
    var percentage: Double = 0
    var isCharging = false
    var isPluggedIn = false
    var minutesRemaining: Int?
    var health: String?
    var cycleCount: Int?
}

struct ProcessSample: Equatable, Identifiable, Sendable {
    var id: Int32
    var name: String
    var cpu: Double
    var memory: UInt64
}

/// Polls the kernel for the numbers the system widget shows. Sampling only runs while
/// something is actually watching, so a closed panel costs nothing.
