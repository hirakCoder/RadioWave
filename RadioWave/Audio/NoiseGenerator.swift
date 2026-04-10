import AVFoundation

/// Atmospheric noise generator with spatial width, micro-details,
/// and evolving character designed to be pleasant for extended listening.
final class NoiseGenerator {
    private let sampleRate: Double

    // State
    private var brownL: Float = 0
    private var brownR: Float = 0
    private var crackleCountdown: Int
    private var burstCountdown: Int
    private var burstRemaining: Int = 0
    private var driftPhase: Double = 0
    private var sweepPhase: Double = 0
    private var sweepActive: Bool = false
    private var sweepCountdown: Int
    private var morsePhase: Double = 0
    private var morsePattern: [Bool] = []
    private var morseIndex: Int = 0
    private var morseSampleCount: Int = 0
    private var morseCountdown: Int

    init(sampleRate: Double = 44100) {
        self.sampleRate = sampleRate
        crackleCountdown = Int.random(in: 3000...15000)
        burstCountdown = Int.random(in: 40000...150000)
        sweepCountdown = Int.random(in: 80000...200000)
        morseCountdown = Int.random(in: 100000...300000)
        generateMorsePattern()
    }

    // MARK: - Idle: Beautiful ambient static

    /// Warm atmospheric static with stereo crackle, distant sweep ghosts,
    /// faint morse fragments, and gentle breathing dynamics.
    func fillIdleAmbient(buffer: AVAudioPCMBuffer, amplitude: Float) {
        guard let data = buffer.floatChannelData, buffer.format.channelCount >= 2 else { return }
        let frameCount = Int(buffer.frameLength)

        for frame in 0..<frameCount {
            // Warm brown noise — slightly different per channel for width
            let whiteL = Float.random(in: -1...1)
            let whiteR = Float.random(in: -1...1)
            brownL = brownL * 0.986 + whiteL * 0.014
            brownR = brownR * 0.984 + whiteR * 0.016  // slightly different filter = stereo width
            var sampleL = brownL * 14.0 * amplitude
            var sampleR = brownR * 14.0 * amplitude

            // Slow breathing: the noise floor gently swells and recedes
            driftPhase += 0.05 / sampleRate
            let breath = Float(0.6 + 0.4 * sin(driftPhase * 2.0 * .pi))
            sampleL *= breath
            sampleR *= breath

            // Crackle: stereo pops that jump between ears
            crackleCountdown -= 1
            if crackleCountdown <= 0 {
                crackleCountdown = Int.random(in: 2000...18000)
                let intensity = Float.random(in: 0.15...0.6) * amplitude * 3.0
                if Bool.random() {
                    sampleL += intensity * (Bool.random() ? 1 : -1)
                } else {
                    sampleR += intensity * (Bool.random() ? 1 : -1)
                }
            }

            // Distant sweep ghost: a faint tone that slides through like a station passing
            sweepCountdown -= 1
            if sweepCountdown <= 0 && !sweepActive {
                sweepActive = true
                sweepPhase = 0
                sweepCountdown = Int.random(in: 100000...300000)
            }
            if sweepActive {
                sweepPhase += 1.0 / sampleRate
                let sweepDuration = 3.0  // seconds
                if sweepPhase > sweepDuration {
                    sweepActive = false
                } else {
                    let progress = sweepPhase / sweepDuration
                    let sweepFreq = 300.0 + progress * 1800.0
                    let envelope = Float(sin(progress * .pi)) * 0.04 * amplitude  // fades in and out
                    let tone = Float(sin(sweepPhase * 2.0 * .pi * sweepFreq)) * envelope
                    // Pan the sweep across stereo field
                    let pan = Float(progress)  // moves left to right
                    sampleL += tone * (1.0 - pan)
                    sampleR += tone * pan
                }
            }

            // Faint morse code fragments — rare, mysterious
            morseCountdown -= 1
            if morseCountdown <= 0 && morseIndex >= morsePattern.count {
                morseCountdown = Int.random(in: 150000...400000)
                morseIndex = 0
                morseSampleCount = 0
                generateMorsePattern()
            }
            if morseIndex < morsePattern.count {
                let dotLength = Int(sampleRate * 0.08)
                let currentBit = morseIndex < morsePattern.count ? morsePattern[morseIndex] : false
                morseSampleCount += 1
                if morseSampleCount > dotLength {
                    morseSampleCount = 0
                    morseIndex += 1
                }
                if currentBit {
                    morsePhase += (2.0 * .pi * 720.0) / sampleRate
                    let morseTone = Float(sin(morsePhase)) * 0.025 * amplitude
                    // Place morse slightly off-center
                    sampleL += morseTone * 0.3
                    sampleR += morseTone * 0.7
                }
            }

            // Burst interference — rare but dramatic
            burstCountdown -= 1
            if burstCountdown <= 0 && burstRemaining <= 0 {
                burstRemaining = Int.random(in: 800...3000)
                burstCountdown = Int.random(in: 50000...200000)
            }
            if burstRemaining > 0 {
                burstRemaining -= 1
                let env = min(Float(burstRemaining) / 500.0, 1.0) * amplitude * 2.0
                sampleL += Float.random(in: -1...1) * env * 0.6
                sampleR += Float.random(in: -1...1) * env * 0.4
            }

            data[0][frame] = max(-1, min(1, sampleL))
            data[1][frame] = max(-1, min(1, sampleR))
        }
    }

