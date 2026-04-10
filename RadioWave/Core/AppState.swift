import SwiftUI
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published var radioState: RadioState = .idle
    @Published var demoMode: Bool = false
    @Published var signalStrength: Double = 0.12
    @Published var noiseLevel: Double = 0.88
    @Published var cpuLoad: Double = 0.0
    @Published var frequencyMHz: Double = 88.5
    @Published var isMonitoring: Bool = false
    @Published var currentToolName: String = ""
    @Published var activeSessionCount: Int = 0
    @Published var lastEventDescription: String = "No signal"

    private var targetFrequency: Double = 88.5
    private var frequencyTimer: Timer?

    func transition(to newState: RadioState, toolName: String = "") {
        guard newState != radioState || (newState == .toolUse && toolName != currentToolName) else { return }

        let oldState = radioState
        radioState = newState
        currentToolName = toolName

        targetFrequency = newState.frequencyMHz
        animateFrequency()

        updateMeters(from: oldState, to: newState)
        updateEventDescription(state: newState, toolName: toolName)
    }

    private func animateFrequency() {
        frequencyTimer?.invalidate()
        let step = (targetFrequency - frequencyMHz) / 20.0
        guard abs(step) > 0.01 else {
            frequencyMHz = targetFrequency
            return
        }
        frequencyTimer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self else { timer.invalidate(); return }
                self.frequencyMHz += step
                if abs(self.frequencyMHz - self.targetFrequency) < abs(step) {
                    self.frequencyMHz = self.targetFrequency
                    timer.invalidate()
                }
            }
        }
    }

    private func updateMeters(from oldState: RadioState, to newState: RadioState) {
        withAnimation(.easeInOut(duration: 0.8)) {
            switch newState {
            case .idle:
                signalStrength = 0.08
                noiseLevel = 0.85
                cpuLoad = 0.02
            case .connected:
                signalStrength = 0.35
                noiseLevel = 0.55
                cpuLoad = 0.05
            case .thinking:
                signalStrength = 0.60
                noiseLevel = 0.30
                cpuLoad = 0.15
            case .toolUse:
                signalStrength = 0.75
                noiseLevel = 0.15
                cpuLoad = 0.65
            case .generating:
                signalStrength = 0.95
                noiseLevel = 0.05
                cpuLoad = 0.30
            case .error:
                signalStrength = 0.02
                noiseLevel = 0.95
                cpuLoad = 0.0
            }
        }
    }

    private func updateEventDescription(state: RadioState, toolName: String) {
        switch state {
        case .idle:
            lastEventDescription = "No signal"
        case .connected:
            lastEventDescription = "Session active — awaiting prompt"
        case .thinking:
            lastEventDescription = "Processing prompt..."
        case .toolUse:
            lastEventDescription = toolName.isEmpty ? "Executing tool" : "Tool: \(toolName)"
        case .generating:
            lastEventDescription = "Generating response"
        case .error:
            lastEventDescription = "Signal lost"
        }
    }
}
