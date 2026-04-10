import SwiftUI

/// Signal / Noise / Load meters with thin animated progress bars.
struct MetersView: View {
    let signalStrength: Double
    let noiseLevel: Double
    let cpuLoad: Double
    let state: RadioState

    var body: some View {
        VStack(spacing: 6) {
            MeterRow(label: "SIGNAL", value: signalStrength, color: state.color)
            MeterRow(label: "NOISE", value: noiseLevel, color: .white.opacity(0.5))
            MeterRow(label: "LOAD", value: cpuLoad, color: cpuLoad > 0.7 ? .red : .radioOrange)
        }
    }
}

struct MeterRow: View {
    let label: String
    let value: Double
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.radioLabel)
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.08))
                        .frame(height: 3)

                    Capsule()
                        .fill(color)
                        .frame(width: max(0, geo.size.width * value), height: 3)
                        .animation(.linear(duration: 0.15), value: value)
                }
            }
            .frame(height: 3)

            Text(String(format: "%.0f%%", value * 100))
                .font(.radioCaption)
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .trailing)
                .monospacedDigit()
        }
    }
}
