import AVFoundation

/// One-shot event sounds that play over the ambient state audio.
/// These are brief, satisfying tones for discrete events like
/// "response complete", "tool succeeded", "session connected".
final class EventChimes {
    private let sampleRate: Double
    private var phases: [Double] = Array(repeating: 0, count: 8)

    init(sampleRate: Double = 44100) {
        self.sampleRate = sampleRate
    }

    // MARK: - Success Chime

    /// Warm two-note ascending chime (like AirPods connect). ~0.4s
    /// Notes: C5 → E5 (major third = happy/resolved)
    func fillSuccessChime(buffer: AVAudioPCMBuffer, amplitude: Float) {
        guard let data = buffer.floatChannelData, buffer.format.channelCount >= 2 else { return }
        let frameCount = Int(buffer.frameLength)
        let note1End = Int(sampleRate * 0.18)   // first note: 180ms
        let note2Start = Int(sampleRate * 0.12) // overlap by 60ms
        let totalLength = Int(sampleRate * 0.4)

        for frame in 0..<frameCount {
            var sampleL: Float = 0
            var sampleR: Float = 0

            // Note 1: C5 (523.25 Hz) — decays
            if frame < note1End {
                let env = Float(pow(1.0 - Double(frame) / Double(note1End), 1.5))
                phases[0] += (2.0 * .pi * 523.25) / sampleRate
                phases[1] += (2.0 * .pi * 523.25 * 2.0) / sampleRate  // octave harmonic
                let tone = Float(sin(phases[0])) * 0.6 + Float(sin(phases[1])) * 0.15
                sampleL += tone * env * amplitude
                sampleR += tone * env * amplitude
            }

            // Note 2: E5 (659.25 Hz) — arrives slightly later, sustains longer
            if frame >= note2Start && frame < totalLength {
                let localFrame = frame - note2Start
                let attackEnd = Int(sampleRate * 0.015)
                let sustainEnd = Int(sampleRate * 0.12)
                let env: Float
                if localFrame < attackEnd {
                    env = Float(localFrame) / Float(attackEnd)
                } else if localFrame < sustainEnd {
                    env = 1.0
                } else {
                    env = Float(pow(max(0, 1.0 - Double(localFrame - sustainEnd) / Double(totalLength - note2Start - sustainEnd)), 2.0))
                }

                phases[2] += (2.0 * .pi * 659.25) / sampleRate
                phases[3] += (2.0 * .pi * 659.25 * 2.0) / sampleRate
                phases[4] += (2.0 * .pi * 659.25 * 3.98) / sampleRate  // bell inharmonic
                let tone = Float(sin(phases[2])) * 0.55
                         + Float(sin(phases[3])) * 0.12
                         + Float(sin(phases[4])) * 0.04
                // Slightly wider stereo on second note
                sampleL += tone * env * amplitude * 0.55
                sampleR += tone * env * amplitude * 0.45
            }

            // Fade to silence after total length
            if frame >= totalLength {
                sampleL = 0
                sampleR = 0
            }

            data[0][frame] = max(-1, min(1, (data[0][frame] + sampleL)))
            data[1][frame] = max(-1, min(1, (data[1][frame] + sampleR)))
        }
    }

    // MARK: - Tool Complete Chime

    /// Quick single "tick" confirmation — subtle and non-intrusive. ~0.1s
    /// A soft high ping, like a typewriter bell at the end of a line.
    func fillToolCompletePing(buffer: AVAudioPCMBuffer, amplitude: Float) {
        guard let data = buffer.floatChannelData, buffer.format.channelCount >= 2 else { return }
        let frameCount = Int(buffer.frameLength)
        let pingLength = Int(sampleRate * 0.1)

        for frame in 0..<frameCount {
            guard frame < pingLength else { break }

            let env = Float(pow(1.0 - Double(frame) / Double(pingLength), 2.5))

            // High bell: A6 (1760 Hz) with inharmonic overtone
            phases[0] += (2.0 * .pi * 1760.0) / sampleRate
            phases[1] += (2.0 * .pi * 1760.0 * 2.76) / sampleRate  // inharmonic = bell
            let tone = Float(sin(phases[0])) * 0.5 + Float(sin(phases[1])) * 0.08

            let sample = tone * env * amplitude * 0.5
            data[0][frame] = max(-1, min(1, data[0][frame] + sample * 0.5))
            data[1][frame] = max(-1, min(1, data[1][frame] + sample * 0.5))
        }
    }

