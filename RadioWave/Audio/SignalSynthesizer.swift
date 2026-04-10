import AVFoundation
import Foundation

/// Musical signal synthesis with multiple variants per state.
/// Each state has 3-4 sound "presets" that rotate randomly so it never gets stale.
final class SignalSynthesizer {
    private let sampleRate: Double

    // Oscillator banks
    private var phases: [Double] = Array(repeating: 0, count: 16)
    private var lfoPhases: [Double] = Array(repeating: 0, count: 8)
    private var sampleCounter: Int = 0

    // Current variant per state — rotated by AudioEngine
    nonisolated(unsafe) var thinkingVariant: Int = 0
    nonisolated(unsafe) var toolUseVariant: Int = 0
    nonisolated(unsafe) var generatingVariant: Int = 0
    nonisolated(unsafe) var errorVariant: Int = 0

    // Waveshaping table
    private let warmTable: [Float]

    init(sampleRate: Double = 44100) {
        self.sampleRate = sampleRate
        var table = [Float]()
        for i in 0..<4096 {
            let x = Float(i) / 2048.0 - 1.0
            table.append(tanh(x * 1.8) * 0.85)
        }
        warmTable = table
    }

    private func warm(_ input: Float) -> Float {
        let index = max(0, min(4095, Int((input * 0.5 + 0.5) * 4095)))
        return warmTable[index]
    }

    // MARK: - Thinking (3 variants)

    func fillThinking(buffer: AVAudioPCMBuffer, amplitude: Float) {
        switch thinkingVariant {
        case 0: fillThinkingChordDrone(buffer: buffer, amplitude: amplitude)
        case 1: fillThinkingOceanicPad(buffer: buffer, amplitude: amplitude)
        default: fillThinkingNumberStation(buffer: buffer, amplitude: amplitude)
        }
    }

    /// Variant 0: Three-voice chord drone (A2 root + fifth + octave)
    private func fillThinkingChordDrone(buffer: AVAudioPCMBuffer, amplitude: Float) {
        guard let data = buffer.floatChannelData, buffer.format.channelCount >= 2 else { return }
        let frameCount = Int(buffer.frameLength)

        for frame in 0..<frameCount {
            sampleCounter += 1
            let t = Double(sampleCounter) / sampleRate
            let d1 = sin(t * 0.067) * 0.5
            let d2 = sin(t * 0.041 + 1.3) * 0.4

            let root = 110.0 + d1 * 4.0
            phases[0] += (2.0 * .pi * root) / sampleRate
            phases[1] += (2.0 * .pi * root * 3.0) / sampleRate
            let v1 = Float(sin(phases[0])) * 0.55 + Float(sin(phases[1])) * 0.1

            let fifth = root * 1.498 + d2 * 3.0
            phases[2] += (2.0 * .pi * fifth) / sampleRate
            let v2 = Float(sin(phases[2])) * 0.3

            let oct = root * 2.003
            phases[3] += (2.0 * .pi * oct) / sampleRate
            let v3Amp = Float(0.08 + 0.08 * sin(t * 0.09))
            let v3 = Float(sin(phases[3])) * v3Amp

            phases[4] += (2.0 * .pi * root * 0.5) / sampleRate
            let sub = Float(sin(phases[4])) * 0.12

            lfoPhases[0] += (2.0 * .pi * 0.18) / sampleRate
            let trem = Float(0.75 + 0.25 * sin(lfoPhases[0]))
            let mono = warm((v1 + v2 + v3 + sub) * amplitude * trem)

            let pan = Float(sin(t * 0.11) * 0.15)
            data[0][frame] = mono * (0.5 + pan)
            data[1][frame] = mono * (0.5 - pan)
        }
        wrapPhases()
    }

