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

    // Multi-session tracking
    @Published var activeSessions: [String: SessionInfo] = [:]  // sessionId → info
    @Published var monitoredSessionId: String? = nil  // nil = monitor all

    struct SessionInfo: Identifiable {
        let id: String          // sessionId
        let cwd: String         // working directory
        let startTime: Date
        var lastEvent: String
        var displayName: String { // short label for picker
            let folder = (cwd as NSString).lastPathComponent
            return folder.isEmpty ? "Session \(id.prefix(6))" : folder
        }
    }

    func registerSession(id: String, cwd: String) {
        if activeSessions[id] == nil {
            activeSessions[id] = SessionInfo(id: id, cwd: cwd, startTime: Date(), lastEvent: "connected")
        }
        activeSessionCount = activeSessions.count
    }

    func removeSession(id: String) {
        activeSessions.removeValue(forKey: id)
        activeSessionCount = activeSessions.count
        // If the removed session was the one being monitored, reset to all
        if monitoredSessionId == id {
            monitoredSessionId = nil
        }
    }

    func updateSessionEvent(id: String, event: String) {
        activeSessions[id]?.lastEvent = event
    }

    func shouldHandleEvent(sessionId: String) -> Bool {
        guard let monitored = monitoredSessionId else { return true } // nil = all
        return sessionId == monitored
    }

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
