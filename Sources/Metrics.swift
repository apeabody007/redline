import CoreGraphics
import Foundation
import IOKit

/// One sample of machine vitals. Any field may be nil if this Mac
/// does not expose that counter, which is how the app stays portable
/// across chip generations.
struct Sample {
    /// The headline number: the fastest tier's utilization when the chip
    /// reports tiers, otherwise the aggregate. On an 18-core M5 Pro, six
    /// saturated top-tier cores are only 33% of the aggregate, so the old
    /// average read "calm" while the machine was at its performance ceiling.
    var cpu: Double = 0          // 0...1
    var cpuAggregate: Double = 0 // 0...1, every core weighted equally
    var cpuTiers: [TierUsage] = []
    var gpu: Double?             // 0...1
    var ram: Double = 0          // 0...1
    var ramUsedGB: Double = 0
    var tempC: Double?
    var thermal: ProcessInfo.ThermalState = .nominal
    var memoryPressure: MemoryPressure = .normal
}

struct TierUsage {
    let name: String
    let usage: Double   // 0...1
    let cores: Int
}

/// Splits the flat `host_processor_info` array into the chip's core tiers.
///
/// Cores are laid out slowest tier first, fastest last: on an M2 that is four
/// efficiency cores then four performance, and on an M5 Pro twelve then six.
/// `hw.perflevel0` is always the fastest tier, so its block sits at the END of
/// the array. Returns nil if the counts do not add up to the core count, in
/// which case the caller falls back to a single aggregate number rather than
/// reporting a split it cannot justify.
func tierRanges(coreCounts: [Int], totalCores: Int) -> [Range<Int>]? {
    guard !coreCounts.isEmpty, coreCounts.allSatisfy({ $0 > 0 }),
          coreCounts.reduce(0, +) == totalCores else { return nil }

    var ranges = [Range<Int>](repeating: 0..<0, count: coreCounts.count)
    var start = 0
    for level in stride(from: coreCounts.count - 1, through: 0, by: -1) {
        ranges[level] = start..<(start + coreCounts[level])
        start += coreCounts[level]
    }
    return ranges
}

/// One tier of cores, named by the kernel rather than by convention.
///
/// The M-series used to be Performance plus Efficiency. This M5 Pro reports
/// "Super" and "Performance" and has no efficiency level at all, so the names
/// are read from `hw.perflevelN.name` and never assumed. Same reasoning as the
/// temperature sensors: discover what the chip says, do not hardcode a
/// generation.
struct CoreTier {
    let name: String
    let range: Range<Int>
    var count: Int { range.count }
}

enum CoreTopology {
    /// Fastest tier first. Empty when the machine does not report perf levels,
    /// such as on Intel.
    static let tiers: [CoreTier] = {
        guard let levels = sysctlInt("hw.nperflevels"), levels > 1,
              let total = sysctlInt("hw.logicalcpu") else { return [] }
        let counts = (0..<levels).map { sysctlInt("hw.perflevel\($0).logicalcpu") ?? 0 }
        guard let ranges = tierRanges(coreCounts: counts, totalCores: total) else { return [] }
        return (0..<levels).map {
            CoreTier(name: sysctlString("hw.perflevel\($0).name") ?? "Tier \($0)",
                     range: ranges[$0])
        }
    }()
}

func sysctlInt(_ name: String) -> Int? {
    var value = 0
    var size = MemoryLayout<Int>.size
    guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
    return value
}

func sysctlString(_ name: String) -> String? {
    var size = 0
    guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
    var buffer = [CChar](repeating: 0, count: size)
    guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
    return String(cString: buffer)
}