    // MARK: - Connected: Clean presence

    /// Clean warm hiss with a faint stereo pilot tone — feels like a station is locked.
    func fillConnectedPresence(buffer: AVAudioPCMBuffer, amplitude: Float) {
        guard let data = buffer.floatChannelData, buffer.format.channelCount >= 2 else { return }
        let frameCount = Int(buffer.frameLength)

        for frame in 0..<frameCount {
            let whiteL = Float.random(in: -1...1)
            let whiteR = Float.random(in: -1...1)
            brownL = brownL * 0.992 + whiteL * 0.008
            brownR = brownR * 0.991 + whiteR * 0.009
            var sampleL = brownL * 10.0 * amplitude
            var sampleR = brownR * 10.0 * amplitude

            // Warm pilot tone — stereo with slight detuning
            driftPhase += 1.0 / sampleRate
            let pilotAmpMod = Float(0.6 + 0.4 * sin(driftPhase * 0.15 * 2.0 * .pi))
            let pilotAmp = amplitude * 0.04 * pilotAmpMod
            let toneL = Float(sin(driftPhase * 380.0 * 2.0 * .pi)) * pilotAmp
            let toneR = Float(sin(driftPhase * 383.0 * 2.0 * .pi)) * pilotAmp  // 3Hz detune
            sampleL += toneL
            sampleR += toneR

            // Very gentle crackle
            crackleCountdown -= 1
            if crackleCountdown <= 0 {
                crackleCountdown = Int.random(in: 15000...40000)
                let pop = Float.random(in: 0.05...0.2) * amplitude
                if Bool.random() { sampleL += pop } else { sampleR += pop }
            }

            data[0][frame] = max(-1, min(1, sampleL))
            data[1][frame] = max(-1, min(1, sampleR))
        }
    }

    // MARK: - Thinking: Breathing atmosphere

    /// Slow-pulsing filtered noise, like listening to a deep space transmission.
    func fillThinkingAtmosphere(buffer: AVAudioPCMBuffer, amplitude: Float) {
        guard let data = buffer.floatChannelData, buffer.format.channelCount >= 2 else { return }
        let frameCount = Int(buffer.frameLength)

        for frame in 0..<frameCount {
            let whiteL = Float.random(in: -1...1)
            let whiteR = Float.random(in: -1...1)
            brownL = brownL * 0.996 + whiteL * 0.004
            brownR = brownR * 0.995 + whiteR * 0.005

            // Deep breathing pulse — inhale/exhale rhythm
            driftPhase += 0.22 / sampleRate  // ~4.5 second cycle
            let breathEnvelope = Float(pow(sin(driftPhase * 2.0 * .pi) * 0.5 + 0.5, 1.5))
            let sampleL = brownL * 8.0 * amplitude * (0.2 + breathEnvelope * 0.8)
            let sampleR = brownR * 8.0 * amplitude * (0.2 + breathEnvelope * 0.8)

            data[0][frame] = max(-1, min(1, sampleL))
            data[1][frame] = max(-1, min(1, sampleR))
        }
    }

    // MARK: - Generating: Minimal warmth

    /// Very subtle warm hiss — just enough to give the FM signal some air.
    func fillWarmHiss(buffer: AVAudioPCMBuffer, amplitude: Float) {
        guard let data = buffer.floatChannelData, buffer.format.channelCount >= 2 else { return }
        let frameCount = Int(buffer.frameLength)

        for frame in 0..<frameCount {
            brownL = brownL * 0.997 + Float.random(in: -1...1) * 0.003
            brownR = brownR * 0.996 + Float.random(in: -1...1) * 0.004
            data[0][frame] = max(-1, min(1, brownL * 5.0 * amplitude))
            data[1][frame] = max(-1, min(1, brownR * 5.0 * amplitude))
        }
    }

    // MARK: - Error: Dramatic dropout

