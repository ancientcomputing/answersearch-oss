import Foundation
import Testing
@testable import AnswerSearchKit

@MainActor
private final class StubLocal: LocalAnswering {
    var availability: LocalAIAvailability
    var outcome: LocalOutcome
    var error: (any Error)?
    private(set) var requests: [AnswerRequest] = []

    init(supported: Bool = true, outcome: LocalOutcome = .answer("4")) {
        availability = LocalAIAvailability(supported: supported, reason: supported ? "available" : "capability_missing", detail: "")
        self.outcome = outcome
    }

    func answer(_ request: AnswerRequest) async throws -> LocalOutcome {
        requests.append(request)
        if let error { throw error }
        return outcome
    }
}

@MainActor
private final class StubProvider: ProviderAnswering {
    var raw = RawAnswer(text: "Provider answer", model: "stub-model")
    var error: (any Error)?
    private(set) var requests: [AnswerRequest] = []
    private(set) var providers: [ProviderKind] = []

    func answer(
        _ request: AnswerRequest, provider: ProviderKind, onStatus: @escaping @MainActor (String) -> Void
    ) async throws -> RawAnswer {
        requests.append(request)
        providers.append(provider)
        onStatus("Searching the web...")
        if let error { throw error }
        return raw
    }
}

@MainActor
private func makeEngine(
    mode: ResponseMode = .webQuick, localOptIn: Bool = false,
    local: StubLocal = StubLocal(), provider: StubProvider = StubProvider()
) -> (AnswerEngine, StubLocal, StubProvider) {
    var settings = AppSettings()
    settings.responseMode = mode
    settings.automaticallyUseLocalAI = localOptIn
    let engine = AnswerEngine(settings: settings, local: local, provider: provider)
    return (engine, local, provider)
}

@MainActor
@Suite struct EngineRoutingTests {
    @Test func emptyQuestionIsRejected() async {
        let (engine, _, _) = makeEngine()
        await #expect(throws: SearchError.self) {
            _ = try await engine.search(SearchInput(question: "   "))
        }
    }

    @Test func webQuickUsesProviderWithWebSearchPreset() async throws {
        let (engine, local, provider) = makeEngine(mode: .webQuick, localOptIn: true)
        let result = try await engine.search(SearchInput(question: "latest iPhone"))
        #expect(local.requests.isEmpty)
        let request = try #require(provider.requests.first)
        #expect(request.useWebSearch)
        #expect(request.maxOutputTokens == 6_000)
        #expect(request.webSearchMaxUses == 5)
        #expect(result.answeredBy == .configuredProvider)
        #expect(result.answeredByLabel == "Answered by Claude")
        #expect(result.doubleCheckLabel == "Double-check with Claude")
    }

    @Test func aiFastDisablesWebSearch() async throws {
        let (engine, _, provider) = makeEngine(mode: .aiFast)
        _ = try await engine.search(SearchInput(question: "hi"))
        let request = try #require(provider.requests.first)
        #expect(!request.useWebSearch)
        #expect(request.maxOutputTokens == 800)
    }

    @Test func webDeepUsesLargestBudget() async throws {
        let (engine, _, provider) = makeEngine(mode: .webDeep)
        _ = try await engine.search(SearchInput(question: "compare things"))
        #expect(provider.requests.first?.maxOutputTokens == 10_000)
    }

    @Test func localFastAnswersLocallyWhenOptedIn() async throws {
        let (engine, local, provider) = makeEngine(mode: .localFast, localOptIn: true, local: StubLocal(outcome: .answer("response_format: Text\n\n\"4\"")))
        let result = try await engine.search(SearchInput(question: "2+2"))
        #expect(provider.requests.isEmpty)
        #expect(local.requests.count == 1)
        #expect(result.answer == "4")
        #expect(result.answeredBy == .localAI)
        #expect(result.answeredByLabel == "Answered by AI on this Mac")
        #expect(!result.showSources)
    }

    @Test func localFastWithoutOptInUsesProviderFast() async throws {
        let (engine, local, provider) = makeEngine(mode: .localFast, localOptIn: false)
        _ = try await engine.search(SearchInput(question: "2+2"))
        #expect(local.requests.isEmpty)
        let request = try #require(provider.requests.first)
        #expect(request.responseMode == .aiFast)
        #expect(!request.useWebSearch)
    }

    @Test func localDeferFallsBackToProviderFast() async throws {
        let (engine, local, provider) = makeEngine(
            mode: .localFast, localOptIn: true, local: StubLocal(outcome: .deferred(reason: "not_local_safe"))
        )
        let result = try await engine.search(SearchInput(question: "weather today"))
        #expect(local.requests.count == 1)
        let request = try #require(provider.requests.first)
        #expect(request.responseMode == .aiFast)
        #expect(request.maxOutputTokens == 800)
        #expect(result.answeredBy == .configuredProvider)
    }

    @Test func localFailureFallsBackToProvider() async throws {
        let local = StubLocal()
        local.error = CancellationError()
        let (engine, _, provider) = makeEngine(mode: .localFast, localOptIn: true, local: local)
        let result = try await engine.search(SearchInput(question: "2+2"))
        #expect(provider.requests.count == 1)
        #expect(result.answeredBy == .configuredProvider)
    }

    @Test func linkRequestsSkipLocalAI() async throws {
        let (engine, local, provider) = makeEngine(mode: .localFast, localOptIn: true)
        _ = try await engine.search(SearchInput(question: "Give me sources about volcanoes"))
        #expect(local.requests.isEmpty)
        #expect(provider.requests.count == 1)
    }

    @Test func unsupportedLocalAIFallsBackToProvider() async throws {
        let (engine, local, provider) = makeEngine(mode: .localFast, localOptIn: true, local: StubLocal(supported: false))
        _ = try await engine.search(SearchInput(question: "2+2"))
        #expect(local.requests.isEmpty)
        #expect(provider.requests.count == 1)
    }

    @Test func providerFastRequestDisablesWebSearchAndLinks() {
        let request = AnswerRequest(
            question: "q", model: "m", responseMode: .localFast, maxOutputTokens: 600,
            useWebSearch: true, webSearchMaxUses: 5, linksRequested: true
        )
        let fast = request.providerFast
        #expect(fast.responseMode == .aiFast)
        #expect(fast.maxOutputTokens == 800)
        #expect(!fast.useWebSearch)
        #expect(fast.webSearchMaxUses == 0)
        #expect(!fast.linksRequested)
    }
}

