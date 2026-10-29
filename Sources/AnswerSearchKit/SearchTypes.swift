import Foundation

public enum QueryKind: String, Sendable {
    case newSearch = "new_search"
    case relatedQuestion = "related_question"
    case doubleCheck = "double_check"
}

public enum AnsweredBy: String, Sendable {
    case localAI = "local_ai"
    case configuredProvider = "configured_provider"
}

/// The one previous question/answer a follow-up may use as context. AnswerSearch keeps no
/// longer history by design.
public struct PreviousTransaction: Equatable, Sendable {
    public var question: String
    public var answer: String
    public var answeredBy: AnsweredBy
    public var webSearchUsed: Bool

    public init(question: String, answer: String, answeredBy: AnsweredBy, webSearchUsed: Bool) {
        self.question = question
        self.answer = answer
        self.answeredBy = answeredBy
        self.webSearchUsed = webSearchUsed
    }
}

/// Provider-neutral description of one answer request.
public struct AnswerRequest: Equatable, Sendable {
    public var question: String
    public var kind: QueryKind = .newSearch
    public var previous: PreviousTransaction?
    public var model: String
    public var responseMode: ResponseMode
    public var maxOutputTokens: Int
    public var useWebSearch: Bool
    public var webSearchMaxUses: Int
    public var linksRequested: Bool
    public var location: RequestLocation
    public var locale: String
    public var now: Date

    public init(
        question: String,
        kind: QueryKind = .newSearch,
        previous: PreviousTransaction? = nil,
        model: String,
        responseMode: ResponseMode,
        maxOutputTokens: Int,
        useWebSearch: Bool,
        webSearchMaxUses: Int,
        linksRequested: Bool,
        location: RequestLocation = RequestLocation(),
        locale: String = "",
        now: Date = Date()
    ) {
        self.question = question
        self.kind = kind
        self.previous = previous
        self.model = model
        self.responseMode = responseMode
        self.maxOutputTokens = maxOutputTokens
        self.useWebSearch = useWebSearch
        self.webSearchMaxUses = webSearchMaxUses
        self.linksRequested = linksRequested
        self.location = location
        self.locale = locale
        self.now = now
    }

    /// The same request downgraded to the provider's "Fast AI" behavior: short, no web search, no links.
    public var providerFast: AnswerRequest {
        var copy = self
        copy.responseMode = .aiFast
        copy.maxOutputTokens = ResponseMode.aiFast.maxOutputTokens
        copy.useWebSearch = false
        copy.webSearchMaxUses = 0
        copy.linksRequested = false
        return copy
    }
}

public struct Source: Equatable, Hashable, Sendable {
    public var title: String
    public var url: String
    public var citedText: String?

    public init(title: String, url: String, citedText: String? = nil) {
        self.title = title
        self.url = url
        self.citedText = citedText
    }
}

/// What a provider (or the on-device model) hands back, before the product adds labels and routing info.
public struct RawAnswer: Equatable, Sendable {
    public var text: String
    public var sources: [Source] = []
    public var searches: [String] = []
    public var webSearchUsed = false
    public var model: String

    public init(text: String, sources: [Source] = [], searches: [String] = [], webSearchUsed: Bool = false, model: String) {
        self.text = text
        self.sources = sources
        self.searches = searches
        self.webSearchUsed = webSearchUsed
        self.model = model
    }
}

public struct SearchResult: Equatable, Sendable {
    public var question: String
    public var answer: String
    public var answerMarkdown: String
    public var sources: [Source]
    public var showSources: Bool
    public var webSearchUsed: Bool
    public var searches: [String]
    public var model: String
    public var answeredBy: AnsweredBy
    public var answeredByLabel: String
    public var doubleCheckLabel: String
    public var responseMode: ResponseMode

    public init(
        question: String, answer: String, answerMarkdown: String, sources: [Source] = [],
        showSources: Bool = false, webSearchUsed: Bool = false, searches: [String] = [],
        model: String = "", answeredBy: AnsweredBy, answeredByLabel: String = "",
        doubleCheckLabel: String = "", responseMode: ResponseMode
    ) {
        self.question = question
        self.answer = answer
        self.answerMarkdown = answerMarkdown
        self.sources = sources
        self.showSources = showSources
        self.webSearchUsed = webSearchUsed
        self.searches = searches
        self.model = model
        self.answeredBy = answeredBy
        self.answeredByLabel = answeredByLabel
        self.doubleCheckLabel = doubleCheckLabel
        self.responseMode = responseMode
    }
}

public struct SearchError: LocalizedError, Equatable, Sendable {
    public enum Code: String, Sendable {
        case invalidRequest = "invalid_request"
        case configurationRequired = "configuration_required"
        case providerError = "provider_error"
        case cancelled
    }

    public let code: Code
    public let message: String

    public init(_ code: Code, _ message: String) {
        self.code = code
        self.message = message
    }

    public var errorDescription: String? { message }
}
