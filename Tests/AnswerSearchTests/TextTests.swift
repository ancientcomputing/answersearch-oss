import Testing
@testable import AnswerSearchKit

@Suite struct AnswerTextTests {
    @Test func sanitizeRemovesToolTraceLines() {
        let raw = """
        tool_call: web_search({"query":"weather today San Jose California"})

        tool_response: {"results":[{"title":"Weather in San Jose","url":"https://www.weatherapi.com/"}]}

        Currently in San Jose, CA, it's 64°F with clear skies.

        For the rest of the day, expect a high near 86°F.
        """
        let cleaned = AnswerText.sanitize(raw)
        #expect(!cleaned.contains("tool_call:"))
        #expect(!cleaned.contains("tool_response:"))
        #expect(cleaned.contains("Currently in San Jose"))
        #expect(cleaned.contains("high near 86"))
    }

    @Test func sanitizeLeavesNormalAnswerAlone() {
        let raw = "First paragraph.\n\nSecond paragraph."
        #expect(AnswerText.sanitize(raw) == raw)
    }

    @Test func sanitizeRemovesToolSlashTraceAndSearchChatter() {
        let raw = """
        tools/web_search("Toyota Corolla SR")
        Results:
        Toyota Corolla SR appears in search results related to older Corolla trim levels.

        Let me search more specifically.
        tools/web_search("Toyota Corolla SR trim level specs")

        The Toyota Corolla SR is a sport-oriented trim name used in some markets.
        """
        #expect(AnswerText.sanitize(raw) == "The Toyota Corolla SR is a sport-oriented trim name used in some markets.")
    }

    @Test func cleanLocalAnswerRemovesResponseFormatPreamble() {
        #expect(AnswerText.cleanLocalAnswer("response_format: Text\n\n\"2+2 equals 4.\"") == "2+2 equals 4.")
    }

    @Test func cleanLocalAnswerLeavesQuotedAnswersAlone() {
        #expect(AnswerText.cleanLocalAnswer("\"Yes\" is the quoted word.") == "\"Yes\" is the quoted word.")
    }

    @Test func cleanLocalAnswerRemovesRepeatedPreambleLines() {
        #expect(AnswerText.cleanLocalAnswer("response_format: Text\nresponse_format: Text\nAnswer") == "Answer")
    }
}

@Suite struct LinkIntentTests {
    @Test(arguments: [
        ("Give me sources for this claim", true),
        ("include useful links about this", true),
        ("what is a binary search tree", false),
    ])
    func detectsLinkRequests(question: String, expected: Bool) {
        #expect(LinkIntent.isLinkRequest(question) == expected)
    }
}

@Suite struct ExportTests {
    @Test func filenameUsesFirstEightWords() {
        #expect(AnswerExport.suggestedFilename(for: "What is the capital of France, really? Tell me now please")
            == "what-is-the-capital-of-france-really-tell.txt")
        #expect(AnswerExport.suggestedFilename(for: "???") == "answersearch-answer.txt")
    }

    @Test func exportIncludesQuestionAnswerSearchesAndReferences() {
        let result = SearchResult(
            question: "Q?", answer: "A.", answerMarkdown: "A.",
            sources: [Source(title: "Site", url: "https://example.com", citedText: "quote")],
            showSources: true, webSearchUsed: true, searches: ["one", "one", "two", "three"],
            answeredBy: .configuredProvider, responseMode: .webQuick
        )
        let text = AnswerExport.text(for: result)
        #expect(text.contains("Question\nQ?"))
        #expect(text.contains("Answer\nA."))
        #expect(text.contains("- one\n- two\n"))
        #expect(!text.contains("- three"))
        #expect(text.contains("1. Site\n   https://example.com\n   quote"))
    }
}