@MainActor
@Suite struct EngineFollowUpTests {
    @Test func relatedQuestionCarriesOnlyThePreviousTransaction() async throws {
        let (engine, _, provider) = makeEngine(mode: .aiFast)
        provider.raw = RawAnswer(text: "First answer", model: "m")
        _ = try await engine.search(SearchInput(question: "first"))
        provider.raw = RawAnswer(text: "Second answer", model: "m")
        _ = try await engine.search(SearchInput(question: "second", related: true))
        let related = try #require(provider.requests.last)
        #expect(related.kind == .relatedQuestion)
        #expect(related.previous?.question == "first")
        #expect(related.previous?.answer == "First answer")

        _ = try await engine.search(SearchInput(question: "third", related: true))
        let third = try #require(provider.requests.last)
        #expect(third.previous?.question == "second") // never "first": context depth is one
    }

    @Test func newSearchIgnoresPrevious() async throws {
        let (engine, _, provider) = makeEngine(mode: .aiFast)
        _ = try await engine.search(SearchInput(question: "first"))
        _ = try await engine.search(SearchInput(question: "second"))
        let request = try #require(provider.requests.last)
        #expect(request.kind == .newSearch)
        #expect(request.previous == nil)
    }

    @Test func relatedWithoutPreviousIsANewSearch() async throws {
        let (engine, _, provider) = makeEngine(mode: .aiFast)
        _ = try await engine.search(SearchInput(question: "q", related: true))
        #expect(provider.requests.first?.kind == .newSearch)
    }

    @Test func followUpOfProviderAnswerStaysWithProviderInLocalMode() async throws {
        let (engine, local, provider) = makeEngine(mode: .aiFast, localOptIn: true)
        _ = try await engine.search(SearchInput(question: "first"))
        engine.settings.responseMode = .localFast
        _ = try await engine.search(SearchInput(question: "and then?", related: true))
        #expect(local.requests.isEmpty)
        #expect(provider.requests.last?.responseMode == .aiFast)
    }

