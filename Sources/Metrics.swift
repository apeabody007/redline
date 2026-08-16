import Foundation
import IOKit

/// One sample of machine vitals. Any field may be nil if this Mac
/// does not expose that counter, which is how the app stays portable
/// across chip generations.
struct Sample {
    var cpu: Double = 0          // 0...1
    var gpu: Double?             // 0...1
    var ram: Double = 0          // 0...1
    var ramUsedGB: Double = 0
    var tempC: Double?
    var thermal: ProcessInfo.ThermalState = .nominal
}

enum Temp {
    static let key = "fahrenheit"

    /// Sensors report Celsius. Which one a person wants to read is a locale
    /// question, so default to the region's system and let the menu override.
    static var systemDefault: Bool { Locale.current.measurementSystem == .us }
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

final class Sampler: ObservableObject {
    @Published private(set) var sample = Sample()

    private var timer: Timer?
    private var prevTicks: (used: Double, total: Double)?
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
        s.cpu = readCPU()
        s.gpu = readGPU()
        let mem = readMemory()
        s.ram = mem.fraction
        s.ramUsedGB = mem.usedGB
        s.tempC = sensors.peakDieTemperature()
        s.thermal = ProcessInfo.processInfo.thermalState
        sample = s
    }

    // MARK: - CPU

    private func readCPU() -> Double {
        var count: natural_t = 0
        var infoCount: mach_msg_type_number_t = 0
        var info: processor_info_array_t?

        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO,
                                  &count, &info, &infoCount) == KERN_SUCCESS,
              let info else { return prevTicks == nil ? 0 : sample.cpu }

        defer {
            vm_deallocate(mach_task_self_,
                          vm_address_t(UInt(bitPattern: info)),
                          vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride))
        }

        var used = 0.0, total = 0.0
        for core in 0..<Int(count) {
            let base = core * Int(CPU_STATE_MAX)
            let user = Double(info[base + Int(CPU_STATE_USER)])
            let system = Double(info[base + Int(CPU_STATE_SYSTEM)])
            let nice = Double(info[base + Int(CPU_STATE_NICE)])
            let idle = Double(info[base + Int(CPU_STATE_IDLE)])
            used += user + system + nice
            total += user + system + nice + idle
        }

        defer { prevTicks = (used, total) }
        guard let prev = prevTicks else { return 0 }
        let dTotal = total - prev.total
        guard dTotal > 0 else { return sample.cpu }
        return min(max((used - prev.used) / dTotal, 0), 1)
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
