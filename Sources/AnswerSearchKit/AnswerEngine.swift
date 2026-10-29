import Foundation

public struct SearchInput: Sendable {
    public var question: String
    public var related: Bool
    public var doubleCheck: Bool
    public var locale: String

    public init(question: String, related: Bool = false, doubleCheck: Bool = false, locale: String = "") {
        self.question = question
        self.related = related
        self.doubleCheck = doubleCheck
        self.locale = locale
    }
}

/// Why a request was or was not sent to the on-device model.
public enum LocalRouteReason: String, Sendable {
    case useLocal = "local_ai_available"
    case disabled = "local_ai_disabled"
    case unavailable = "local_ai_unavailable"
    case linksRequested = "links_requested"
    case relatedProviderAnswer = "related_provider_answer"
    case unsupportedQueryKind = "unsupported_query_mode"
    case doubleCheckRequested = "double_check_requested"
}

/// The product flow: build a request, decide local vs. provider, answer, label, and remember
/// the one previous transaction for follow-ups.
@MainActor
public final class AnswerEngine {
    public var settings: AppSettings
    public private(set) var previous: PreviousTransaction?

    private let local: LocalAnswering
    private let provider: ProviderAnswering
    private let clock: @Sendable () -> Date

    public init(
        settings: AppSettings = AppSettings(),
        local: LocalAnswering,
        provider: ProviderAnswering,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.settings = settings
        self.local = local
        self.provider = provider
        self.clock = clock
    }

    public var localAIAvailability: LocalAIAvailability { local.availability }

    public func clearPrevious() {
        previous = nil
    }

    // MARK: Request construction

    func makeRequest(for input: SearchInput, question: String) -> AnswerRequest {
        var kind = QueryKind.newSearch
        var context: PreviousTransaction?
        if input.doubleCheck, let previous {
            kind = .doubleCheck
            context = previous
        } else if input.related, let previous {
            kind = .relatedQuestion
            context = previous
        }
        let mode = settings.responseMode
        return AnswerRequest(
            question: question,
            kind: kind,
            previous: context,
            model: settings.model,
            responseMode: mode,
            maxOutputTokens: mode.maxOutputTokens,
            useWebSearch: mode.usesWebSearch && settings.provider.supportsWebSearch,
            webSearchMaxUses: mode.usesWebSearch ? settings.webSearchMaxUses : 0,
            linksRequested: LinkIntent.isLinkRequest(question),
            location: settings.location,
            locale: input.locale,
            now: clock()
        )
    }

    func localRoute(for request: AnswerRequest) -> (useLocal: Bool, reason: LocalRouteReason) {
        guard settings.responseMode == .localFast else { return (false, .disabled) }
        if request.kind == .relatedQuestion, request.previous?.answeredBy != .localAI {
            return (false, .relatedProviderAnswer)
        }
        guard settings.automaticallyUseLocalAI else { return (false, .disabled) }
        guard local.availability.supported else { return (false, .unavailable) }
        if request.linksRequested { return (false, .linksRequested) }
        if request.kind == .doubleCheck { return (false, .unsupportedQueryKind) }
        return (true, .useLocal)
    }

    // MARK: Search

    public func search(
        _ input: SearchInput,
        onStatus: @escaping @MainActor (String) -> Void = { _ in }
    ) async throws -> SearchResult {
        let question = input.question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else {
            throw SearchError(.invalidRequest, "Enter a question.")
        }

        var request = makeRequest(for: input, question: question)
        var route = localRoute(for: request)
        if input.doubleCheck {
            route = (false, .doubleCheckRequested)
            request = request.providerFast
        }
        if !route.useLocal, settings.responseMode == .localFast {
            request = request.providerFast
        }

        // Local AI is tried first only in Local AI mode, when opted in and available. If it defers,
        // errors or answers nothing, the same question goes to the online provider below, using
        // Fast AI behavior (`providerFast`).
        if route.useLocal {
            onStatus("Checking with AI on this Mac...")
            if let result = await tryLocal(request, question: question, reason: route.reason) {
                return result
            }
            request = request.providerFast
        }

        onStatus("Thinking...")
        let raw: RawAnswer
        do {
            raw = try await provider.answer(request, provider: settings.provider, onStatus: onStatus)
        } catch let error as SearchError {
            throw error
        } catch is CancellationError {
            throw SearchError(.cancelled, "Search cancelled.")
        } catch {
            throw SearchError(.providerError, error.localizedDescription)
        }

        let answer = AnswerText.sanitize(raw.text)
        guard !answer.isEmpty else {
            throw SearchError(.providerError, "The AI provider returned an empty answer.")
        }
        let sources = Self.uniqueSources(raw.sources)
        let result = SearchResult(
            question: question,
            answer: answer,
            answerMarkdown: MarkdownTables.normalize(answer),
            sources: sources,
            showSources: !sources.isEmpty && (request.linksRequested || raw.webSearchUsed),
            webSearchUsed: raw.webSearchUsed,
            searches: raw.searches,
            model: raw.model,
            answeredBy: .configuredProvider,
            answeredByLabel: "Answered by \(settings.provider.shortName)",
            doubleCheckLabel: "Double-check with \(settings.provider.shortName)",
            responseMode: request.responseMode
        )
        previous = PreviousTransaction(
            question: question, answer: answer, answeredBy: .configuredProvider, webSearchUsed: raw.webSearchUsed
        )
        return result
    }

    /// Returns nil whenever the on-device model should not answer (deferred, empty or failed), which
    /// tells `search` to fall back to the online provider.
    private func tryLocal(_ request: AnswerRequest, question: String, reason: LocalRouteReason) async -> SearchResult? {
        let outcome: LocalOutcome
        do {
            outcome = try await local.answer(request)
        } catch {
            return nil
        }
        guard case .answer(let text) = outcome else { return nil }
        let answer = AnswerText.cleanLocalAnswer(text)
        guard !answer.isEmpty else { return nil }
        previous = PreviousTransaction(
            question: question, answer: answer, answeredBy: .localAI, webSearchUsed: false
        )
        return SearchResult(
            question: question,
            answer: answer,
            answerMarkdown: MarkdownTables.normalize(answer),
            sources: [],
            showSources: false,
            webSearchUsed: false,
            searches: [],
            model: "Apple Foundation Models",
            answeredBy: .localAI,
            answeredByLabel: "Answered by AI on this Mac",
            doubleCheckLabel: "Double-check with \(settings.provider.shortName)",
            responseMode: request.responseMode
        )
    }

    static func uniqueSources(_ sources: [Source]) -> [Source] {
        var seen = Set<String>()
        var unique: [Source] = []
        for source in sources {
            let url = source.url.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !url.isEmpty, seen.insert(url).inserted else { continue }
            unique.append(source)
        }
        return unique
    }
}
