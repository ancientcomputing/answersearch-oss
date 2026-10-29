import Foundation

/// Report of whether Apple's on-device model can answer on this Mac.
public struct LocalAIAvailability: Equatable, Sendable {
    public var supported: Bool
    /// Machine-readable: `available`, `unsupported_hardware`, `capability_missing`,
    /// `model_not_ready`, `api_unavailable`.
    public var reason: String
    public var detail: String

    public init(supported: Bool, reason: String, detail: String) {
        self.supported = supported
        self.reason = reason
        self.detail = detail
    }

    public static let unknown = LocalAIAvailability(
        supported: false, reason: "api_unavailable",
        detail: "Local AI availability could not be determined."
    )
}

public enum LocalOutcome: Equatable, Sendable {
    case answer(String)
    /// The on-device model declined (or failed); the caller falls back to the provider.
    case deferred(reason: String)
}

/// Answers a request with the on-device model after a conservative triage step.
@MainActor
public protocol LocalAnswering {
    var availability: LocalAIAvailability { get }
    func answer(_ request: AnswerRequest) async throws -> LocalOutcome
}

/// Answers a request with a hosted provider (Anthropic or OpenAI), optionally with web search.
@MainActor
public protocol ProviderAnswering {
    func answer(
        _ request: AnswerRequest,
        provider: ProviderKind,
        onStatus: @escaping @MainActor (String) -> Void
    ) async throws -> RawAnswer
}

/// A local backend that is never available. Used on systems without Apple Intelligence support
/// and as the default in tests.
@MainActor
public struct UnavailableLocalAnswerer: LocalAnswering {
    public let availability: LocalAIAvailability
    public init(availability: LocalAIAvailability = .unknown) {
        self.availability = availability
    }
    public func answer(_ request: AnswerRequest) async throws -> LocalOutcome {
        .deferred(reason: "local_model_unavailable")
    }
}