    /// Signal dropout: sharp noise hit, then silence with fading crackle.
    func fillSignalDropout(buffer: AVAudioPCMBuffer, amplitude: Float) {
        guard let data = buffer.floatChannelData, buffer.format.channelCount >= 2 else { return }
        let frameCount = Int(buffer.frameLength)
        let hitFrames = Int(sampleRate * 0.06)
        let crackleStart = Int(sampleRate * 0.15)

        for frame in 0..<frameCount {
            var sampleL: Float = 0
            var sampleR: Float = 0

            if frame < hitFrames {
                // Sharp noise hit
                let env = 1.0 - Float(frame) / Float(hitFrames)
                sampleL = Float.random(in: -1...1) * amplitude * env * 1.5
                sampleR = Float.random(in: -1...1) * amplitude * env * 1.5
            } else if frame > crackleStart {
                // Fading crackle
                let decay = max(0, 1.0 - Float(frame - crackleStart) / Float(frameCount - crackleStart))
                if Int.random(in: 0...200) == 0 {
                    let pop = Float.random(in: 0.1...0.4) * amplitude * decay
                    if Bool.random() { sampleL = pop } else { sampleR = pop }
                }
            }

            data[0][frame] = max(-1, min(1, sampleL))
            data[1][frame] = max(-1, min(1, sampleR))
        }
    }

    // MARK: - Tuning Sweep (transition effect)

    /// Simulates turning a radio dial: static → brief fragments → resolve.
    /// Call this during state transitions for the signature RadioWave feel.
    func fillTuningSweep(buffer: AVAudioPCMBuffer, amplitude: Float,
                         fromFreq: Double, toFreq: Double, progress: Double) {
        guard let data = buffer.floatChannelData, buffer.format.channelCount >= 2 else { return }
        let frameCount = Int(buffer.frameLength)

        for frame in 0..<frameCount {
            let t = Double(frame) / Double(frameCount)
            let totalProgress = progress + t * (1.0 / 20.0)  // assumes ~20 buffers per transition

            // Frequency sweeps from start to target
            let freq = fromFreq + (toFreq - fromFreq) * totalProgress
            sweepPhase += (2.0 * .pi * freq) / sampleRate

            // Static intensity: high at start, dips when "passing stations", low at end
            let staticAmount = Float(1.0 - totalProgress) * 0.8
            let noiseL = Float.random(in: -1...1) * amplitude * staticAmount
            let noiseR = Float.random(in: -1...1) * amplitude * staticAmount

            // Tone clarity: inverse of static
            let toneAmount = Float(totalProgress)
            let tone = Float(sin(sweepPhase)) * amplitude * toneAmount * 0.4

            // Brief "station fragments" at random points
            let fragmentTone: Float
            if Int.random(in: 0...1000) < 3 {
                fragmentTone = Float(sin(sweepPhase * Double.random(in: 0.5...2.0))) * amplitude * 0.15
            } else {
                fragmentTone = 0
            }

            // Squelch break sound at the very end (satisfying "lock")
            let squelch: Float
            if totalProgress > 0.9 {
                let squelchProgress = (totalProgress - 0.9) / 0.1
                squelch = Float(sin(squelchProgress * .pi)) * amplitude * 0.1
            } else {
                squelch = 0
            }

            let sampleL = max(-1, min(1, noiseL + tone * 0.6 + fragmentTone + squelch))
            let sampleR = max(-1, min(1, noiseR + tone * 0.4 + fragmentTone + squelch))
            data[0][frame] = sampleL
            data[1][frame] = sampleR
        }
    }

    // MARK: - Helpers

    private func generateMorsePattern() {
        // Generate a random morse-like pattern (dots and dashes with gaps)
        morsePattern = []
        let wordLength = Int.random(in: 3...6)
        for _ in 0..<wordLength {
            let charLength = Int.random(in: 1...5)
            for _ in 0..<charLength {
                let isDash = Bool.random()
                let onBits = isDash ? 3 : 1
                for _ in 0..<onBits { morsePattern.append(true) }
                morsePattern.append(false) // inter-element gap
            }
            morsePattern.append(false) // inter-character gap
            morsePattern.append(false)
        }
    }

    func reset() {
        brownL = 0
        brownR = 0
        crackleCountdown = Int.random(in: 3000...15000)
        burstCountdown = Int.random(in: 40000...150000)
        burstRemaining = 0
        driftPhase = 0
        sweepPhase = 0
        sweepActive = false
        sweepCountdown = Int.random(in: 80000...200000)
        morseCountdown = Int.random(in: 100000...300000)
        morseIndex = morsePattern.count  // inactive
    }
}
