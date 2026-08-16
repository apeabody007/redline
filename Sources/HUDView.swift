import SwiftUI

struct HUDView: View {
    @ObservedObject var sampler: Sampler
    @AppStorage(Temp.key) private var fahrenheit = Temp.defaultsToFahrenheit
    @AppStorage(Appearance.severityKey) private var severityColors = true

    private var vitals: Sample { sampler.sample }

    var body: some View {
        HStack(spacing: 14) {
            readout("CPU", percent: vitals.cpu, tint: usageTint(vitals.cpu))
            if let gpu = vitals.gpu {
                readout("GPU", percent: gpu, tint: usageTint(gpu))
            }
            // Memory is tinted by macOS's pressure verdict rather than by the
            // percentage. A Mac deliberately fills RAM, so 71% used might be
            // perfectly healthy or might be thrashing, and only the OS knows.
            readout("RAM", percent: vitals.ram, tint: pressureTint)
            if let temp = vitals.tempC {
                Text(Temp.string(temp, fahrenheit: fahrenheit))
                    .foregroundStyle(thermalColor)
            }
            if vitals.thermal != .nominal {
                Text(throttleLabel)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(thermalColor.opacity(0.22)))
                    .foregroundStyle(thermalColor)
            }
        }
        .font(.system(size: 12, weight: .medium, design: .monospaced))
        .monospacedDigit()
        .foregroundStyle(.primary.opacity(0.85))
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(
            Capsule().fill(.ultraThinMaterial)
                .overlay(Capsule().strokeBorder(.white.opacity(0.10), lineWidth: 1))
        )
        .fixedSize()
    }

    /// Padded to three columns. The font is monospaced, so 3% and 100% occupy
    /// the same width and the pill never resizes as the numbers move.
    private func readout(_ label: String, percent: Double, tint: Color) -> some View {
        HStack(spacing: 5) {
            Text(label).foregroundStyle(.secondary)
            Text(String(format: "%3d%%", Int((percent * 100).rounded())))
                .foregroundStyle(tint)
        }
    }

    /// Processors warm as they climb, so the pill reads at a glance without
    /// anyone having to actually parse the digits.
    private func usageTint(_ fraction: Double) -> Color {
        guard severityColors else { return resting }
        if fraction >= 0.90 { return .red }
        if fraction >= 0.70 { return .orange }
        return resting
    }

    private var pressureTint: Color {
        guard severityColors else { return resting }
        switch vitals.memoryPressure {
        case .normal:   return resting
        case .warning:  return .orange
        case .critical: return .red
        }
    }

    private var resting: Color { .primary.opacity(0.85) }

    /// Temperature always tracks thermal pressure rather than the severity
    /// toggle. It is the reading the app exists for, so it is never muted.
    private var thermalColor: Color {
        switch vitals.thermal {
        case .nominal:  return resting
        case .fair:     return .yellow
        case .serious:  return .orange
        case .critical: return .red
        @unknown default: return .primary
        }
    }

    private var throttleLabel: String {
        vitals.thermal == .fair ? "WARM" : "THROTTLE"
    }
}
