import AVFoundation
import os

/// Manages the AVAudioEngine pipeline with tuning-dial transitions between states.
/// Node chain: sourceNode → reverbNode → mainMixerNode → outputNode
///
/// Audio rendering runs on a real-time thread. Shared state uses nonisolated(unsafe)
/// for simple value types with benign races.
final class AudioEngine: ObservableObject {
    private let engine = AVAudioEngine()
    private let noiseGen = NoiseGenerator()
    private let synthesizer = SignalSynthesizer()
    private let logger = Logger(subsystem: "com.hirakbanerjee.RadioWave", category: "AudioEngine")

    private let format: AVAudioFormat
    private var sourceNode: AVAudioSourceNode?
    private let reverbNode = AVAudioUnitReverb()

    @MainActor @Published var isPlaying = false

    // Shared render-thread state
    nonisolated(unsafe) private var currentState: RadioState = .idle
    nonisolated(unsafe) private var currentVolume: Float = 0.15
    nonisolated(unsafe) private var masterVolume: Float = 0.5
    nonisolated(unsafe) private var staticIntensity: Float = 0.4
    nonisolated(unsafe) private var idleStaticEnabled: Bool = true
    nonisolated(unsafe) private var generatingStartTime: Date?

    // Tuning transition state
    nonisolated(unsafe) private var isTuning: Bool = false
    nonisolated(unsafe) private var tuningProgress: Double = 0
    nonisolated(unsafe) private var tuningFromFreq: Double = 88.5
    nonisolated(unsafe) private var tuningToFreq: Double = 88.5
    nonisolated(unsafe) private var tuningFromState: RadioState = .idle

    private var targetVolume: Float = 0.15
    private var crossfadeTimer: Timer?
    private var tuningTimer: Timer?

    init() {
        self.format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        setupEngine()
    }

    private func setupEngine() {
        reverbNode.loadFactoryPreset(.mediumHall)
        reverbNode.wetDryMix = 20
        engine.attach(reverbNode)

        let fmt = format
        let renderBlock: AVAudioSourceNodeRenderBlock = { [weak self] _, _, frameCount, bufferList -> OSStatus in
            guard let self else { return noErr }

            let ablPointer = UnsafeMutableAudioBufferListPointer(bufferList)
            let buffer = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(frameCount))!
            buffer.frameLength = AVAudioFrameCount(frameCount)

            if let channelData = buffer.floatChannelData {
                for ch in 0..<Int(fmt.channelCount) {
                    memset(channelData[ch], 0, Int(frameCount) * MemoryLayout<Float>.size)
                }
            }

            self.renderAudio(into: buffer)

            if let channelData = buffer.floatChannelData {
                for ch in 0..<min(Int(fmt.channelCount), ablPointer.count) {
                    let dest = ablPointer[ch].mData!.assumingMemoryBound(to: Float.self)
                    memcpy(dest, channelData[ch], Int(frameCount) * MemoryLayout<Float>.size)
                }
            }

            return noErr
        }

        let source = AVAudioSourceNode(format: format, renderBlock: renderBlock)
        sourceNode = source

