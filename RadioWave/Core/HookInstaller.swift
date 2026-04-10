import Foundation
import os

/// Manages Claude Code hook configuration in ~/.claude/settings.json.
/// Installs HTTP hooks that point to RadioWave's local server.
struct HookInstaller {
    private static let logger = Logger(subsystem: "com.hirakbanerjee.RadioWave", category: "HookInstaller")

    static let hookEvents = [
        "SessionStart",
        "SessionEnd",
        "UserPromptSubmit",
        "PreToolUse",
        "PostToolUse",
        "Stop",
        "Notification"
    ]

    static var settingsPath: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
    }

    static func install(port: UInt16 = HookServer.defaultPort) {
        let baseURL = "http://localhost:\(port)/hook"

        do {
            var settings = readSettings() ?? [String: Any]()
            var hooks = settings["hooks"] as? [String: Any] ?? [:]

            for event in hookEvents {
                let hookURL = "\(baseURL)/\(event.lowercased())"
                let hookDef: [String: Any] = [
                    "type": "http",
                    "url": hookURL,
                    "async": true
                ]

                // Check if our hook is already installed
                if let existing = hooks[event] as? [[String: Any]] {
                    let alreadyInstalled = existing.contains { group in
                        if let groupHooks = group["hooks"] as? [[String: Any]] {
                            return groupHooks.contains { ($0["url"] as? String)?.contains("localhost:\(port)") == true }
                        }
                        return false
                    }
                    if alreadyInstalled { continue }
                }

                let group: [String: Any]
                if event == "PreToolUse" || event == "PostToolUse" {
                    group = ["matcher": "*", "hooks": [hookDef]]
                } else {
                    group = ["hooks": [hookDef]]
                }

                // Append to existing hooks for this event
                var eventHooks = hooks[event] as? [[String: Any]] ?? []
                eventHooks.append(group)
                hooks[event] = eventHooks
            }

            settings["hooks"] = hooks

            let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: settingsPath)
            logger.info("Hooks installed successfully")
        } catch {
            logger.error("Failed to install hooks: \(error)")
        }
    }

    static func uninstall(port: UInt16 = HookServer.defaultPort) {
        do {
            guard var settings = readSettings() else { return }
            guard var hooks = settings["hooks"] as? [String: Any] else { return }

            for event in hookEvents {
                guard var eventHooks = hooks[event] as? [[String: Any]] else { continue }
                eventHooks.removeAll { group in
                    if let groupHooks = group["hooks"] as? [[String: Any]] {
                        return groupHooks.allSatisfy { ($0["url"] as? String)?.contains("localhost:\(port)") == true }
                    }
                    return false
                }
                if eventHooks.isEmpty {
                    hooks.removeValue(forKey: event)
                } else {
                    hooks[event] = eventHooks
                }
            }

            if hooks.isEmpty {
                settings.removeValue(forKey: "hooks")
            } else {
                settings["hooks"] = hooks
            }

            let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: settingsPath)
            logger.info("Hooks uninstalled successfully")
        } catch {
            logger.error("Failed to uninstall hooks: \(error)")
        }
    }

    static func isInstalled(port: UInt16 = HookServer.defaultPort) -> Bool {
        guard let settings = readSettings(),
              let hooks = settings["hooks"] as? [String: Any],
              let sessionStart = hooks["SessionStart"] as? [[String: Any]] else {
            return false
        }
        return sessionStart.contains { group in
            if let groupHooks = group["hooks"] as? [[String: Any]] {
                return groupHooks.contains { ($0["url"] as? String)?.contains("localhost:\(port)") == true }
            }
            return false
        }
    }

    private static func readSettings() -> [String: Any]? {
        guard let data = try? Data(contentsOf: settingsPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }
}