    @Test func followUpOfLocalAnswerCanStayLocal() async throws {
        let (engine, local, _) = makeEngine(mode: .localFast, localOptIn: true)
        _ = try await engine.search(SearchInput(question: "2+2"))
        _ = try await engine.search(SearchInput(question: "times 3", related: true))
        #expect(local.requests.count == 2)
        #expect(local.requests.last?.kind == .relatedQuestion)
    }

    @Test func doubleCheckSendsPreviousLocalAnswerToProviderFast() async throws {
        let (engine, local, provider) = makeEngine(mode: .localFast, localOptIn: true)
        _ = try await engine.search(SearchInput(question: "Compare RAV4 to CR-V"))
        let result = try await engine.search(SearchInput(question: "Compare RAV4 to CR-V", doubleCheck: true))
        #expect(local.requests.count == 1)
        let request = try #require(provider.requests.first)
        #expect(request.kind == .doubleCheck)
        #expect(request.previous?.answeredBy == .localAI)
        #expect(request.responseMode == .aiFast)
        #expect(!request.useWebSearch)
        #expect(result.answeredBy == .configuredProvider)
    }

    @Test func clearPreviousForgetsContext() async throws {
        let (engine, _, provider) = makeEngine(mode: .aiFast)
        _ = try await engine.search(SearchInput(question: "first"))
        engine.clearPrevious()
        _ = try await engine.search(SearchInput(question: "second", related: true))
        #expect(provider.requests.last?.previous == nil)
    }
}

@MainActor
@Suite struct EngineResultTests {
    @Test func sourcesShownOnlyWhenWebSearchUsedOrLinksRequested() async throws {
        let (engine, _, provider) = makeEngine(mode: .aiFast)
        provider.raw = RawAnswer(text: "A", sources: [Source(title: "T", url: "https://a.example")], model: "m")
        let hidden = try await engine.search(SearchInput(question: "what is a cat"))
        #expect(!hidden.showSources)

        let asked = try await engine.search(SearchInput(question: "cat facts with links"))
        #expect(asked.showSources)

        provider.raw = RawAnswer(text: "A", sources: [Source(title: "T", url: "https://a.example")], webSearchUsed: true, model: "m")
        let searched = try await engine.search(SearchInput(question: "what is a cat"))
        #expect(searched.showSources)
    }

    @Test func duplicateSourcesAreDroppedByURL() async throws {
        let (engine, _, provider) = makeEngine(mode: .webQuick)
        provider.raw = RawAnswer(
            text: "A",
            sources: [Source(title: "One", url: "https://a.example"), Source(title: "Dup", url: " https://a.example "), Source(title: "Blank", url: "")],
            webSearchUsed: true, model: "m"
        )
        let result = try await engine.search(SearchInput(question: "q"))
        #expect(result.sources.map(\.title) == ["One"])
    }

    @Test func providerTextIsSanitized() async throws {
        let (engine, _, provider) = makeEngine(mode: .webQuick)
        provider.raw = RawAnswer(text: "tool_call: web_search({})\n\nReal answer.", model: "m")
        let result = try await engine.search(SearchInput(question: "q"))
        #expect(result.answer == "Real answer.")
    }

    @Test func emptyProviderAnswerIsAnError() async {
        let (engine, _, provider) = makeEngine()
        provider.raw = RawAnswer(text: "  \n ", model: "m")
        await #expect(throws: SearchError.self) {
            _ = try await engine.search(SearchInput(question: "q"))
        }
    }

    @Test func providerErrorsAreWrapped() async {
        let (engine, _, provider) = makeEngine()
        provider.error = URLError(.notConnectedToInternet)
        do {
            _ = try await engine.search(SearchInput(question: "q"))
            Issue.record("expected an error")
        } catch let error as SearchError {
            #expect(error.code == .providerError)
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }

    @Test func statusCallbackReceivesProgress() async throws {
        let (engine, _, _) = makeEngine()
        var messages: [String] = []
        _ = try await engine.search(SearchInput(question: "q")) { messages.append($0) }
        #expect(messages.first == "Thinking...")
        #expect(messages.contains("Searching the web..."))
    }

    @Test func tablesInAnswersAreNormalizedForDisplay() async throws {
        let (engine, _, provider) = makeEngine()
        provider.raw = RawAnswer(text: "A | B\n--- | ---\n1 | 2", model: "m")
        let result = try await engine.search(SearchInput(question: "table"))
        #expect(result.answerMarkdown.contains("| A | B |"))
    }
}
