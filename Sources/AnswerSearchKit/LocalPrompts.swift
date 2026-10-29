import Foundation

/// Prompt text and triage rules for the on-device model. Kept free of FoundationModels types so
/// it can be unit-tested.
public struct LocalPrompts {
    public let triage: String
    public let answer: String

    public init(request: AnswerRequest) {
        let tokenHint = "Stay under about \(request.maxOutputTokens) tokens."
        let timeHint = Self.timeContext(request)
        let locationHint = Self.locationContext(request.location)
        let relatedHint = Self.relatedContext(request)

        let triageInstructions = """
        You are AnswerSearch's private on-device triage and answer assistant.
        Default to defer to the configured provider.
        The provided locale and time are for interpreting the user's wording and deciding whether to defer. They do not make current facts answerable locally.
        Answer locally only when all of these are true:
        1. The question is self-contained, or the provided previous question and answer make it self-contained.
        2. The answer can be produced from the prompt, previous context, deterministic calculation, user-supplied text, or stable non-current general knowledge in an allowed local-safe category.
        3. The answer does not require freshness, verification, sources, personal or account data, professional judgment, external tools, or web access.
        4. You are highly confident.
        This triage call does not answer the user. It only decides whether local answering is allowed.
        When a local answer is allowed, answer in the same language as the user's question unless the user asks for another language.
        Choose exactly one category:
        arithmetic: numeric calculation using values supplied in the prompt or previous context.
        unit_conversion: converting supplied values between units.
        stable_school_science: widely taught elementary or secondary-school science facts that are stable, non-current, non-controversial, and do not depend on date, location, measurement conditions, source version, observation, or specialized professional judgment.
        simple_definition: concise definitions of stable, non-current common terms or concepts.
        simple_explanation: short explanations of stable, non-current common concepts at a general audience level.
        user_text_transformation: rewriting, summarizing, formatting, or transforming text supplied by the user without adding outside facts.
        not_local_safe: anything else.
        The local-safe categories are exhaustive. If the question does not clearly fit one of the local-safe categories, choose not_local_safe and defer.
        Treat product facts, specs, current events, schedules, weather, prices, news, personal/account data, and source-dependent claims as not_local_safe unless the needed information is supplied in the prompt.
        Set requires_external_info to "yes" if a good answer would depend on facts outside the prompt/context and outside the stable non-current general knowledge allowed by the selected local-safe category.
        Set requires_current_info to "yes" if the wording asks for, implies, or may require recency, freshness, current state, schedules, availability, status, prices, releases, rankings, forecasts, conditions, dates, versions, or which thing is newest/latest/next/current.
        Treat likely misspellings, variants, or paraphrases of time-sensitive words as current-info requests. Examples include latest, lateset, newest, current, recent, recently, today, now, this week, this month, this year, upcoming, next, still, available, released, price, specs, schedule, forecast, status, match, game, event, version.
        Defer stable_school_science, simple_definition, and simple_explanation if the answer depends on current observations, recent discoveries, exact source/version wording, measurement conditions, location, date, pressure, temperature, disputed facts, health advice, legal/regulatory facts, or professional judgment.
        If any condition is false or unclear, defer.
        For follow-ups, use the previous answer provenance. If the previous answer came from the configured provider or used web search, defer unless the follow-up is independently answerable as a local-safe task without relying on those provider or web facts.
        Use decision "answer" only when confidence is "high".
        Keep reason to a short category-style code, without computed values or answer text.
        \(tokenHint)
        \(timeHint)
        \(locationHint)
        \(relatedHint)
        """

        let answerInstructions = """
        You are AnswerSearch's private on-device assistant.
        The question has already been triaged as safe for a concise local answer.
        Answer directly using only the prompt and previous context.
        Reply in the same language as the user's question unless the user asks for another language.
        Do not translate the user's question into a different language before answering.
        Do not add citations, links, current claims, or external facts.
        \(tokenHint)
        \(timeHint)
        \(locationHint)
        \(relatedHint)
        """

        // Instructions and question are combined into one prompt; this reads more reliably with the
        // on-device model than separate session instructions.
        triage = """
        \(triageInstructions)

        Triage the user question.

        User question:
        \(request.question)
        """
        answer = """
        \(answerInstructions)

        Answer the user question.

        User question:
        \(request.question)
        """
    }

