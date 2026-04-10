import Foundation
import os

/// Tier 2 fallback: Watches ~/.claude/sessions/ for active Claude Code sessions
/// and monitors session JSONL transcripts for activity.
final class SessionWatcher {
    private let logger = Logger(subsystem: "com.hirakbanerjee.RadioWave", category: "SessionWatcher")
    private var pollTimer: Timer?
    private var fileHandle: FileHandle?
    private var watchedTranscriptPath: String?
    private var fileSource: DispatchSourceFileSystemObject?

    var onStateChange: ((RadioState, String) -> Void)?

    private var sessionsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/sessions")
    }

    func start() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.pollSessions()
        }
        pollSessions()
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        stopWatchingTranscript()
    }

    private func pollSessions() {
        let fm = FileManager.default
        let dir = sessionsDirectory.path

        guard fm.fileExists(atPath: dir) else {
            onStateChange?(.idle, "")
            return
        }

        do {
            let files = try fm.contentsOfDirectory(atPath: dir)
                .filter { $0.hasSuffix(".json") }

            var activeSessions: [(pid: Int32, sessionId: String, transcriptPath: String)] = []

            for file in files {
                let filePath = sessionsDirectory.appendingPathComponent(file).path
                guard let data = fm.contents(atPath: filePath),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let pid = json["pid"] as? Int else { continue }

                // Check if process is still alive
                if kill(Int32(pid), 0) == 0 {
                    let sessionId = json["sessionId"] as? String ?? ""
                    let cwd = json["cwd"] as? String ?? ""
                    let projectHash = cwd.replacingOccurrences(of: "/", with: "-")
                    let transcriptPath = FileManager.default.homeDirectoryForCurrentUser
                        .appendingPathComponent(".claude/projects/\(projectHash)/\(sessionId).jsonl").path
                    activeSessions.append((Int32(pid), sessionId, transcriptPath))
                }
            }

            if activeSessions.isEmpty {
                onStateChange?(.idle, "")
                stopWatchingTranscript()
            } else if watchedTranscriptPath == nil, let first = activeSessions.first {
                onStateChange?(.connected, "")
                startWatchingTranscript(at: first.transcriptPath)
            }
        } catch {
            logger.error("Failed to poll sessions: \(error)")
        }
    }

    private func startWatchingTranscript(at path: String) {
        stopWatchingTranscript()

        guard FileManager.default.fileExists(atPath: path) else { return }

        watchedTranscriptPath = path

        guard let handle = FileHandle(forReadingAtPath: path) else { return }
        fileHandle = handle

        // Seek to end — we only care about new events
        handle.seekToEndOfFile()

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: handle.fileDescriptor,
            eventMask: [.extend, .write],
            queue: .global(qos: .userInitiated)
        )
        source.setEventHandler { [weak self] in
            self?.readNewLines()
        }
        source.setCancelHandler { [weak self] in
            self?.fileHandle?.closeFile()
            self?.fileHandle = nil
        }
        source.resume()
        fileSource = source
    }

    private func stopWatchingTranscript() {
        fileSource?.cancel()
        fileSource = nil
        watchedTranscriptPath = nil
    }

    private func readNewLines() {
        guard let handle = fileHandle else { return }
        let data = handle.availableData
        guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }

        let lines = text.split(separator: "\n")
        for line in lines {
            guard let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else { continue }

            let type = json["type"] as? String ?? ""
            parseTranscriptLine(type: type, json: json)
        }
    }

    private func parseTranscriptLine(type: String, json: [String: Any]) {
        switch type {
        case "assistant":
            if let data = json["data"] as? [String: Any],
               let content = data["content"] as? [[String: Any]] {
                for block in content {
                    let blockType = block["type"] as? String ?? ""
                    if blockType == "thinking" {
                        onStateChange?(.thinking, "")
                    } else if blockType == "tool_use" {
                        let toolName = block["name"] as? String ?? ""
                        onStateChange?(.toolUse, toolName)
                    } else if blockType == "text" {
                        onStateChange?(.generating, "")
                    }
                }
            }
        case "progress":
            onStateChange?(.toolUse, "")
        case "user":
            onStateChange?(.thinking, "")
        default:
            break
        }
    }
}