    /// Variant 1: Oceanic pad — wide stereo with slow filter sweep feel
    private func fillThinkingOceanicPad(buffer: AVAudioPCMBuffer, amplitude: Float) {
        guard let data = buffer.floatChannelData, buffer.format.channelCount >= 2 else { return }
        let frameCount = Int(buffer.frameLength)

        for frame in 0..<frameCount {
            sampleCounter += 1
            let t = Double(sampleCounter) / sampleRate

            // Deep root with slow vibrato
            let root = 82.4 + sin(t * 0.05) * 2.0  // E2
            phases[0] += (2.0 * .pi * root) / sampleRate
            phases[1] += (2.0 * .pi * root * 2.0) / sampleRate
            phases[2] += (2.0 * .pi * root * 3.01) / sampleRate  // slightly detuned 3rd harmonic

            // Harmonic mix evolves: more overtones during "bright" phase
            let brightness = Float(0.5 + 0.5 * sin(t * 0.033))  // 30s cycle
            let v1 = Float(sin(phases[0])) * 0.5
            let v2 = Float(sin(phases[1])) * 0.2 * brightness
            let v3 = Float(sin(phases[2])) * 0.1 * brightness * brightness

            // Major third above, very soft (creates a major chord feel)
            let third = root * 1.26  // ~E2 major third
            phases[3] += (2.0 * .pi * third) / sampleRate
            let v4 = Float(sin(phases[3])) * 0.12

            // Stereo chorus: same content but phase-shifted between channels
            phases[4] += (2.0 * .pi * root * 1.002) / sampleRate  // 0.2% detune
            let chorusR = Float(sin(phases[4])) * 0.3

            lfoPhases[0] += (2.0 * .pi * 0.12) / sampleRate
            let swell = Float(0.6 + 0.4 * sin(lfoPhases[0]))

            let left = warm((v1 + v2 + v3 + v4) * amplitude * swell)
            let right = warm((chorusR + v2 + v3 + v4) * amplitude * swell)
            data[0][frame] = left
            data[1][frame] = right
        }
        wrapPhases()
    }

    /// Variant 2: Number station — eerie shortwave with faint rhythmic blips
    private func fillThinkingNumberStation(buffer: AVAudioPCMBuffer, amplitude: Float) {
        guard let data = buffer.floatChannelData, buffer.format.channelCount >= 2 else { return }
        let frameCount = Int(buffer.frameLength)

        for frame in 0..<frameCount {
            sampleCounter += 1
            let t = Double(sampleCounter) / sampleRate

            // Carrier with slow FM wobble (shortwave propagation)
            let wobble = sin(t * 0.7) * 8.0 + sin(t * 0.23) * 3.0
            let carrier = 196.0 + wobble  // G3
            phases[0] += (2.0 * .pi * carrier) / sampleRate
            let tone = Float(sin(phases[0])) * 0.35

            // Rhythmic blips: every ~1.2 seconds, a brief high ping
            let blipPhase = (t * 0.83).truncatingRemainder(dividingBy: 1.0)
            let blip: Float
            if blipPhase < 0.04 {
                phases[1] += (2.0 * .pi * 1200.0) / sampleRate
                blip = Float(sin(phases[1])) * 0.15 * Float(1.0 - blipPhase / 0.04)
            } else {
                blip = 0
            }

            // Fading echo of carrier
            phases[2] += (2.0 * .pi * carrier * 0.999) / sampleRate
            let echo = Float(sin(phases[2])) * 0.08

            // Deep drone underneath
            phases[3] += (2.0 * .pi * 55.0) / sampleRate
            let drone = Float(sin(phases[3])) * 0.1

            // AM fading (ionospheric propagation)
            lfoPhases[0] += (2.0 * .pi * 0.08) / sampleRate  // very slow
            let fade = Float(0.4 + 0.6 * pow(sin(lfoPhases[0]) * 0.5 + 0.5, 2.0))

            let mixed = (tone + blip + echo + drone) * amplitude * fade
            // Slight stereo spread
            data[0][frame] = max(-1, min(1, mixed * 0.55))
            data[1][frame] = max(-1, min(1, mixed * 0.45 + blip * 0.1))
        }
        wrapPhases()
    }

    // MARK: - Tool Use (3 variants)

    func fillToolUse(buffer: AVAudioPCMBuffer, amplitude: Float) {
        switch toolUseVariant {
        case 0: fillToolUseClockwork(buffer: buffer, amplitude: amplitude)
        case 1: fillToolUseDialup(buffer: buffer, amplitude: amplitude)
        default: fillToolUseTeletype(buffer: buffer, amplitude: amplitude)
        }
    }