    // MARK: Triage decision

    public struct TriageDecision: Equatable, Sendable {
        public var decision: String
        public var confidence: String
        public var category: String
        public var requiresExternalInfo: String
        public var requiresCurrentInfo: String
        public var reason: String

        /// Local answering is allowed only when every safety condition holds.
        public var allowsLocalAnswer: Bool {
            decision == "answer" && confidence == "high"
                && requiresExternalInfo == "no" && requiresCurrentInfo == "no"
                && LocalPrompts.localSafeCategories.contains(category)
        }
    }

    static let localSafeCategories: Set<String> = [
        "arithmetic", "unit_conversion", "stable_school_science",
        "simple_definition", "simple_explanation", "user_text_transformation",
    ]

    /// Missing or unrecognized values resolve to the cautious option (defer / low / yes).
    public static func normalizedTriage(
        decision: String, confidence: String?, category: String?,
        requiresExternal: String?, requiresCurrent: String?, reason: String?
    ) -> TriageDecision {
        let normalizedDecision = decision.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "answer" ? "answer" : "defer"
        let normalizedConfidence = ["high", "medium", "low"].contains(clean(confidence)) ? clean(confidence) : "low"
        let normalizedCategory = snakeCase(category ?? "").isEmpty || category == nil ? "not_local_safe" : snakeCase(category ?? "")
        func yesNo(_ value: String?) -> String { clean(value) == "no" ? "no" : "yes" }
        let fallbackReason = normalizedDecision == "answer" ? "local_high_confidence" : "local_deferred"
        return TriageDecision(
            decision: normalizedDecision,
            confidence: normalizedConfidence,
            category: normalizedCategory,
            requiresExternalInfo: yesNo(requiresExternal),
            requiresCurrentInfo: yesNo(requiresCurrent),
            reason: snakeCase(reason ?? fallbackReason)
        )
    }

    private static func clean(_ value: String?) -> String {
        (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func snakeCase(_ value: String) -> String {
        let mapped = value.lowercased().unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : "_"
        }
        let collapsed = String(mapped).split(separator: "_").joined(separator: "_")
        if collapsed.isEmpty { return "unspecified" }
        return String(collapsed.prefix(96))
    }

    // MARK: Context blocks

    private static func timeContext(_ request: AnswerRequest) -> String {
        let utc = ISO8601DateFormatter()
        let local = ISO8601DateFormatter()
        local.timeZone = .current
        let locale = request.locale.trimmingCharacters(in: .whitespacesAndNewlines)
        return """
        Request context:
        Locale: \(locale.isEmpty ? "unknown" : locale)
        Local time: \(local.string(from: request.now))
        UTC time: \(utc.string(from: request.now))
        """
    }

    private static func locationContext(_ location: RequestLocation) -> String {
        let place = [location.city, location.region, location.country]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        let timezone = location.timezone.trimmingCharacters(in: .whitespacesAndNewlines)
        if place.isEmpty && timezone.isEmpty { return "" }
        if timezone.isEmpty { return "User location context: \(place)." }
        if place.isEmpty { return "User timezone context: \(timezone)." }
        return "User location context: \(place), timezone \(timezone)."
    }

    private static func relatedContext(_ request: AnswerRequest) -> String {
        guard request.kind == .relatedQuestion else { return "" }
        guard let previous = request.previous else {
            return "This is marked as a related question, but no previous context was provided."
        }
        return """
        Previous question: \(previous.question)
        Previous answer: \(previous.answer)
        Previous answer source: \(previous.answeredBy.rawValue)
        Previous answer used web search: \(previous.webSearchUsed ? "true" : "false")
        """
    }
}
