import AppKit
import SwiftUI

/// Reports hover in and out of the pill.
///
/// AppKit's own tooltips, and SwiftUI's `.help`, never fire for this window.
/// They need the owning app to be active, and Redline is an accessory app whose
/// panel is non-activating and never becomes key. Verified by parking the
/// cursor inside the pill and watching for a tooltip window that never
/// appeared. `.activeAlways` is the part that matters below: without it the
/// tracking area only fires while Redline is the frontmost app, which it never
/// is.
final class HoverView: NSView {
    var onHover: ((Bool) -> Void)?
    private var tracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
}

/// The panel that appears on hover. One panel for the whole pill rather than a
/// tooltip per number: the readings are 30pt wide, and asking someone to aim at
/// "71%" to learn what it means is worse than showing everything at once.
struct DetailView: View {
    @ObservedObject var sampler: Sampler
    @AppStorage(Temp.key) private var fahrenheit = Temp.defaultsToFahrenheit

    private var vitals: Sample { sampler.sample }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            row("CPU", percent(vitals.cpu),
                "across \(ProcessInfo.processInfo.processorCount) cores")
            if let gpu = vitals.gpu {
                row("GPU", percent(gpu), "graphics utilization")
            }
            row("RAM", percent(vitals.ram), memoryNote)
            if let temp = vitals.tempC {
                row("Temp", Temp.string(temp, fahrenheit: fahrenheit).trimmingCharacters(in: .whitespaces),
                    "hottest die sensor")
            }

            Divider().opacity(0.3)

            HStack(spacing: 6) {
                Text("Thermal").foregroundStyle(.secondary)
                Text(thermalNote)
            }
            .font(.system(size: 11))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(.white.opacity(0.10), lineWidth: 1))
        )
        .fixedSize()
    }

    private func row(_ label: String, _ value: String, _ note: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 38, alignment: .leading)
            Text(value)
                .frame(width: 52, alignment: .trailing)
                .monospacedDigit()
            Text(note)
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 11, weight: .medium, design: .monospaced))
    }

    private func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    /// The reason this panel exists. A percentage cannot tell you whether a Mac
    /// is in trouble, because macOS deliberately fills RAM. This can.
    private var memoryNote: String {
        let total = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
        let verdict: String
        switch vitals.memoryPressure {
        case .normal:   verdict = "pressure normal"
        case .warning:  verdict = "pressure WARNING"
        case .critical: verdict = "pressure CRITICAL"
        }
        return String(format: "%.2f of %.0f GB used, %@", vitals.ramUsedGB, total, verdict)
    }

    private var thermalNote: String {
        switch vitals.thermal {
        case .nominal:  return "nominal, running at full speed"
        case .fair:     return "fair, warming up but not slowed"
        case .serious:  return "serious, the chip is down-clocking"
        case .critical: return "critical, heavily throttled"
        @unknown default: return "unknown"
        }
    }
}
