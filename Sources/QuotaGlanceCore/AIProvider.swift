import Foundation

public enum AIProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case codex
    case claude

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .codex: "Codex"
        case .claude: "Claude"
        }
    }

    public var shortName: String {
        switch self {
        case .codex: "C"
        case .claude: "A"
        }
    }
}