    /// Variant 0: Clockwork — pitched sequence with mechanical clicks
    private func fillToolUseClockwork(buffer: AVAudioPCMBuffer, amplitude: Float) {
        guard let data = buffer.floatChannelData, buffer.format.channelCount >= 2 else { return }
        let frameCount = Int(buffer.frameLength)

        let sequences: [[Double]] = [
            [660, 550, 770, 440, 660, 880, 550, 770],
            [520, 620, 520, 740, 620, 520, 880, 740],
            [440, 660, 550, 660, 770, 660, 550, 440],
        ]

        for frame in 0..<frameCount {
            sampleCounter += 1
            let t = Double(sampleCounter) / sampleRate
            let seqIdx = Int(t / 4.0) % sequences.count
            let seq = sequences[seqIdx]
            let tempo = 8.0 + sin(t * 0.2) * 2.0
            let noteIndex = Int(t * tempo) % seq.count
            let freq = seq[noteIndex]

            lfoPhases[0] += tempo / sampleRate
            let notePhase = lfoPhases[0].truncatingRemainder(dividingBy: 1.0)
            let env: Float = notePhase < 0.05 ? Float(notePhase / 0.05)
                           : notePhase < 0.35 ? Float(1.0 - (notePhase - 0.05) / 0.3 * 0.6)
                           : notePhase < 0.6 ? 0.4
                           : Float(0.4 * (1.0 - (notePhase - 0.6) / 0.4))

            phases[0] += (2.0 * .pi * freq) / sampleRate
            phases[1] += (2.0 * .pi * freq * 3.0) / sampleRate
            let tone = Float(sin(phases[0])) * 0.7 + Float(sin(phases[1])) * 0.12
            let click: Float = notePhase < 0.008 ? Float.random(in: 0.3...0.5) : 0

            let mixed = (tone * env + click) * amplitude
            let pan = Float(noteIndex % 2 == 0 ? 0.35 : 0.65)
            data[0][frame] = max(-1, min(1, mixed * (1.0 - pan)))
            data[1][frame] = max(-1, min(1, mixed * pan))
        }
        wrapPhases()
    }

    /// Variant 1: Dialup modem — classic handshake sounds with frequency sweeps
    private func fillToolUseDialup(buffer: AVAudioPCMBuffer, amplitude: Float) {
        guard let data = buffer.floatChannelData, buffer.format.channelCount >= 2 else { return }
        let frameCount = Int(buffer.frameLength)

        for frame in 0..<frameCount {
            sampleCounter += 1
            let t = Double(sampleCounter) / sampleRate

            // Dual-tone alternation (like DTMF/modem negotiation)
            let cyclePos = t.truncatingRemainder(dividingBy: 3.0)
            let freq1: Double, freq2: Double, mix: Double

            if cyclePos < 1.0 {
                // Rising sweep
                freq1 = 400.0 + cyclePos * 1600.0
                freq2 = 1200.0 + sin(cyclePos * 20.0) * 200.0
                mix = 0.6
            } else if cyclePos < 2.0 {
                // Stable dual tone
                let p = cyclePos - 1.0
                freq1 = 1400.0 + sin(p * 8.0) * 50.0
                freq2 = 2100.0 + sin(p * 12.0) * 30.0
                mix = 0.5
            } else {
                // Falling with warble
                let p = cyclePos - 2.0
                freq1 = 2000.0 - p * 1200.0
                freq2 = 1800.0 - p * 600.0 + sin(p * 30.0) * 100.0
                mix = 0.7
            }

            phases[0] += (2.0 * .pi * freq1) / sampleRate
            phases[1] += (2.0 * .pi * freq2) / sampleRate
            let tone1 = Float(sin(phases[0])) * Float(mix) * 0.35
            let tone2 = Float(sin(phases[1])) * Float(1.0 - mix) * 0.35

            // Digital noise bursts between phases
            let noise: Float = Int(t * 15.0) % 3 == 0 ? Float.random(in: -0.08...0.08) : 0

            let mixed = (tone1 + tone2 + noise) * amplitude
            data[0][frame] = max(-1, min(1, mixed * 0.55))
            data[1][frame] = max(-1, min(1, mixed * 0.45))
        }
        wrapPhases()
    }

