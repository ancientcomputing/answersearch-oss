import Foundation
import LocalLMLabSDKCore
import LocalLMLabSDKRemote

/// Hosted-provider answers through the LocalLM Lab SDK's `RemoteModelProvider`.
///
/// SDK usage, in order: build a `RemoteProviderConfig` -> register it with
/// `lab.models.replace` -> point a route at the model -> `lab.makeSession` -> `session.respond`,
/// then read `session.events` / `session.citations`. See the SDK guide, section 6b (online
/// providers) and 6a (sessions): https://github.com/ancientcomputing/locallm/blob/2.3.0-GA/docs/sdk-guide.md
///
/// One `RemoteProviderConfig` per provider is (re-)registered on the shared `LocalLMLab` before each
/// turn, so a changed API key or model takes effect immediately. The SDK's remote layer needs
/// macOS 27; on macOS 26 only the on-device Local AI mode is available.
@MainActor
public final class SDKProviderAnswerer: ProviderAnswering {
    private let lab: LocalLMLab
    private let credentials: CredentialStore
    private static let route: RouteName = "answer"

    public init(lab: LocalLMLab, credentials: CredentialStore) {
        self.lab = lab
        self.credentials = credentials
    }

    public func answer(
        _ request: AnswerRequest,
        provider: ProviderKind,
        onStatus: @escaping @MainActor (String) -> Void
    ) async throws -> RawAnswer {
        guard let key = credentials.apiKey(for: provider) else {
            throw SearchError(.configurationRequired, "Add your \(provider.apiKeyLabel) in Settings.")
        }
        guard #available(macOS 27, *) else {
            throw SearchError(
                .configurationRequired,
                "\(provider.displayName) answers need macOS 27 or later. On macOS 26 only Local AI is available."
            )
        }
        return try await answerRemote(request, provider: provider, apiKey: key, onStatus: onStatus)
    }

    @available(macOS 27, *)
    private func answerRemote(
        _ request: AnswerRequest,
        provider: ProviderKind,
        apiKey: String,
        onStatus: @escaping @MainActor (String) -> Void
    ) async throws -> RawAnswer {
        let model = request.model.trimmingCharacters(in: .whitespacesAndNewlines)
        let models = [RemoteModel(id: model.isEmpty ? provider.defaultModel : model)]

        // Presets fill in the dialect, base URL and auth shape. The SDK ships no model ids, so the
        // id comes from Settings. Anthropic uses the Messages API; OpenAI uses the Responses API
        // (the same API the earlier AnswerSearch builds used for hosted web search).
        var config: RemoteProviderConfig
        switch provider {
        case .anthropic: config = .anthropic(apiKey: apiKey, models: models)
        case .openai: config = .openAIResponses(apiKey: apiKey, models: models)
        }
        // Declares that this provider can run web search. Whether a given turn does is decided by
        // `SessionOptions.webSearch` below.
        config.capabilities.insert(.webSearch)

        // `RemoteModelProvider.init` validates the config (HTTPS base URL, credential syntax).
        let remote: RemoteModelProvider
        do {
            remote = try RemoteModelProvider(config)
        } catch {
            throw SearchError(.configurationRequired, error.localizedDescription)
        }
        // Register (or re-register) the provider before every turn so a changed key or model
        // takes effect immediately; `replace` swaps in place without rebuilding `LocalLMLab`.
        lab.models.replace(remote)

        guard let modelID = ModelID(scheme: config.scheme, rest: models[0].id) else {
            throw SearchError(.configurationRequired, "\"\(models[0].id)\" is not a valid model name.")
        }
        // A route is a name the app owns; sessions ask for the route, not a hard-coded model.
        lab.models.route(Self.route, to: modelID)

        // Per-turn knobs. The provider runs the web search itself (no MCP server needed), and
        // `userLocation` localizes results. It is only sent when web search is on.
        var options = SessionOptions(
            webSearch: request.useWebSearch,
            webSearchMaxUses: request.useWebSearch ? request.webSearchMaxUses : nil,
            maxOutputTokens: request.maxOutputTokens
        )
        if request.useWebSearch {
            options.userLocation = Self.userLocation(request.location)
        }

        // `instructions` become the system prompt. `includeMCPTools: false` because AnswerSearch
        // configures no MCP servers and wants a plain answer turn.
        let session = try lab.makeSession(
            route: Self.route,
            instructions: Prompts.system(for: request),
            includeMCPTools: false,
            options: options
        )

        // `session.events` reports provider-run web searches as they happen, so the UI can show
        // "Searching the web..." before the answer arrives.
        let tracker = SearchTracker()
        let events = Task { @MainActor in
            for await event in session.events {
                if case .serverToolCall(let activity) = event,
                   case .webSearch(let queries, let hits) = activity.kind {
                    tracker.record(queries: queries, hits: hits)
                    onStatus("Searching the web...")
                }
            }
        }
        defer { events.cancel() }

        let text: String
        do {
            text = try await session.respond(to: Prompts.user(for: request))
        } catch is CancellationError {
            throw SearchError(.cancelled, "Search cancelled.")
        } catch {
            throw SearchError(.providerError, Self.describe(error))
        }

        // `session.citations` is filled in by `respond`: the sources the provider cited. If the
        // provider cited nothing, fall back to the pages the search returned.
        var sources = session.citations.map { Source(title: $0.title, url: $0.url, citedText: $0.citedText) }
        if sources.isEmpty {
            sources = tracker.hits.map { Source(title: $0.title, url: $0.url, citedText: $0.snippet) }
        }
        return RawAnswer(
            text: text,
            sources: sources,
            searches: tracker.queries,
            webSearchUsed: tracker.used || !session.citations.isEmpty,
            model: models[0].id
        )
    }

    static func userLocation(_ location: RequestLocation) -> UserLocation? {
        func value(_ text: String) -> String? {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        guard !location.parts.isEmpty else { return nil }
        return UserLocation(
            city: value(location.city), region: value(location.region),
            country: value(location.country), timezone: value(location.timezone)
        )
    }

    static func describe(_ error: any Error) -> String {
        if let sdkError = error as? LocalLMLabError, let description = sdkError.errorDescription {
            return description
        }
        return error.localizedDescription
    }
}

/// Collects the provider-run web searches reported on `session.events`.
@MainActor
final class SearchTracker {
    private(set) var queries: [String] = []
    private(set) var hits: [WebHit] = []
    private(set) var used = false

    func record(queries newQueries: [String], hits newHits: [WebHit]) {
        used = true
        for query in newQueries {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, !queries.contains(trimmed) { queries.append(trimmed) }
        }
        hits.append(contentsOf: newHits)
    }
}
