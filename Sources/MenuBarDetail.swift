import SwiftUI

/// One reading drawn over time. Deliberately unlabelled and without axes: the
/// question it answers is "was it like this a minute ago", which is a shape,
/// not a number, and the number is already sitting next to it.
struct Sparkline: Shape {
    /// Oldest first, each 0...1. Values outside that are clamped rather than
    /// rescaled, so one spike reads as a spike instead of quietly flattening
    /// everything around it.
    let values: [Double]

    /// Carries the line down to the baseline and closes it, so the same shape
    /// can be filled underneath as well as stroked.
    var closed = false

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard values.count > 1 else { return path }

        let step = rect.width / CGFloat(values.count - 1)
        func point(_ index: Int) -> CGPoint {
            let clamped = min(max(values[index], 0), 1)
            return CGPoint(x: rect.minX + CGFloat(index) * step,
                           y: rect.maxY - clamped * rect.height)
        }

        path.move(to: point(0))
        for index in 1..<values.count { path.addLine(to: point(index)) }

        if closed {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
        return path
    }
}

/// The panel that appears when the pointer rests on the menu bar icon.
///
/// It is not the pill's detail panel relocated. That one explains the numbers
/// you are looking at; this one shows the last few minutes, which is the one
/// thing the pill cannot tell you no matter how long you stare at it.
struct MenuBarDetailView: View {
    @ObservedObject var sampler: Sampler

    @AppStorage(Temp.key) private var fahrenheit = Temp.defaultsToFahrenheit

    static let width: CGFloat = 236

    private var vitals: Sample { sampler.sample }
    private var history: [Sample] { sampler.history }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            trace("CPU", values: history.map(\.cpu), value: percent(vitals.cpu))

            if vitals.gpu != nil {
                trace("GPU", values: history.map { $0.gpu ?? 0 },
                      value: percent(vitals.gpu ?? 0))
            }

            trace("RAM", values: history.map(\.ram), value: percent(vitals.ram))

            if let temp = vitals.tempC {
                // A die temperature has no natural ceiling the way a percentage
                // does, so the trace is scaled across the range a Mac actually
                // lives in: 30C is cold, 100C is in trouble.
                trace("Temp",
                      values: history.map { ($0.tempC.map { ($0 - 30) / 70 }) ?? 0 },
                      value: Temp.string(temp, fahrenheit: fahrenheit)
                          .trimmingCharacters(in: .whitespaces))
            }

            Text(span)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(.tertiary)
                .padding(.top, 1)
        }
        .font(.system(size: 11, weight: .medium, design: .monospaced))
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(width: Self.width, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(.white.opacity(0.10), lineWidth: 1))
        )
    }

    /// Label, trace, current value. The trace takes whatever width is left so
    /// every row starts and ends on the same two edges.
    private func trace(_ label: String, values: [Double], value: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .leading)

            ZStack {
                Sparkline(values: values, closed: true)
                    .fill(LinearGradient(colors: [.primary.opacity(0.20),
                                                  .primary.opacity(0.02)],
                                         startPoint: .top, endPoint: .bottom))
                Sparkline(values: values)
                    .stroke(.primary.opacity(0.75),
                            style: StrokeStyle(lineWidth: 1.2,
                                               lineCap: .round, lineJoin: .round))
            }
            .frame(height: 16)
            .frame(maxWidth: .infinity)

            Text(value)
                .frame(width: 44, alignment: .trailing)
                .monospacedDigit()
        }
    }

    /// How much time the traces actually cover, so a line that has only just
    /// started filling in after launch is not read as a flat three minutes.
    private var span: String {
        let seconds = max(history.count - 1, 0)
        guard seconds >= 60 else { return "last \(seconds)s" }
        return "last \(seconds / 60)m \(seconds % 60)s"
    }

    private func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }
}
