import Foundation

/// Plain-text export of an answer ("Save as...").
public enum AnswerExport {
    public static func text(for result: SearchResult, fallbackQuestion: String = "", now: Date = Date()) -> String {
        var lines: [String] = []
        let question = (result.question.isEmpty ? fallbackQuestion : result.question)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !question.isEmpty {
            lines.append(contentsOf: ["Question", question, ""])
        }
        lines.append(contentsOf: ["Answer", result.answer.trimmingCharacters(in: .whitespacesAndNewlines), ""])

        let searches = Array(uniqueTrimmed(result.searches).prefix(2))
        if !searches.isEmpty {
            lines.append("Searches")
            lines.append(contentsOf: searches.map { "- \($0)" })
            lines.append("")
        }

        let sources = Array(result.sources.prefix(5))
        if !sources.isEmpty {
            lines.append("References")
            for (index, source) in sources.enumerated() {
                let title = source.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let url = source.url.trimmingCharacters(in: .whitespacesAndNewlines)
                lines.append("\(index + 1). \(title.isEmpty ? url : title)")
                if !title.isEmpty, !url.isEmpty {
                    lines.append("   \(url)")
                }
                if let cited = source.citedText?.trimmingCharacters(in: .whitespacesAndNewlines), !cited.isEmpty {
                    lines.append("   \(cited)")
                }
            }
            lines.append("")
        }

        lines.append("Saved from AnswerSearch on \(now.formatted(date: .abbreviated, time: .shortened))")
        return lines.joined(separator: "\n") + "\n"
    }

    public static func suggestedFilename(for question: String) -> String {
        let words = question
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .prefix(8)
            .joined(separator: "-")
        return "\(words.isEmpty ? "answersearch-answer" : words).txt"
    }

    public static func uniqueTrimmed(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var unique: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
            unique.append(trimmed)
        }
        return unique
    }
}