    /// Variant 2: Teletype — rhythmic clicking with pitched confirmation tones
    private func fillToolUseTeletype(buffer: AVAudioPCMBuffer, amplitude: Float) {
        guard let data = buffer.floatChannelData, buffer.format.channelCount >= 2 else { return }
        let frameCount = Int(buffer.frameLength)

        for frame in 0..<frameCount {
            sampleCounter += 1
            let t = Double(sampleCounter) / sampleRate

            // Fast rhythmic clicks (12 per second, irregular)
            let clickRate = 12.0
            lfoPhases[0] += clickRate / sampleRate
            let clickPhase = lfoPhases[0].truncatingRemainder(dividingBy: 1.0)

            // Irregular rhythm: some clicks are skipped
            let beatNum = Int(lfoPhases[0])
            let shouldClick = (beatNum * 7 + 3) % 5 != 0  // pseudo-random skip pattern

            var sample: Float = 0

            if shouldClick && clickPhase < 0.08 {
                // Click: short noise burst with slight pitch
                let clickFreq = 3000.0 + Double(beatNum % 4) * 500.0
                phases[0] += (2.0 * .pi * clickFreq) / sampleRate
                let env = Float(1.0 - clickPhase / 0.08)
                sample = (Float(sin(phases[0])) * 0.4 + Float.random(in: -0.3...0.3)) * env * amplitude
            }

            // Confirmation tone every ~2 seconds (bell-like)
            let bellPhase = (t * 0.5).truncatingRemainder(dividingBy: 1.0)
            if bellPhase < 0.15 {
                phases[1] += (2.0 * .pi * 880.0) / sampleRate
                phases[2] += (2.0 * .pi * 1108.7) / sampleRate  // major third
                let bellEnv = Float(1.0 - bellPhase / 0.15)
                let bell = (Float(sin(phases[1])) * 0.3 + Float(sin(phases[2])) * 0.15) * bellEnv * bellEnv * amplitude
                sample += bell
            }

            // Alternate click position in stereo
            let pan: Float = (beatNum % 3 == 0) ? 0.3 : (beatNum % 3 == 1) ? 0.5 : 0.7
            data[0][frame] = max(-1, min(1, sample * (1.0 - pan)))
            data[1][frame] = max(-1, min(1, sample * pan))
        }
        wrapPhases()
    }

    // MARK: - Generating (3 variants)

    func fillGenerating(buffer: AVAudioPCMBuffer, amplitude: Float, pitchOffset: Double = 0) {
        switch generatingVariant {
        case 0: fillGeneratingFM(buffer: buffer, amplitude: amplitude, pitchOffset: pitchOffset)
        case 1: fillGeneratingArpeggio(buffer: buffer, amplitude: amplitude, pitchOffset: pitchOffset)
        default: fillGeneratingPulsar(buffer: buffer, amplitude: amplitude, pitchOffset: pitchOffset)
        }
    }

    /// Variant 0: Rich dual-layer FM synthesis
    private func fillGeneratingFM(buffer: AVAudioPCMBuffer, amplitude: Float, pitchOffset: Double) {
        guard let data = buffer.floatChannelData, buffer.format.channelCount >= 2 else { return }
        let frameCount = Int(buffer.frameLength)

        for frame in 0..<frameCount {
            sampleCounter += 1
            let t = Double(sampleCounter) / sampleRate
            let cBase = 280.0 + pitchOffset + sin(t * 0.083) * 8.0

            let m1F = cBase * (1.0 + sin(t * 0.051) * 0.01)
            let m1I = 1.8 + sin(t * 0.13) * 1.2 + sin(t * 0.07) * 0.5
            phases[4] += (2.0 * .pi * m1F) / sampleRate
            phases[5] += (2.0 * .pi * (cBase + sin(phases[4]) * m1I * m1F)) / sampleRate
            let fm1 = warm(Float(sin(phases[5])) * 0.8)

            let m2F = cBase * 0.707
            let m2I = 0.6 + sin(t * 0.17) * 0.4
            phases[6] += (2.0 * .pi * m2F) / sampleRate
            phases[7] += (2.0 * .pi * (cBase * 1.5 + sin(phases[6]) * m2I * m2F)) / sampleRate
            let fm2 = Float(sin(phases[7])) * 0.22

            phases[8] += (2.0 * .pi * cBase * 0.5) / sampleRate
            let sub = Float(sin(phases[8])) * 0.1

            lfoPhases[2] += (2.0 * .pi * 0.31) / sampleRate
            lfoPhases[3] += (2.0 * .pi * 0.37) / sampleRate
            let shimL = Float(0.85 + 0.15 * sin(lfoPhases[2]))
            let shimR = Float(0.85 + 0.15 * sin(lfoPhases[3]))

            let mixed = (fm1 + fm2 + sub) * amplitude
            data[0][frame] = max(-1, min(1, mixed * shimL))
            data[1][frame] = max(-1, min(1, mixed * shimR))
        }
        wrapPhases()
    }

