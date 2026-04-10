import Foundation
import Network
import os

/// Lightweight HTTP server that receives Claude Code hook events.
/// Listens on a local port and parses POST requests from hook callbacks.
final class HookServer {
    static let defaultPort: UInt16 = 19847

    private let port: UInt16
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.radiowave.hookserver", qos: .userInitiated)
    private let logger = Logger(subsystem: "com.hirakbanerjee.RadioWave", category: "HookServer")

    var onEvent: ((HookEvent) -> Void)?

    init(port: UInt16 = HookServer.defaultPort) {
        self.port = port
    }

    func start() throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true

        listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
        listener?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.logger.info("Hook server listening on port \(self?.port ?? 0)")
            case .failed(let error):
                self?.logger.error("Hook server failed: \(error)")
                self?.listener?.cancel()
            default:
                break
            }
        }
        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }
        listener?.start(queue: queue)
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveHTTPRequest(connection: connection, accumulated: Data())
    }

    private func receiveHTTPRequest(connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            guard let self else { return }

            var data = accumulated
            if let content { data.append(content) }

            if let error {
                self.logger.error("Connection error: \(error)")
                connection.cancel()
                return
            }

            // Check if we have the full HTTP request (headers + body)
            if let parsed = self.parseHTTPRequest(data) {
                self.processPayload(parsed)
                self.sendHTTPResponse(connection: connection)
            } else if isComplete {
                // Connection closed before full request — try parsing what we have
                if let parsed = self.parseHTTPRequest(data) {
                    self.processPayload(parsed)
                }
                self.sendHTTPResponse(connection: connection)
            } else {
                // Need more data
                self.receiveHTTPRequest(connection: connection, accumulated: data)
            }
        }
    }

    private func parseHTTPRequest(_ data: Data) -> Data? {
        guard let str = String(data: data, encoding: .utf8) else { return nil }

        // Find the blank line separating headers from body
        guard let headerEnd = str.range(of: "\r\n\r\n") else { return nil }

        let headers = str[str.startIndex..<headerEnd.lowerBound]
        let bodyStart = headerEnd.upperBound

        // Extract Content-Length
        var contentLength = 0
        for line in headers.split(separator: "\r\n") {
            let lower = line.lowercased()
            if lower.hasPrefix("content-length:") {
                let value = line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)
                contentLength = Int(value) ?? 0
            }
        }

        let bodyStr = str[bodyStart...]
        if bodyStr.utf8.count >= contentLength {
            return Data(bodyStr.prefix(contentLength).utf8)
        }

        return nil // Need more data
    }

    private func processPayload(_ data: Data) {
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            let event = HookEvent(from: json)
            logger.info("Hook event: \(event.eventName)")
            onEvent?(event)
        } catch {
            logger.error("Failed to parse hook payload: \(error)")
        }
    }

    private func sendHTTPResponse(connection: NWConnection) {
        let response = "HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok"
        let data = Data(response.utf8)
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

struct HookEvent {
    let eventName: String
    let sessionId: String
    let toolName: String
    let transcriptPath: String
    let cwd: String
    let raw: [String: Any]

    init(from json: [String: Any]) {
        self.eventName = json["hook_event_name"] as? String ?? json["hookEventName"] as? String ?? "unknown"
        self.sessionId = json["session_id"] as? String ?? json["sessionId"] as? String ?? ""
        self.toolName = json["tool_name"] as? String ?? json["toolName"] as? String ?? ""
        self.transcriptPath = json["transcript_path"] as? String ?? json["transcriptPath"] as? String ?? ""
        self.cwd = json["cwd"] as? String ?? ""
        self.raw = json
    }
}
