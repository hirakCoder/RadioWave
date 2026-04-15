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
        var id: String          // sessionId (may start as pid-XXX, updated when real ID arrives)
        let cwd: String         // working directory
        let startTime: Date
        var lastEvent: String
        var realSessionId: String?  // the actual Claude session ID (once a hook event arrives)
        var displayName: String {
            let path = cwd as NSString
            let folder = path.lastPathComponent
            if folder.isEmpty || folder == "hirakbanerjee" {
                return "Home"
            }
            // Show parent/folder for clarity (e.g., "Desktop/SwiftGen")
            let parent = (path.deletingLastPathComponent as NSString).lastPathComponent
            if parent.isEmpty || parent == "hirakbanerjee" || parent == "Users" {
                return folder
            }
            return "\(parent)/\(folder)"
        }
    }

    /// Register a session. If a discovered (pid-based) session has the same cwd,
    /// upgrade it with the real session ID instead of creating a duplicate.
    func registerSession(id: String, cwd: String) {
        // Check if we already have a pid-based session with the same cwd
        if let existingKey = activeSessions.first(where: {
            $0.key.hasPrefix("pid-") && $0.value.cwd == cwd
        })?.key {
            // Upgrade: replace pid-based entry with real session ID
            var session = activeSessions.removeValue(forKey: existingKey)!
            session.id = id
            session.realSessionId = id
            activeSessions[id] = session
            // If user was monitoring the old pid-based entry, switch to the new ID
            if monitoredSessionId == existingKey {
                monitoredSessionId = id
            }
        } else if activeSessions[id] == nil {
            activeSessions[id] = SessionInfo(
                id: id, cwd: cwd, startTime: Date(),
                lastEvent: "connected", realSessionId: id
            )
        }
        activeSessionCount = activeSessions.count
    }

    func removeSession(id: String) {
        activeSessions.removeValue(forKey: id)
        activeSessionCount = activeSessions.count
        if monitoredSessionId == id {
            monitoredSessionId = nil
        }
    }

    func updateSessionEvent(id: String, event: String) {
        activeSessions[id]?.lastEvent = event
    }

    /// Match by session ID or by cwd (for pid-discovered sessions that haven't been upgraded yet)
    func shouldHandleEvent(sessionId: String) -> Bool {
        guard let monitored = monitoredSessionId else { return true } // nil = all

        // Direct ID match
        if sessionId == monitored { return true }

        // If monitoring a pid-based session, match by cwd instead
        if monitored.hasPrefix("pid-"),
           let monitoredCwd = activeSessions[monitored]?.cwd,
           let eventCwd = activeSessions[sessionId]?.cwd,
           monitoredCwd == eventCwd {
            return true
        }

        return false
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
