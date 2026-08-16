import SwiftUI

struct HUDView: View {
    @ObservedObject var sampler: Sampler

    private var vitals: Sample { sampler.sample }

    var body: some View {
        HStack(spacing: 14) {
            readout("CPU", percent: vitals.cpu)
            if let gpu = vitals.gpu {
                readout("GPU", percent: gpu)
            }
            readout("RAM", percent: vitals.ram)
            if let temp = vitals.tempC {
                Text("\(Int(temp.rounded()))°C")
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

    private func readout(_ label: String, percent: Double) -> some View {
        HStack(spacing: 5) {
            Text(label).foregroundStyle(.secondary)
            Text("\(Int((percent * 100).rounded()))%")
        }
    }

    private var thermalColor: Color {
        switch vitals.thermal {
        case .nominal:  return .primary.opacity(0.85)
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
