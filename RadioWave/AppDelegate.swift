import AppKit
import SwiftUI
import os

/// Manages the menubar status item, popover, and coordinates all subsystems.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var iconTimer: Timer?
    private let logger = Logger(subsystem: "com.hirakbanerjee.RadioWave", category: "AppDelegate")

    let appState = AppState()
    let audioEngine = AudioEngine()
    private let hookServer = HookServer()
    private let sessionWatcher = SessionWatcher()
    private var settingsObservers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        registerDefaults()
        setupStatusItem()
        setupPopover()
        setupHookServer()
        setupSessionWatcher()
        installHooksIfNeeded()
        observeSettings()

        // Push initial settings to audio engine
        syncSettingsToAudioEngine()

        if UserDefaults.standard.bool(forKey: "audioEnabled") {
            audioEngine.start()
        }

        startIconAnimation()
        logger.info("RadioWave launched")
    }

    private func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            "audioEnabled": true,
            "idleStaticEnabled": true,
            "playOnLaunch": true,
            "volume": 0.5,
            "staticIntensity": 0.4,
            "sensitivity": 0.5,
            "colorTheme": "Green"
        ])
    }

    func applicationWillTerminate(_ notification: Notification) {
        audioEngine.stop()
        hookServer.stop()
        sessionWatcher.stop()
        iconTimer?.invalidate()
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = makeIcon(barHeights: [3, 5, 8, 6, 4], active: false)
            button.action = #selector(togglePopover)
            button.target = self
        }
    }

    private func makeIcon(barHeights: [Int], active: Bool) -> NSImage {
        let width: CGFloat = 18
        let height: CGFloat = 18
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            let barCount = barHeights.count
            let barWidth: CGFloat = 2
            let gap: CGFloat = 1.5
            let totalWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * gap
            let startX = (width - totalWidth) / 2

            for (i, h) in barHeights.enumerated() {
                let barHeight = CGFloat(h)
                let x = startX + CGFloat(i) * (barWidth + gap)
                let y = (height - barHeight) / 2
                let barRect = NSRect(x: x, y: y, width: barWidth, height: barHeight)
                let path = NSBezierPath(roundedRect: barRect, xRadius: 0.5, yRadius: 0.5)
                NSColor.labelColor.withAlphaComponent(active ? 1.0 : 0.5).setFill()
                path.fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    private func startIconAnimation() {
        iconTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let state = self.appState.radioState
                let active = state != .idle

                let heights: [Int]
                if active {
                    heights = (0..<5).map { _ in Int.random(in: 2...14) }
                } else {
                    heights = [3, 5, 8, 6, 4]
                }

                self.statusItem.button?.image = self.makeIcon(barHeights: heights, active: active)
            }
        }
    }

    // MARK: - Popover

    private func setupPopover() {
        let view = PopoverView()
            .environmentObject(appState)
            .environmentObject(audioEngine)

        popover.contentViewController = NSHostingController(rootView: view)
        popover.contentSize = NSSize(width: 300, height: 340)
        popover.behavior = .transient
        popover.animates = true
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

            // Ensure popover gets focus
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    // MARK: - Hook Server (Tier 1)

    private func setupHookServer() {
        hookServer.onEvent = { [weak self] event in
            Task { @MainActor in
                self?.handleHookEvent(event)
            }
        }
        do {
            try hookServer.start()
        } catch {
            logger.error("Failed to start hook server: \(error)")
        }
    }

    private func handleHookEvent(_ event: HookEvent) {
        guard !appState.demoMode else { return }
        switch event.eventName.lowercased() {
        case "sessionstart":
            appState.activeSessionCount += 1
            appState.transition(to: .connected)
            audioEngine.transition(to: .connected)
            audioEngine.playChime(.sessionConnect)

        case "sessionend":
            appState.activeSessionCount = max(0, appState.activeSessionCount - 1)
            audioEngine.playChime(.sessionDisconnect)
            if appState.activeSessionCount == 0 {
                appState.transition(to: .idle)
                audioEngine.transition(to: .idle)
            }

        case "userpromptsubmit":
            appState.transition(to: .thinking)
            audioEngine.transition(to: .thinking)

        case "pretooluse":
            appState.transition(to: .toolUse, toolName: event.toolName)
            audioEngine.transition(to: .toolUse)

        case "posttooluse":
            // Tool completed — play a subtle ping, then back to generating
            audioEngine.playChime(.toolComplete)
            appState.transition(to: .generating)
            audioEngine.transition(to: .generating)

        case "posttoolusefailure":
            // Tool failed
            audioEngine.playChime(.failure)
            appState.transition(to: .generating)
            audioEngine.transition(to: .generating)

        case "stop":
            // Response complete — success chime, back to connected
            audioEngine.playChime(.success)
            appState.transition(to: .connected)
            audioEngine.transition(to: .connected)

        case "notification":
            // Brief alert then back to current
            let currentState = appState.radioState
            appState.transition(to: .error)
            audioEngine.transition(to: .error)
            Task {
                try? await Task.sleep(for: .seconds(1))
                self.appState.transition(to: currentState)
                self.audioEngine.transition(to: currentState)
            }

        default:
            logger.info("Unhandled hook event: \(event.eventName)")
        }
    }

    // MARK: - Session Watcher (Tier 2 fallback)

    private func setupSessionWatcher() {
        sessionWatcher.onStateChange = { [weak self] state, toolName in
            Task { @MainActor in
                guard let self, !self.appState.demoMode else { return }
                self.appState.transition(to: state, toolName: toolName)
                self.audioEngine.transition(to: state)
            }
        }
        sessionWatcher.start()
    }

    // MARK: - Hook Installation

    private func installHooksIfNeeded() {
        if !HookInstaller.isInstalled() {
            HookInstaller.install()
            UserDefaults.standard.set(true, forKey: "hooksInstalled")
            logger.info("Hooks auto-installed on first launch")
        }
    }

    // MARK: - Settings Sync

    private func syncSettingsToAudioEngine() {
        let ud = UserDefaults.standard
        // double(forKey:) returns 0.0 for unset keys even with register(defaults:)
        // on some launch sequences, so clamp to sensible minimums
        let vol = ud.object(forKey: "volume") != nil ? ud.double(forKey: "volume") : 0.5
        let staticInt = ud.object(forKey: "staticIntensity") != nil ? ud.double(forKey: "staticIntensity") : 0.4
        let idleStatic = ud.object(forKey: "idleStaticEnabled") != nil ? ud.bool(forKey: "idleStaticEnabled") : true

        logger.info("Syncing settings: volume=\(vol), static=\(staticInt), idleStatic=\(idleStatic)")
        audioEngine.updateSettings(
            masterVolume: Float(vol),
            staticIntensity: Float(staticInt),
            idleStaticEnabled: idleStatic
        )
    }

    private func observeSettings() {
        let keys = ["volume", "staticIntensity", "idleStaticEnabled", "audioEnabled"]
        for key in keys {
            let observer = NotificationCenter.default.addObserver(
                forName: UserDefaults.didChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                self.syncSettingsToAudioEngine()

                // Handle audioEnabled toggle from Settings window
                let enabled = UserDefaults.standard.bool(forKey: "audioEnabled")
                if enabled && !self.audioEngine.isPlaying {
                    self.audioEngine.start()
                } else if !enabled && self.audioEngine.isPlaying {
                    self.audioEngine.stop()
                }
            }
            settingsObservers.append(observer)
        }
    }
}
