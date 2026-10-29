import Foundation

/// The small set of "Answer Modes" the UI offers. Each one is a preset over provider routing,
/// web search and the output-token budget; none of them is a second settings store.
public enum ResponseMode: String, Codable, CaseIterable, Sendable {
    case localFast = "local_fast"
    case aiFast = "ai_fast"
    case webQuick = "web_quick"
    case webDeep = "web_deep"

    public static let `default`: ResponseMode = .webQuick

    public var label: String {
        switch self {
        case .localFast: "Local AI"
        case .aiFast: "Fast AI"
        case .webQuick: "Web Quick"
        case .webDeep: "Web Deep"
        }
    }

    public var help: String {
        switch self {
        case .localFast: "On-device Apple Intelligence, no web search, short answers."
        case .aiFast: "Selected AI provider, no web search, short answers."
        case .webQuick: "Selected AI provider, web search, concise sourced answers."
        case .webDeep: "Selected AI provider, web search, longer structured answers."
        }
    }

    public var maxOutputTokens: Int {
        switch self {
        case .localFast: 600
        case .aiFast: 800
        case .webQuick: 6_000
        case .webDeep: 10_000
        }
    }

    public var usesWebSearch: Bool {
        self == .webQuick || self == .webDeep
    }

    /// Falls back to the default for an unknown stored value.
    public init(storedValue: String) {
        self = ResponseMode(rawValue: storedValue) ?? .default
    }
}
