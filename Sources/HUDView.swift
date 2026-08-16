import SwiftUI

struct HUDView: View {
    @ObservedObject var sampler: Sampler
    @AppStorage(Temp.key) private var fahrenheit = Temp.defaultsToFahrenheit
    @AppStorage(Appearance.severityKey) private var severityColors = true

    private var vitals: Sample { sampler.sample }

    var body: some View {
        HStack(spacing: 14) {
            // Memory turns amber earlier than the processors: a Mac at 80% CPU
            // is working, a Mac at 80% memory is about to start swapping.
            readout("CPU", percent: vitals.cpu, warm: 0.70, hot: 0.90)
            if let gpu = vitals.gpu {
                readout("GPU", percent: gpu, warm: 0.70, hot: 0.90)
            }
            readout("RAM", percent: vitals.ram, warm: 0.75, hot: 0.90)
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
    private func readout(_ label: String, percent: Double,
                         warm: Double, hot: Double) -> some View {
        HStack(spacing: 5) {
            Text(label).foregroundStyle(.secondary)
            Text(String(format: "%3d%%", Int((percent * 100).rounded())))
                .foregroundStyle(tint(percent, warm: warm, hot: hot))
        }
    }

    /// Values warm as they climb so the pill reads at a glance, without
    /// anyone having to actually parse the digits.
    private func tint(_ fraction: Double, warm: Double, hot: Double) -> Color {
        guard severityColors else { return resting }
        if fraction >= hot { return .red }
        if fraction >= warm { return .orange }
        return resting
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
