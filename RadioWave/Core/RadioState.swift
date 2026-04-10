import SwiftUI

enum RadioState: String, CaseIterable, Identifiable {
    case idle
    case connected
    case thinking
    case toolUse
    case generating
    case error

    var id: String { rawValue }

    var label: String {
        switch self {
        case .idle: return "STATIC"
        case .connected: return "STANDBY"
        case .thinking: return "THINKING"
        case .toolUse: return "TOOL USE"
        case .generating: return "ON AIR"
        case .error: return "ERROR"
        }
    }

    var color: Color {
        switch self {
        case .idle: return .white.opacity(0.4)
        case .connected: return .radioBlue
        case .thinking: return .radioOrange
        case .toolUse: return .cyan
        case .generating: return .radioGreen
        case .error: return .red
        }
    }

    var frequencyMHz: Double {
        switch self {
        case .idle: return 88.5
        case .connected: return 95.1
        case .thinking: return 102.3
        case .toolUse: return 128.7
        case .generating: return 142.8
        case .error: return 0.0
        }
    }

    var badgeText: String {
        switch self {
        case .generating: return "● ON AIR"
        case .thinking: return "● THINKING"
        case .toolUse: return "● TOOL USE"
        case .connected: return "● STANDBY"
        case .idle: return "STATIC"
        case .error: return "● ERROR"
        }
    }
}
