import Foundation

/// The hosted AI providers AnswerSearch can use for provider-backed answers.
public enum ProviderKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case anthropic
    case openai

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .anthropic: "Anthropic / Claude"
        case .openai: "OpenAI"
        }
    }

    /// Short name used in labels such as "Answered by Claude".
    public var shortName: String {
        switch self {
        case .anthropic: "Claude"
        case .openai: "OpenAI"
        }
    }

    public var defaultModel: String {
        switch self {
        case .anthropic: "claude-sonnet-4-6"
        case .openai: "gpt-5.5"
        }
    }

    public var modelPlaceholder: String {
        switch self {
        case .anthropic: "claude-sonnet-..."
        case .openai: "gpt-..."
        }
    }

    public var apiKeyLabel: String {
        switch self {
        case .anthropic: "Anthropic API key"
        case .openai: "OpenAI API key"
        }
    }

    public var apiKeyHelpURL: URL {
        switch self {
        case .anthropic: URL(string: "https://console.anthropic.com/settings/keys")!
        case .openai: URL(string: "https://platform.openai.com/api-keys")!
        }
    }

    public var supportsWebSearch: Bool { true }
}
