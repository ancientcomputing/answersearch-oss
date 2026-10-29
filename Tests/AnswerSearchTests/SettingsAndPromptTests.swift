import Foundation
import Testing
@testable import AnswerSearchKit

@Suite struct SettingsTests {
    private func tempStore() -> SettingsStore {
        let dir = FileManager.default.temporaryDirectory.appending(path: "answersearch-tests-\(UUID().uuidString)")
        return SettingsStore(fileURL: dir.appending(path: "config.json"))
    }

    @Test func defaultsMatchTheProduct() {
        let settings = AppSettings()
        #expect(settings.provider == .anthropic)
        #expect(settings.model == "claude-sonnet-4-6")
        #expect(settings.responseMode == .webQuick)
        #expect(settings.shortcut == .suggested)
        #expect(!settings.automaticallyUseLocalAI)
    }

    @Test func roundTripsThroughDisk() throws {
        let store = tempStore()
        var settings = AppSettings()
        settings.provider = .openai
        settings.model = "gpt-test"
        settings.responseMode = .webDeep
        settings.userCity = "Cupertino"
        settings.shortcut = KeyboardShortcut(enabled: false, key: "k", modifiers: "option+shift")
        try store.save(settings)
        #expect(store.load() == settings)
        let attributes = try FileManager.default.attributesOfItem(atPath: store.fileURL.path(percentEncoded: false))
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }

    @Test func missingOrCorruptFileYieldsDefaults() throws {
        let store = tempStore()
        #expect(store.load() == AppSettings())
        try FileManager.default.createDirectory(at: store.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: store.fileURL)
        #expect(store.load() == AppSettings())
    }

    @Test func invalidStoredValuesFallBackIndividually() throws {
        let json = #"{"provider":"nope","model":"  ","responseMode":"bogus","webSearchMaxUses":99,"shortcut":{"enabled":true,"key":"z","modifiers":"cmd"},"userCity":"Oslo"}"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        #expect(settings.provider == .anthropic)
        #expect(settings.model == ProviderKind.anthropic.defaultModel)
        #expect(settings.responseMode == .webQuick)
        #expect(settings.webSearchMaxUses == 5)
        #expect(settings.shortcut == .suggested)
        #expect(settings.userCity == "Oslo")
    }

    @Test func deleteRemovesTheFile() throws {
        let store = tempStore()
        try store.save(AppSettings())
        #expect(store.exists)
        try store.delete()
        #expect(!store.exists)
    }

    @Test func modePresetsMatchProductBudgets() {
        #expect(ResponseMode.localFast.maxOutputTokens == 600)
        #expect(ResponseMode.aiFast.maxOutputTokens == 800)
        #expect(ResponseMode.webQuick.maxOutputTokens == 6_000)
        #expect(ResponseMode.webDeep.maxOutputTokens == 10_000)
        #expect(ResponseMode.allCases.filter(\.usesWebSearch) == [.webQuick, .webDeep])
    }

    @Test func credentialStoreKeepsKeysPerProvider() throws {
        let store = InMemoryCredentialStore()
        try store.setAPIKey("  sk-a \n", for: .anthropic)
        try store.setAPIKey("sk-o", for: .openai)
        #expect(store.apiKey(for: .anthropic) == "sk-a")
        try store.deleteAllKeys()
        #expect(store.apiKey(for: .anthropic) == nil)
        #expect(store.apiKey(for: .openai) == nil)
    }
}

@Suite struct PromptTests {
    private func request(_ mode: ResponseMode, kind: QueryKind = .newSearch, web: Bool = false, links: Bool = false,
                         previous: PreviousTransaction? = nil, location: RequestLocation = RequestLocation()) -> AnswerRequest {
        AnswerRequest(
            question: "What is \"x\"?", kind: kind, previous: previous, model: "m", responseMode: mode,
            maxOutputTokens: mode.maxOutputTokens, useWebSearch: web, webSearchMaxUses: web ? 5 : 0,
            linksRequested: links, location: location
        )
    }

    @Test func systemPromptReflectsWebAccess() {
        #expect(Prompts.system(for: request(.webQuick, web: true)).contains("Web search is available for this request."))
        #expect(Prompts.system(for: request(.aiFast)).contains("No web search is available for this request."))
    }

