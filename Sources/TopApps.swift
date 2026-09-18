import Darwin
import Foundation

/// One app's share of memory, with all of its helper processes added in.
struct AppMemory: Equatable {
    let name: String
    let bytes: UInt64
}

/// The app a process belongs to, read from its executable path: the OUTERMOST
/// `.app` bundle on the way down. Chrome's renderers live at
/// `Google Chrome.app/.../Google Chrome Helper (Renderer).app/...`, and taking
/// the innermost bundle would list Chrome a dozen times as helpers nobody
/// recognizes. A process outside any bundle goes by its executable name.
func appName(forExecutable path: String) -> String {
    let parts = path.split(separator: "/")
    if let bundle = parts.first(where: { $0.hasSuffix(".app") }) {
        return String(bundle.dropLast(4))
    }
    return parts.last.map(String.init) ?? path
}

/// Adds processes up by app and keeps the biggest, largest first. Ties go
/// alphabetically so the list does not shuffle between two equal apps.
func topApps(_ processes: [(path: String, bytes: UInt64)], limit: Int) -> [AppMemory] {
    var totals: [String: UInt64] = [:]
    for process in processes {
        totals[appName(forExecutable: process.path), default: 0] += process.bytes
    }
    return totals
        .map { AppMemory(name: $0.key, bytes: $0.value) }
        .sorted { $0.bytes != $1.bytes ? $0.bytes > $1.bytes : $0.name < $1.name }
        .prefix(max(limit, 0))
        .map { $0 }
}

/// Short enough for the panels' number column: "6.1 GB", "850 MB".
func memoryString(_ bytes: UInt64) -> String {
    let mb = Double(bytes) / 1_048_576
    if mb >= 1024 { return String(format: "%.1f GB", mb / 1024) }
    return "\(Int(mb.rounded())) MB"
}

/// Which apps are holding the memory. Walking every process costs far more
/// than the rest of Redline's sampling put together, so this only runs while a
/// hover panel is on screen.
final class TopAppsSampler: ObservableObject {
    @Published private(set) var apps: [AppMemory] = []

    static let limit = 3

    private var timer: Timer?

    /// Scans once straight away, so a panel sized as it opens already has its
    /// rows, then every two seconds until stopped.
    func start() {
        guard timer == nil else { return }
        scan()
        let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.scan() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func scan() {
        apps = topApps(Self.readProcesses(), limit: Self.limit)
    }

    /// Every process this user can read, measured by physical footprint, the
    /// same figure as Activity Monitor's Memory column. Processes owned by
    /// root or another user refuse `proc_pid_rusage` and are skipped.
    private static func readProcesses() -> [(path: String, bytes: UInt64)] {
        let capacity = Int(proc_listallpids(nil, 0)) + 64
        var pids = [pid_t](repeating: 0, count: capacity)
        let count = Int(proc_listallpids(&pids, Int32(capacity * MemoryLayout<pid_t>.size)))
        guard count > 0 else { return [] }

        var result: [(path: String, bytes: UInt64)] = []
        var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        for pid in pids.prefix(count) where pid > 0 {
            var info = rusage_info_v4()
            let status = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
                }
            }
            guard status == 0, info.ri_phys_footprint > 0 else { continue }
            guard proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count)) > 0 else { continue }
            result.append((String(cString: pathBuffer), info.ri_phys_footprint))
        }
        return result
    }
}