/// Slides `frame` horizontally until it sits inside `bounds`.
///
/// Vertical position is deliberately left alone. Parking the pill up in the
/// menu bar or down over the Dock are both places you might genuinely want it,
/// and it draws above them, so it stays readable. Only the side edges actually
/// cut readings off. If `bounds` is narrower than the frame it pins to the left
/// edge, which keeps the result deterministic.
func clampedHorizontally(_ frame: CGRect, into bounds: CGRect) -> CGRect {
    let rightmost: CGFloat = max(bounds.maxX - frame.size.width, bounds.minX)
    let x: CGFloat = min(max(frame.origin.x, bounds.minX), rightmost)
    return CGRect(origin: CGPoint(x: x, y: frame.origin.y), size: frame.size)
}

/// macOS's own verdict on memory, which is a different question from how much
/// is in use. A Mac deliberately fills RAM with caches and compressed pages, so
/// a high percentage on its own says nothing. This says whether it hurts.
enum MemoryPressure: Int {
    case normal = 1
    case warning = 2
    case critical = 4

    private static let key = "kern.memorystatus_vm_pressure_level"

    /// Anything unrecognized reads as normal. Inventing alarm from a value we
    /// do not understand would be worse than staying quiet.
    static func from(_ raw: Int32) -> MemoryPressure {
        MemoryPressure(rawValue: Int(raw)) ?? .normal
    }

    static var current: MemoryPressure {
        var level: Int32 = 1
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(key, &level, &size, nil, 0) == 0 else { return .normal }
        return from(level)
    }

    var label: String {
        switch self {
        case .normal:   return "normal"
        case .warning:  return "warning"
        case .critical: return "critical"
        }
    }
}

enum Appearance: String, CaseIterable {
    case auto, light, dark

    static let key = "appearance"
    static let severityKey = "severityColors"

    var title: String { rawValue.capitalized }

    static var current: Appearance {
        UserDefaults.standard.string(forKey: key).flatMap(Appearance.init) ?? .auto
    }
}

enum Temp {
    static let key = "fahrenheit"

    /// Sensors report Celsius. Fahrenheit is the default because that is what
    /// this was built for; the menu switches it in one click.
    static let defaultsToFahrenheit = true
    static var preference: Bool { UserDefaults.standard.bool(forKey: key) }

    /// Right-aligned in a fixed column so 99°F and 100°F are the same width.
    static func string(_ celsius: Double, fahrenheit: Bool, decimals: Int = 0) -> String {
        let value = fahrenheit ? celsius * 9 / 5 + 32 : celsius
        let width = decimals > 0 ? decimals + 4 : 3
        return String(format: "%\(width).\(decimals)f°\(fahrenheit ? "F" : "C")", value)
    }
}

extension ProcessInfo.ThermalState {
    var label: String {
        switch self {
        case .nominal:  return "nominal"
        case .fair:     return "fair"
        case .serious:  return "serious (throttling)"
        case .critical: return "critical (throttling hard)"
        @unknown default: return "unknown"
        }
    }
}

/// Appends to a fixed-length window of readings, dropping the oldest once it is
/// full. A free function rather than a method on the sampler so the rule can be
/// tested on its own, the way `clampedHorizontally` is.
func appending<T>(_ value: T, to window: [T], limit: Int) -> [T] {
    guard limit > 0 else { return [] }
    var next = window
    next.append(value)
    if next.count > limit { next.removeFirst(next.count - limit) }
    return next
}

final class Sampler: ObservableObject {
    @Published private(set) var sample = Sample()

    /// The recent past, oldest first, so hovering the menu bar icon can show
    /// where a reading has been and not only where it is.
    @Published private(set) var history: [Sample] = []

    /// Ticks are a second apart, so this is the last three minutes.
    static let historyLimit = 180

    private var timer: Timer?
    private var prevCores: [(used: Double, total: Double)]?
    private let sensors = TemperatureSensors()