        engine.attach(source)
        engine.connect(source, to: reverbNode, format: format)
        engine.connect(reverbNode, to: engine.mainMixerNode, format: format)
    }

    // MARK: - Render

    private func renderAudio(into buffer: AVAudioPCMBuffer) {
        // If we're in a tuning transition, render the dial sweep
        if isTuning {
            renderTuning(into: buffer)
            return
        }

        let state = currentState
        let vol = currentVolume * masterVolume
        let staticAmp = staticIntensity

        switch state {
        case .idle:
            if idleStaticEnabled {
                noiseGen.fillIdleAmbient(buffer: buffer, amplitude: 0.07 * vol * staticAmp)
            }

        case .connected:
            noiseGen.fillConnectedPresence(buffer: buffer, amplitude: 0.06 * vol * staticAmp)

        case .thinking:
            let toneBuffer = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength)!
            toneBuffer.frameLength = buffer.frameLength
            noiseGen.fillThinkingAtmosphere(buffer: buffer, amplitude: 0.03 * vol * staticAmp)
            synthesizer.fillThinking(buffer: toneBuffer, amplitude: 0.35 * vol)
            mixBuffers(source: toneBuffer, into: buffer)

        case .toolUse:
            let toneBuffer = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength)!
            toneBuffer.frameLength = buffer.frameLength
            noiseGen.fillWarmHiss(buffer: buffer, amplitude: 0.015 * vol * staticAmp)
            synthesizer.fillToolUse(buffer: toneBuffer, amplitude: 0.38 * vol)
            mixBuffers(source: toneBuffer, into: buffer)

        case .generating:
            let toneBuffer = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength)!
            toneBuffer.frameLength = buffer.frameLength
            let elapsed = generatingStartTime.map { Date().timeIntervalSince($0) } ?? 0
            let pitchOffset = min(elapsed / 30.0, 1.0) * 80.0
            noiseGen.fillWarmHiss(buffer: buffer, amplitude: 0.01 * vol)
            synthesizer.fillGenerating(buffer: toneBuffer, amplitude: 0.42 * vol, pitchOffset: pitchOffset)
            mixBuffers(source: toneBuffer, into: buffer)

        case .error:
            let toneBuffer = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength)!
            toneBuffer.frameLength = buffer.frameLength
            noiseGen.fillSignalDropout(buffer: buffer, amplitude: 0.35 * vol)
            synthesizer.fillError(buffer: toneBuffer, amplitude: 0.28 * vol)
            mixBuffers(source: toneBuffer, into: buffer)
        }
    }

    /// Renders the tuning-dial sweep transition — static + fragments + resolving tone.
    private func renderTuning(into buffer: AVAudioPCMBuffer) {
        let vol = currentVolume * masterVolume
        noiseGen.fillTuningSweep(
            buffer: buffer,
            amplitude: 0.15 * vol,
            fromFreq: tuningFromFreq,
            toFreq: tuningToFreq,
            progress: tuningProgress
        )
    }

    private func mixBuffers(source: AVAudioPCMBuffer, into dest: AVAudioPCMBuffer) {
        guard let srcData = source.floatChannelData,
              let dstData = dest.floatChannelData else { return }
        let frames = Int(dest.frameLength)
        let channels = Int(dest.format.channelCount)
        for ch in 0..<channels {
            for f in 0..<frames {
                dstData[ch][f] += srcData[ch][f]
            }
        }
    }

    // MARK: - Controls

    @MainActor
    func start() {
        guard !engine.isRunning else { return }
        do {
            try engine.start()
            isPlaying = true
            logger.info("Audio engine started")
        } catch {
            logger.error("Failed to start audio engine: \(error)")
        }
    }

    @MainActor
    func stop() {
        engine.stop()
        isPlaying = false
    }

    @MainActor
    func transition(to state: RadioState) {
        guard state != currentState else { return }

        // Pick a random sound variant for the new state
        synthesizer.randomizeAllVariants()

        let fromState = currentState

        if state == .generating {
            generatingStartTime = Date()
        } else if currentState == .generating {
            generatingStartTime = nil
        }

        // Start tuning transition
        tuningFromFreq = fromState.frequencyMHz * 2.0  // scale to audible range
        tuningToFreq = state.frequencyMHz * 2.0
        tuningFromState = fromState
        tuningProgress = 0
        isTuning = true

        // Animate tuning progress over 0.6 seconds
        tuningTimer?.invalidate()
        let tuningDuration = 0.6
        let tuningSteps = 30
        let stepInterval = tuningDuration / Double(tuningSteps)
        var step = 0

        tuningTimer = Timer.scheduledTimer(withTimeInterval: stepInterval, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            step += 1
            self.tuningProgress = Double(step) / Double(tuningSteps)
            if step >= tuningSteps {
                timer.invalidate()
                self.isTuning = false
                self.currentState = state
            }
        }

        // Also crossfade volume
        let oldVolume = volumeForState(fromState)
        let newVolume = volumeForState(state)
        crossfade(from: oldVolume, to: newVolume, duration: 0.8)
    }

    @MainActor
    func updateSettings(masterVolume: Float, staticIntensity: Float, idleStaticEnabled: Bool) {
        self.masterVolume = masterVolume
        self.staticIntensity = staticIntensity
        self.idleStaticEnabled = idleStaticEnabled
    }

    private func volumeForState(_ state: RadioState) -> Float {
        switch state {
        case .idle: return 0.15
        case .connected: return 0.25
        case .thinking: return 0.40
        case .toolUse: return 0.45
        case .generating: return 0.55
        case .error: return 0.40
        }
    }

    @MainActor
    private func crossfade(from: Float, to: Float, duration: Double) {
        crossfadeTimer?.invalidate()
        let steps = 40
        let stepDuration = duration / Double(steps)
        let stepSize = (to - from) / Float(steps)
        var step = 0

        crossfadeTimer = Timer.scheduledTimer(withTimeInterval: stepDuration, repeats: true) { [weak self] timer in
            step += 1
            self?.currentVolume = from + stepSize * Float(step)
            if step >= steps {
                timer.invalidate()
                self?.currentVolume = to
                self?.targetVolume = to
            }
        }
    }
}
