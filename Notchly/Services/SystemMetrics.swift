import Foundation
import Combine
import Darwin
import IOKit.ps

@MainActor
final class SystemMetrics: ObservableObject {
    @Published private(set) var cpu = CPUSample()
    @Published private(set) var memory = MemorySample()
    @Published private(set) var disk = DiskSample()
    @Published private(set) var network = NetworkSample()
    @Published private(set) var battery = BatterySample()
    @Published private(set) var topProcesses: [ProcessSample] = []
    @Published private(set) var cpuHistory: [Double] = Array(repeating: 0, count: 48)
    @Published private(set) var networkHistory: [Double] = Array(repeating: 0, count: 48)
    @Published private(set) var uptime: TimeInterval = 0

    /// How often a subscriber needs fresh numbers. `live` is the open Panel; `ambient`
    /// is the Idle handle, which shows the same readings but doesn't need them every
    /// second to feel current.
    enum Cadence {
        case live, ambient

        var fastInterval: TimeInterval { self == .live ? 1 : 5 }
        var slowInterval: TimeInterval { self == .live ? 5 : 20 }
    }

    private var liveSubscribers = 0
    private var ambientSubscribers = 0
    private var runningCadence: Cadence?
    private var fastTimer: Timer?
    private var slowTimer: Timer?

    private var previousCPUTicks: (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)?
    private var previousNetwork: (inBytes: UInt64, outBytes: UInt64, at: Date)?
    private var processTask: Task<Void, Never>?

    init() {}

    func subscribe(_ cadence: Cadence) {
        switch cadence {
        case .live: liveSubscribers += 1
        case .ambient: ambientSubscribers += 1
        }
        applyCadence()
    }

    func unsubscribe(_ cadence: Cadence) {
        switch cadence {
        case .live: liveSubscribers = max(0, liveSubscribers - 1)
        case .ambient: ambientSubscribers = max(0, ambientSubscribers - 1)
        }
        applyCadence()
    }