    /// Variant 1: Gentle arpeggio — notes cycle through a chord, like a music box
    private func fillGeneratingArpeggio(buffer: AVAudioPCMBuffer, amplitude: Float, pitchOffset: Double) {
        guard let data = buffer.floatChannelData, buffer.format.channelCount >= 2 else { return }
        let frameCount = Int(buffer.frameLength)

        // C major 7 arpeggio in different inversions
        let chords: [[Double]] = [
            [261.6, 329.6, 392.0, 493.9],   // C E G B
            [293.7, 370.0, 440.0, 523.3],   // D F# A C
            [246.9, 311.1, 370.0, 466.2],   // B Eb F# Bb (dim feel)
        ]

        for frame in 0..<frameCount {
            sampleCounter += 1
            let t = Double(sampleCounter) / sampleRate

            let chordIdx = Int(t / 8.0) % chords.count  // change chord every 8s
            let chord = chords[chordIdx]
            let noteRate = 3.5 + sin(t * 0.1) * 0.5  // 3-4 notes/sec
            let noteIdx = Int(t * noteRate) % chord.count
            let freq = chord[noteIdx] + pitchOffset * 0.5

            // Bell-like envelope
            lfoPhases[0] += noteRate / sampleRate
            let notePhase = lfoPhases[0].truncatingRemainder(dividingBy: 1.0)
            let env = Float(pow(max(0, 1.0 - notePhase * 1.5), 2.0))  // fast decay

            // Tone with harmonics for bell quality
            phases[0] += (2.0 * .pi * freq) / sampleRate
            phases[1] += (2.0 * .pi * freq * 2.0) / sampleRate
            phases[2] += (2.0 * .pi * freq * 3.98) / sampleRate  // inharmonic = bell
            let tone = Float(sin(phases[0])) * 0.5
                     + Float(sin(phases[1])) * 0.2 * env
                     + Float(sin(phases[2])) * 0.08 * env * env

            // Soft pad underneath
            phases[3] += (2.0 * .pi * chord[0] * 0.5) / sampleRate
            let pad = Float(sin(phases[3])) * 0.08

            let mixed = (tone * env + pad) * amplitude

            // Notes alternate across stereo
            let pan = Float(0.3 + 0.4 * sin(Double(noteIdx) * 1.5))
            data[0][frame] = max(-1, min(1, mixed * (1.0 - pan)))
            data[1][frame] = max(-1, min(1, mixed * pan))
        }
        wrapPhases()
    }

    /// Variant 2: Pulsar — rhythmic deep pulse with harmonics, like a star
    private func fillGeneratingPulsar(buffer: AVAudioPCMBuffer, amplitude: Float, pitchOffset: Double) {
        guard let data = buffer.floatChannelData, buffer.format.channelCount >= 2 else { return }
        let frameCount = Int(buffer.frameLength)

        for frame in 0..<frameCount {
            sampleCounter += 1
            let t = Double(sampleCounter) / sampleRate

            // Pulse rate: 2.5 Hz with slow drift
            let pulseRate = 2.5 + sin(t * 0.07) * 0.3
            lfoPhases[0] += pulseRate / sampleRate
            let pulsePhase = lfoPhases[0].truncatingRemainder(dividingBy: 1.0)

            // Gaussian-ish pulse envelope
            let env = Float(exp(-pow((pulsePhase - 0.15) * 8.0, 2.0)))

            // Rich tone during pulse
            let freq = 165.0 + pitchOffset + sin(t * 0.05) * 5.0
            phases[0] += (2.0 * .pi * freq) / sampleRate
            phases[1] += (2.0 * .pi * freq * 2.0) / sampleRate
            phases[2] += (2.0 * .pi * freq * 3.0) / sampleRate
            phases[3] += (2.0 * .pi * freq * 0.5) / sampleRate

            let tone = Float(sin(phases[0])) * 0.5
                     + Float(sin(phases[1])) * 0.2
                     + Float(sin(phases[2])) * 0.08
                     + Float(sin(phases[3])) * 0.15  // sub

            // Between pulses: very faint residual hum
            let residual = Float(sin(phases[0])) * 0.03

            let mixed = (tone * env + residual) * amplitude

            // Stereo: pulse center, residual wide
            lfoPhases[1] += (2.0 * .pi * 0.2) / sampleRate
            let spread = Float(sin(lfoPhases[1])) * 0.1
            data[0][frame] = max(-1, min(1, mixed * (0.5 + spread)))
            data[1][frame] = max(-1, min(1, mixed * (0.5 - spread)))
        }
        wrapPhases()
    }