    @Test func systemPromptReflectsLengthAndLinks() {
        #expect(Prompts.system(for: request(.webQuick, web: true)).contains("100-200 words"))
        #expect(Prompts.system(for: request(.webDeep, web: true)).contains("500-900 words"))
        #expect(Prompts.system(for: request(.aiFast)).contains("roughly 100-300 words"))
        #expect(Prompts.system(for: request(.aiFast, links: true)).contains("explicitly asked for links or sources"))
        #expect(Prompts.system(for: request(.aiFast)).contains("Do not add links, source lists"))
    }

    @Test func systemPromptIncludesLocation() {
        let located = request(.aiFast, location: RequestLocation(city: "Oslo", country: "Norway"))
        #expect(Prompts.system(for: located).contains("Approximate user location: Oslo, Norway"))
        #expect(Prompts.system(for: request(.aiFast)).contains("Approximate user location: not configured"))
    }

    @Test func userPromptEncodesTransactionAsJSON() throws {
        let prompt = Prompts.user(for: request(.aiFast))
        let json = try #require(prompt.components(separatedBy: "\n\n").last)
        let object = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: String])
        #expect(object["mode"] == "new_search")
        #expect(object["current_query"] == "What is \"x\"?")
        #expect(object["previous_answer"] == nil)
    }

    @Test func relatedAndDoubleCheckPromptsCarryPreviousContext() throws {
        let previous = PreviousTransaction(question: "pq", answer: "pa", answeredBy: .localAI, webSearchUsed: false)
        let related = Prompts.user(for: request(.aiFast, kind: .relatedQuestion, previous: previous))
        #expect(related.contains("\"previous_answer\":\"pa\""))
        #expect(related.contains("\"mode\":\"related_question\""))
        let check = Prompts.user(for: request(.aiFast, kind: .doubleCheck, previous: previous))
        #expect(check.contains("\"mode\":\"double_check\""))
        #expect(check.contains("\"previous_answered_by\":\"local_ai\""))
        #expect(check.contains("Check previous_answer against current_query"))
    }
}

@Suite struct LocalTriageTests {
    private func decision(_ answer: String = "answer", confidence: String? = "high", category: String? = "arithmetic",
                          external: String? = "no", current: String? = "no") -> LocalPrompts.TriageDecision {
        LocalPrompts.normalizedTriage(
            decision: answer, confidence: confidence, category: category,
            requiresExternal: external, requiresCurrent: current, reason: "Simple Math!"
        )
    }

    @Test func allowsOnlyConfidentSelfContainedLocalSafeAnswers() {
        #expect(decision().allowsLocalAnswer)
        #expect(!decision("defer").allowsLocalAnswer)
        #expect(!decision(confidence: "medium").allowsLocalAnswer)
        #expect(!decision(category: "not_local_safe").allowsLocalAnswer)
        #expect(!decision(external: "yes").allowsLocalAnswer)
        #expect(!decision(current: "yes").allowsLocalAnswer)
    }

    @Test func missingFieldsDeferCautiously() {
        let missing = decision(confidence: nil, category: nil, external: nil, current: nil)
        #expect(!missing.allowsLocalAnswer)
        #expect(missing.category == "not_local_safe")
        #expect(missing.requiresCurrentInfo == "yes")
    }

    @Test func reasonIsSnakeCased() {
        #expect(decision().reason == "simple_math")
    }

    @Test func promptsCombineInstructionsAndQuestion() {
        let request = AnswerRequest(
            question: "convert 3 miles to km", model: "m", responseMode: .localFast, maxOutputTokens: 600,
            useWebSearch: false, webSearchMaxUses: 0, linksRequested: false, locale: "en-US"
        )
        let prompts = LocalPrompts(request: request)
        #expect(prompts.triage.contains("Triage the user question."))
        #expect(prompts.triage.contains("User question:\nconvert 3 miles to km"))
        #expect(prompts.answer.contains("Answer the user question."))
        #expect(prompts.triage.contains("Locale: en-US"))
        #expect(prompts.triage.contains("Stay under about 600 tokens."))
    }
}