    func start(interval: TimeInterval = 1.0) {
        tick()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        var s = Sample()
        let cpu = readCPU()
        s.cpuAggregate = cpu.aggregate
        s.cpuTiers = cpu.tiers
        // The fastest tier is the headline, because that is the one that decides
        // whether the machine feels slow. Without tier data this is the average.
        s.cpu = cpu.tiers.first?.usage ?? cpu.aggregate
        s.gpu = readGPU()
        let mem = readMemory()
        s.ram = mem.fraction
        s.ramUsedGB = mem.usedGB
        s.tempC = sensors.peakDieTemperature()
        s.thermal = ProcessInfo.processInfo.thermalState
        s.memoryPressure = MemoryPressure.current
        sample = s
        history = appending(s, to: history, limit: Self.historyLimit)
    }

    // MARK: - CPU

    private func readCPU() -> (aggregate: Double, tiers: [TierUsage]) {
        var count: natural_t = 0
        var infoCount: mach_msg_type_number_t = 0
        var info: processor_info_array_t?

        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO,
                                  &count, &info, &infoCount) == KERN_SUCCESS,
              let info else { return (sample.cpuAggregate, sample.cpuTiers) }

        defer {
            vm_deallocate(mach_task_self_,
                          vm_address_t(UInt(bitPattern: info)),
                          vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride))
        }

        var perCore: [(used: Double, total: Double)] = []
        perCore.reserveCapacity(Int(count))
        for core in 0..<Int(count) {
            let base = core * Int(CPU_STATE_MAX)
            let user = Double(info[base + Int(CPU_STATE_USER)])
            let system = Double(info[base + Int(CPU_STATE_SYSTEM)])
            let nice = Double(info[base + Int(CPU_STATE_NICE)])
            let idle = Double(info[base + Int(CPU_STATE_IDLE)])
            perCore.append((user + system + nice, user + system + nice + idle))
        }

        defer { prevCores = perCore }
        guard let previous = prevCores, previous.count == perCore.count else {
            return (aggregate: 0, tiers: [])
        }

        /// Busy fraction over a set of cores between the last tick and this one.
        func busy(_ range: Range<Int>) -> Double? {
            var used = 0.0, total = 0.0
            for core in range where core < perCore.count {
                used += perCore[core].used - previous[core].used
                total += perCore[core].total - previous[core].total
            }
            guard total > 0 else { return nil }
            return min(max(used / total, 0), 1)
        }

        let aggregate = busy(0..<perCore.count) ?? sample.cpuAggregate
        let tiers = CoreTopology.tiers.compactMap { tier -> TierUsage? in
            guard let usage = busy(tier.range) else { return nil }
            return TierUsage(name: tier.name, usage: usage, cores: tier.count)
        }
        return (aggregate, tiers)
    }

    // MARK: - Memory

    private func readMemory() -> (fraction: Double, usedGB: Double) {
        var stats = vm_statistics64()
        var size = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &size)
            }
        }
        guard result == KERN_SUCCESS else { return (0, 0) }

        let page = Double(vm_kernel_page_size)
        // Matches Activity Monitor's "Memory Used": app memory + wired + compressed.
        let used = (Double(stats.active_count)
                    + Double(stats.wire_count)
                    + Double(stats.compressor_page_count)) * page
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        guard total > 0 else { return (0, 0) }
        return (min(used / total, 1), used / 1_073_741_824)
    }

    // MARK: - GPU

    /// Reads "Device Utilization %" out of the accelerator's performance
    /// statistics. Present on Intel and every Apple Silicon generation so far;
    /// returns nil rather than guessing if a future chip drops the key.
    private func readGPU() -> Double? {
        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceMatching("IOAccelerator"),
                                           &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        var best: Double?
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let stats = IORegistryEntryCreateCFProperty(
                    service, "PerformanceStatistics" as CFString,
                    kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any] else { continue }

            let value = (stats["Device Utilization %"] as? NSNumber)
                ?? (stats["Renderer Utilization %"] as? NSNumber)
            if let value {
                let pct = value.doubleValue > 1.5 ? value.doubleValue / 100 : value.doubleValue
                best = max(best ?? 0, min(pct, 1))
            }
        }
        return best
    }
}