    // MARK: - Error (2 variants)

    func fillError(buffer: AVAudioPCMBuffer, amplitude: Float) {
        switch errorVariant {
        case 0: fillErrorSiren(buffer: buffer, amplitude: amplitude)
        default: fillErrorGlitch(buffer: buffer, amplitude: amplitude)
        }
    }

    /// Variant 0: Descending two-tone siren
    private func fillErrorSiren(buffer: AVAudioPCMBuffer, amplitude: Float) {
        guard let data = buffer.floatChannelData, buffer.format.channelCount >= 2 else { return }
        let frameCount = Int(buffer.frameLength)

        for frame in 0..<frameCount {
            sampleCounter += 1
            let t = Double(sampleCounter) / sampleRate
            let cycle = t.truncatingRemainder(dividingBy: 1.5)
            let freq = cycle < 0.75 ? 720.0 - cycle * 200.0 : 520.0 + (cycle - 0.75) * 100.0
            phases[0] += (2.0 * .pi * freq) / sampleRate
            var tone = warm(Float(sin(phases[0])) * 1.5)

            lfoPhases[0] += (2.0 * .pi * 10.0) / sampleRate
            tone *= Float(0.4 + 0.6 * abs(sin(lfoPhases[0]))) * amplitude

            lfoPhases[1] += (2.0 * .pi * 3.0) / sampleRate
            let pan = Float(0.5 + 0.4 * sin(lfoPhases[1]))
            data[0][frame] = max(-1, min(1, tone * (1.0 - pan)))
            data[1][frame] = max(-1, min(1, tone * pan))
        }
        wrapPhases()
    }

    /// Variant 1: Digital glitch — bitcrushed stuttering
    private func fillErrorGlitch(buffer: AVAudioPCMBuffer, amplitude: Float) {
        guard let data = buffer.floatChannelData, buffer.format.channelCount >= 2 else { return }
        let frameCount = Int(buffer.frameLength)

        for frame in 0..<frameCount {
            sampleCounter += 1
            let t = Double(sampleCounter) / sampleRate

            // Stuttering: repeat samples (bitcrush/downsample effect)
            let stutter = max(1, Int(8.0 + sin(t * 5.0) * 6.0))
            let quantizedFrame = (frame / stutter) * stutter

            // Harsh square-ish wave
            let freq = 440.0 + sin(t * 3.0) * 200.0
            let phase = Double(quantizedFrame) * 2.0 * .pi * freq / sampleRate + phases[0]
            var sample = Float(sin(phase)) > 0 ? amplitude * 0.5 : -amplitude * 0.5

            // Random dropout
            if Int(t * 8.0) % 5 == 0 { sample = 0 }

            // Noise bursts
            if Int(t * 12.0) % 7 == 0 {
                sample += Float.random(in: -0.3...0.3) * amplitude
            }

            data[0][frame] = max(-1, min(1, sample * 0.6))
            data[1][frame] = max(-1, min(1, sample * 0.4))
        }
        phases[0] += Double(frameCount) * 2.0 * .pi * 440.0 / sampleRate
        wrapPhases()
    }

    // MARK: - Helpers

    func randomizeAllVariants() {
        thinkingVariant = Int.random(in: 0...2)
        toolUseVariant = Int.random(in: 0...2)
        generatingVariant = Int.random(in: 0...2)
        errorVariant = Int.random(in: 0...1)
    }

    func reset() {
        phases = Array(repeating: 0, count: 16)
        lfoPhases = Array(repeating: 0, count: 8)
        sampleCounter = 0
    }

    private func wrapPhases() {
        let limit = 2.0 * Double.pi * 10000.0
        for i in phases.indices {
            if abs(phases[i]) > limit { phases[i] = phases[i].truncatingRemainder(dividingBy: 2.0 * .pi) }
        }
        for i in lfoPhases.indices {
            if abs(lfoPhases[i]) > limit { lfoPhases[i] = lfoPhases[i].truncatingRemainder(dividingBy: 2.0 * .pi) }
        }
    }
}
