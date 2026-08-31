import Foundation
import Combine
import Darwin
import IOKit.ps

enum Format {
    static func bytes(_ value: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB, .useKB]
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: Int64(value))
    }

    static func rate(_ bytesPerSecond: Double) -> String {
        let value = max(0, bytesPerSecond)
        if value < 1024 { return "\(Int(value)) B/s" }
        if value < 1024 * 1024 { return String(format: "%.0f KB/s", value / 1024) }
        if value < 1024 * 1024 * 1024 { return String(format: "%.1f MB/s", value / 1_048_576) }
        return String(format: "%.2f GB/s", value / 1_073_741_824)
    }

    static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    static func minutes(_ value: Int) -> String {
        value >= 60 ? "\(value / 60)h \(value % 60)m" : "\(value)m"
    }
}