    /// The fastest cadence anyone asked for wins; no subscribers stops sampling
    /// entirely, which is the common case while the Panel is closed.
    private func applyCadence() {
        let wanted: Cadence? = liveSubscribers > 0 ? .live : (ambientSubscribers > 0 ? .ambient : nil)
        guard wanted != runningCadence else { return }
        runningCadence = wanted

        fastTimer?.invalidate(); fastTimer = nil
        slowTimer?.invalidate(); slowTimer = nil

        guard let wanted else {
            processTask?.cancel(); processTask = nil
            // Drop the baselines so the first sample after a gap isn't a huge delta.
            previousCPUTicks = nil
            previousNetwork = nil
            return
        }

        sampleFast()
        sampleSlow()
        fastTimer = Timer.scheduledTimer(withTimeInterval: wanted.fastInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sampleFast() }
        }
        slowTimer = Timer.scheduledTimer(withTimeInterval: wanted.slowInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sampleSlow() }
        }
        fastTimer?.tolerance = wanted.fastInterval / 5
        slowTimer?.tolerance = wanted.slowInterval / 5
    }

    /// Only worth the `ps` call when something is actually showing the list.
    private var wantsProcessList: Bool { liveSubscribers > 0 }

    private func sampleFast() {
        cpu = readCPU()
        memory = readMemory()
        network = readNetwork()
        uptime = Self.systemUptime()

        cpuHistory = Array((cpuHistory.dropFirst() + [cpu.total]).suffix(48))
        let throughput = network.downBytesPerSecond + network.upBytesPerSecond
        networkHistory = Array((networkHistory.dropFirst() + [throughput]).suffix(48))
    }

    private func sampleSlow() {
        disk = readDisk()
        battery = Self.readBattery()
        if wantsProcessList { refreshProcesses() }
    }

    private func readCPU() -> CPUSample {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return cpu }

        let ticks = (user: UInt64(info.cpu_ticks.0),
                     system: UInt64(info.cpu_ticks.1),
                     idle: UInt64(info.cpu_ticks.2),
                     nice: UInt64(info.cpu_ticks.3))
        defer { previousCPUTicks = ticks }
        guard let previous = previousCPUTicks else { return CPUSample() }

        let user = Double(ticks.user &- previous.user) + Double(ticks.nice &- previous.nice)
        let system = Double(ticks.system &- previous.system)
        let idle = Double(ticks.idle &- previous.idle)
        let total = user + system + idle
        guard total > 0 else { return cpu }
        return CPUSample(user: user / total, system: system / total, idle: idle / total)
    }

    private func readMemory() -> MemorySample {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return memory }

        let pageSize = Self.pageSize
        let wired = UInt64(stats.wire_count) * pageSize
        let compressed = UInt64(stats.compressor_page_count) * pageSize
        let purgeable = UInt64(stats.purgeable_count) * pageSize
        let internalPages = UInt64(stats.internal_page_count) * pageSize
        let cached = UInt64(stats.external_page_count) * pageSize
        // Mirrors Activity Monitor: app memory + wired + compressed.
        let appMemory = internalPages > purgeable ? internalPages - purgeable : 0
        let used = appMemory + wired + compressed

        var total: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &total, &size, nil, 0)

        return MemorySample(used: min(used, total), total: max(total, 1),
                            compressed: compressed, wired: wired, cached: cached)
    }

    /// `vm_kernel_page_size` is a mutable global, so read it once through Mach instead.
    private static let pageSize: UInt64 = {
        var size: vm_size_t = 0
        guard host_page_size(mach_host_self(), &size) == KERN_SUCCESS else { return 16384 }
        return UInt64(size)
    }()

    private func readDisk() -> DiskSample {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        guard let values = try? url.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey
        ]) else { return disk }
        let free = UInt64(values.volumeAvailableCapacityForImportantUsage ?? 0)
        let total = UInt64(values.volumeTotalCapacity ?? 1)
        return DiskSample(free: free, total: max(total, 1))
    }

    private func readNetwork() -> NetworkSample {
        var inBytes: UInt64 = 0
        var outBytes: UInt64 = 0
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let first = addresses else { return network }
        defer { freeifaddrs(addresses) }

        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let current = pointer {
            defer { pointer = current.pointee.ifa_next }
            guard let sa = current.pointee.ifa_addr, sa.pointee.sa_family == UInt8(AF_LINK) else { continue }
            let name = String(cString: current.pointee.ifa_name)
            // Loopback and Apple Wireless Direct traffic aren't interesting here.
            guard !name.hasPrefix("lo"), !name.hasPrefix("awdl"), !name.hasPrefix("llw") else { continue }
            guard let data = current.pointee.ifa_data?.assumingMemoryBound(to: if_data.self) else { continue }
            inBytes &+= UInt64(data.pointee.ifi_ibytes)
            outBytes &+= UInt64(data.pointee.ifi_obytes)
        }

        let now = Date()
        defer { previousNetwork = (inBytes, outBytes, now) }
        guard let previous = previousNetwork else {
            return NetworkSample(downBytesPerSecond: 0, upBytesPerSecond: 0, totalIn: inBytes, totalOut: outBytes)
        }
        let elapsed = max(0.2, now.timeIntervalSince(previous.at))
        let down = Double(inBytes &- previous.inBytes) / elapsed
        let up = Double(outBytes &- previous.outBytes) / elapsed
        return NetworkSample(downBytesPerSecond: max(0, down), upBytesPerSecond: max(0, up),
                             totalIn: inBytes, totalOut: outBytes)
    }

    private static func readBattery() -> BatterySample {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else {
            return BatterySample()
        }
        for source in list {
            guard let description = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  let type = description[kIOPSTypeKey] as? String, type == kIOPSInternalBatteryType else { continue }

            let current = description[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = description[kIOPSMaxCapacityKey] as? Int ?? 100
            let state = description[kIOPSPowerSourceStateKey] as? String
            let charging = description[kIOPSIsChargingKey] as? Bool ?? false
            var remaining: Int?
            if charging, let value = description[kIOPSTimeToFullChargeKey] as? Int, value > 0 { remaining = value }
            if !charging, let value = description[kIOPSTimeToEmptyKey] as? Int, value > 0 { remaining = value }

            return BatterySample(isPresent: true,
                                 percentage: max > 0 ? Double(current) / Double(max) : 0,
                                 isCharging: charging,
                                 isPluggedIn: state == kIOPSACPowerValue,
                                 minutesRemaining: remaining,
                                 health: description[kIOPSBatteryHealthKey] as? String,
                                 cycleCount: description["Cycle Count"] as? Int)
        }
        return BatterySample()
    }

    private static func systemUptime() -> TimeInterval {
        var boot = timeval()
        var size = MemoryLayout<timeval>.stride
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        guard sysctl(&mib, 2, &boot, &size, nil, 0) == 0, boot.tv_sec != 0 else { return 0 }
        return Date().timeIntervalSince1970 - Double(boot.tv_sec)
    }

    /// `ps` is cheap enough at this cadence and avoids the entitlement dance that
    /// enumerating other processes' task ports would require.
    private func refreshProcesses() {
        guard processTask == nil else { return }
        processTask = Task { [weak self] in
            let rows = await Self.runProcessSnapshot()
            await MainActor.run {
                guard let self else { return }
                self.topProcesses = rows
                self.processTask = nil
            }
        }
    }

    private static func runProcessSnapshot() async -> [ProcessSample] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/ps")
                process.arguments = ["-Aceo", "pid,pcpu,rss,comm", "-r"]
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = FileHandle.nullDevice
                do { try process.run() } catch { return continuation.resume(returning: []) }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                let text = String(decoding: data, as: UTF8.self)
                var rows: [ProcessSample] = []
                for line in text.split(separator: "\n").dropFirst() {
                    let fields = line.split(separator: " ", omittingEmptySubsequences: true)
                    guard fields.count >= 4,
                          let pid = Int32(fields[0]),
                          let cpu = Double(fields[1]),
                          let rss = UInt64(fields[2]) else { continue }
                    let name = fields[3...].joined(separator: " ")
                    rows.append(ProcessSample(id: pid, name: name, cpu: cpu / 100, memory: rss * 1024))
                    if rows.count == 5 { break }
                }
                continuation.resume(returning: rows)
            }
        }
    }
}