    // MARK: - Session Connected

    /// Warm "tuned in" sound — a soft rising tone. ~0.3s
    /// Like locking onto a radio station.
    func fillSessionConnected(buffer: AVAudioPCMBuffer, amplitude: Float) {
        guard let data = buffer.floatChannelData, buffer.format.channelCount >= 2 else { return }
        let frameCount = Int(buffer.frameLength)
        let length = Int(sampleRate * 0.3)

        for frame in 0..<frameCount {
            guard frame < length else { break }
            let progress = Double(frame) / Double(length)

            // Rising pitch: 300 → 500 Hz
            let freq = 300.0 + progress * 200.0
            phases[0] += (2.0 * .pi * freq) / sampleRate
            phases[1] += (2.0 * .pi * freq * 1.5) / sampleRate  // fifth

            // Envelope: quick attack, hold, gentle fade
            let env: Float
            if progress < 0.05 {
                env = Float(progress / 0.05)
            } else if progress < 0.6 {
                env = 1.0
            } else {
                env = Float(1.0 - (progress - 0.6) / 0.4)
            }

            let tone = Float(sin(phases[0])) * 0.4 + Float(sin(phases[1])) * 0.15
            let sample = tone * env * amplitude * 0.4

            // Gentle stereo spread that widens as it rises
            let spread = Float(progress) * 0.15
            data[0][frame] = max(-1, min(1, data[0][frame] + sample * (0.5 + spread)))
            data[1][frame] = max(-1, min(1, data[1][frame] + sample * (0.5 - spread)))
        }
    }

    // MARK: - Session Disconnected

    /// Descending "signed off" tone. ~0.25s
    func fillSessionDisconnected(buffer: AVAudioPCMBuffer, amplitude: Float) {
        guard let data = buffer.floatChannelData, buffer.format.channelCount >= 2 else { return }
        let frameCount = Int(buffer.frameLength)
        let length = Int(sampleRate * 0.25)

        for frame in 0..<frameCount {
            guard frame < length else { break }
            let progress = Double(frame) / Double(length)

            // Descending: 500 → 250 Hz
            let freq = 500.0 - progress * 250.0
            phases[0] += (2.0 * .pi * freq) / sampleRate

            let env = Float(pow(1.0 - progress, 1.5))
            let sample = Float(sin(phases[0])) * env * amplitude * 0.3

            data[0][frame] = max(-1, min(1, data[0][frame] + sample * 0.5))
            data[1][frame] = max(-1, min(1, data[1][frame] + sample * 0.5))
        }
    }

    // MARK: - Failure Tone

    /// Low dissonant buzz — something went wrong. ~0.3s
    /// Minor second interval (unsettling but brief).
    func fillFailureTone(buffer: AVAudioPCMBuffer, amplitude: Float) {
        guard let data = buffer.floatChannelData, buffer.format.channelCount >= 2 else { return }
        let frameCount = Int(buffer.frameLength)
        let length = Int(sampleRate * 0.3)

        for frame in 0..<frameCount {
            guard frame < length else { break }
            let progress = Double(frame) / Double(length)

            // Two notes a minor second apart (dissonant)
            phases[0] += (2.0 * .pi * 220.0) / sampleRate   // A3
            phases[1] += (2.0 * .pi * 233.08) / sampleRate   // Bb3

            let env = Float(pow(1.0 - progress, 1.2))
            let tone = (Float(sin(phases[0])) * 0.4 + Float(sin(phases[1])) * 0.35) * env * amplitude * 0.4

            // Slight wobble
            phases[2] += (2.0 * .pi * 6.0) / sampleRate
            let wobble = Float(1.0 + sin(phases[2]) * 0.2)

            let sample = tone * wobble
            data[0][frame] = max(-1, min(1, data[0][frame] + sample * 0.5))
            data[1][frame] = max(-1, min(1, data[1][frame] + sample * 0.5))
        }
    }

    func resetPhases() {
        phases = Array(repeating: 0, count: 8)
    }
}
