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

        // A tracking area only fires when the pointer crosses its edge. If the
        // pointer is already inside when the area is installed, which is what
        // happens when the app launches under the cursor, hover would stay dead
        // until you moved away and came back.
        if let window {
            let local = convert(window.mouseLocationOutsideOfEventStream, from: nil)
            report(bounds.contains(local))
        }
    }

    override func mouseEntered(with event: NSEvent) { report(true) }
    override func mouseExited(with event: NSEvent) { report(false) }

    private var isInside = false

    private func report(_ inside: Bool) {
        guard inside != isInside else { return }
        isInside = inside
        onHover?(inside)
    }
}

/// The panel that appears on hover. One panel for the whole pill rather than a
/// tooltip per number: the readings are 30pt wide, and asking someone to aim at
/// "71%" to learn what it means is worse than showing everything at once.
///
/// It is pinned to the pill's exact width so the two read as one object rather
/// than as a box that happened to open near another box.
struct DetailView: View {
    @ObservedObject var sampler: Sampler
    let width: CGFloat

    @AppStorage(Temp.key) private var fahrenheit = Temp.defaultsToFahrenheit

    private var vitals: Sample { sampler.sample }

    /// Wide enough for "Thermal", the longest label. Every row shares it so
    /// the left edge lines up, and a Spacer is deliberately not used: it
    /// competes with the text for width and squeezes it into wrapping.
    private static let labelWidth: CGFloat = 50

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            row("CPU", percent(vitals.cpu),
                "\(ProcessInfo.processInfo.processorCount) cores")
            if let gpu = vitals.gpu {
                row("GPU", percent(gpu), "graphics")
            }
            row("RAM", percent(vitals.ram), memoryDetail)
            if let temp = vitals.tempC {
                row("Temp",
                    Temp.string(temp, fahrenheit: fahrenheit)
                        .trimmingCharacters(in: .whitespaces),
                    "hottest die")
            }

            Divider().opacity(0.28).padding(.vertical, 1)

            verdict("Memory", memoryVerdict, tint: pressureTint)
            verdict("Thermal", thermalVerdict, tint: thermalTint)
        }
        .font(.system(size: 11, weight: .medium, design: .monospaced))
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(width: width, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(.white.opacity(0.10), lineWidth: 1))
        )
    }

    /// Columns line up with the pill above: label, then the number, then what
    /// the number is made of.
    private func row(_ label: String, _ value: String, _ note: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: Self.labelWidth, alignment: .leading)
            Text(value)
                .frame(width: 46, alignment: .trailing)
                .monospacedDigit()
            Text(note)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The two lines that actually answer "is this bad", given the full width
    /// so they never have to be abbreviated.
    private func verdict(_ label: String, _ text: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: Self.labelWidth, alignment: .leading)
            Text(text)
                .foregroundStyle(tint)
                .lineLimit(1)
                // "serious, chip is down-clocking" is the longest of these and
                // only appears under sustained load, so it shrinks slightly
                // rather than risking a truncated verdict nobody can read.
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 10, weight: .medium, design: .monospaced))
    }

    private func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    private var memoryDetail: String {
        let total = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
        return String(format: "%.2f of %.0f GB", vitals.ramUsedGB, total)
    }

    /// The reason this panel exists. A percentage cannot tell you whether a Mac
    /// is in trouble, because macOS deliberately fills RAM. This can.
    private var memoryVerdict: String {
        switch vitals.memoryPressure {
        case .normal:   return "pressure normal, healthy"
        case .warning:  return "pressure warning, straining"
        case .critical: return "pressure critical, thrashing"
        }
    }

    private var thermalVerdict: String {
        switch vitals.thermal {
        case .nominal:  return "nominal, full speed"
        case .fair:     return "fair, warm but not slowed"
        case .serious:  return "serious, chip is down-clocking"
        case .critical: return "critical, heavily throttled"
        @unknown default: return "unknown"
        }
    }

    private var pressureTint: Color {
        switch vitals.memoryPressure {
        case .normal:   return .primary.opacity(0.75)
        case .warning:  return .orange
        case .critical: return .red
        }
    }

    private var thermalTint: Color {
        switch vitals.thermal {
        case .nominal:  return .primary.opacity(0.75)
        case .fair:     return .yellow
        case .serious:  return .orange
        case .critical: return .red
        @unknown default: return .primary
        }
    }
}
