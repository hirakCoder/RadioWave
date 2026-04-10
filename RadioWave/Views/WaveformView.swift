import SwiftUI

/// Animated sine-wave visualization driven by the current radio state.
struct WaveformView: View {
    let state: RadioState

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let midY = size.height / 2
                let width = size.width
                let time = timeline.date.timeIntervalSinceReferenceDate

                var path = Path()
                path.move(to: CGPoint(x: 0, y: midY))

                for x in stride(from: 0, through: width, by: 1) {
                    let y = calculateY(x: x, midY: midY, time: time, width: width)
                    path.addLine(to: CGPoint(x: x, y: y))
                }

                context.stroke(
                    path,
                    with: .color(state.color),
                    lineWidth: lineWidth
                )

                // Draw a subtle glow line behind
                context.stroke(
                    path,
                    with: .color(state.color.opacity(0.3)),
                    lineWidth: lineWidth + 3
                )
            }
        }
        .frame(height: 48)
    }

    private var lineWidth: CGFloat {
        switch state {
        case .idle: return 0.8
        case .connected: return 1.0
        case .thinking: return 1.2
        case .toolUse: return 1.5
        case .generating: return 1.5
        case .error: return 1.0
        }
    }

    private func calculateY(x: CGFloat, midY: CGFloat, time: Double, width: CGFloat) -> CGFloat {
        let phase = time * phaseSpeed
        let noise = CGFloat.random(in: -1...1) * noiseAmount

        switch state {
        case .idle:
            return midY + noise * 2

        case .connected:
            let wave = sin(Double(x) * 0.03 + phase) * 8
            return midY + wave + noise * 4

        case .thinking:
            let wave1 = sin(Double(x) * 0.04 + phase) * 18
            let wave2 = sin(Double(x) * 0.015 + phase * 0.3) * 8
            return midY + wave1 + wave2 + noise * 5

        case .toolUse:
            // Staccato/digital feel
            let wave = sin(Double(x) * 0.1 + phase) * 14
            let square = sin(Double(x) * 0.06 + phase * 0.7) > 0 ? 10.0 : -10.0
            return midY + wave + square + noise * 3

        case .generating:
            let wave1 = sin(Double(x) * 0.06 + phase) * 26
            let wave2 = sin(Double(x) * 0.12 + phase * 0.5) * 10
            return midY + wave1 + wave2 + noise * 3

        case .error:
            // Decaying signal
            let decay = max(0, 1.0 - Double(x) / Double(width))
            let wave = sin(Double(x) * 0.05 + phase) * 20 * decay
            return midY + wave + noise * 8 * decay
        }
    }

    private var phaseSpeed: Double {
        switch state {
        case .idle: return 0.5
        case .connected: return 1.5
        case .thinking: return 3.0
        case .toolUse: return 6.0
        case .generating: return 5.0
        case .error: return 0.3
        }
    }

    private var noiseAmount: CGFloat {
        switch state {
        case .idle: return 1.0
        case .connected: return 2.0
        case .thinking: return 3.0
        case .toolUse: return 2.0
        case .generating: return 1.5
        case .error: return 6.0
        }
    }
}
