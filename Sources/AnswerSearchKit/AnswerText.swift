import Foundation

/// Cleanup applied to model output before it is shown.
public enum AnswerText {
    /// Removes tool-call traces and search-process chatter that some providers leak into prose.
    public static func sanitize(_ answer: String) -> String {
        let lines = answer.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var cleaned: [String] = []
        var skippingToolResults = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = trimmed.lowercased()
            if isToolTraceLine(lower) {
                skippingToolResults = true
                continue
            }
            if skippingToolResults {
                if trimmed.isEmpty {
                    skippingToolResults = false
                    cleaned.append(line)
                    continue
                }
                if lower == "results:" || lower.hasPrefix("result:") {
                    skippingToolResults = true
                }
                continue
            }
            if isSearchProcessLine(lower) { continue }
            cleaned.append(line)
        }
        return collapseBlankLines(cleaned).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Removes the `response_format: ...` preamble Apple's on-device model sometimes echoes.
    public static func cleanLocalAnswer(_ answer: String) -> String {
        var cleaned = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        var hadResponseFormat = false
        while true {
            let (line, rest) = splitFirstLine(cleaned)
            guard isResponseFormatLine(line) else { break }
            hadResponseFormat = true
            guard let rest else {
                cleaned = ""
                break
            }
            cleaned = rest.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if hadResponseFormat {
            cleaned = unquote(cleaned)
        }
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func splitFirstLine(_ text: String) -> (String, String?) {
        guard let newline = text.firstIndex(of: "\n") else { return (text, nil) }
        return (String(text[..<newline]), String(text[text.index(after: newline)...]))
    }

    private static func isResponseFormatLine(_ line: String) -> Bool {
        guard let colon = line.firstIndex(of: ":") else { return false }
        let key = line[..<colon].trimmingCharacters(in: .whitespaces)
        let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        return key.caseInsensitiveCompare("response_format") == .orderedSame && !value.isEmpty
    }

    private static func unquote(_ answer: String) -> String {
        guard answer.count >= 2, answer.hasPrefix("\""), answer.hasSuffix("\"") else { return answer }
        // Decode as a JSON string so escapes such as \n are restored.
        if let data = answer.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(String.self, from: data) {
            return decoded
        }
        return answer.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    }

    private static func isToolTraceLine(_ lower: String) -> Bool {
        if lower.hasPrefix("tool_call:") || lower.hasPrefix("tool_response:")
            || lower.hasPrefix("tool:") || lower.hasPrefix("query:") {
            return true
        }
        if lower.hasPrefix("tools/") && lower.contains("(") { return true }
        return lower.hasPrefix("server_tool_use") || lower.hasPrefix("tool_use")
    }

    private static func isSearchProcessLine(_ lower: String) -> Bool {
        lower.hasPrefix("let me search") || lower.hasPrefix("i'll search")
            || lower.hasPrefix("i will search") || lower.hasPrefix("searching the web")
    }

    private static func collapseBlankLines(_ lines: [String]) -> String {
        var result: [String] = []
        var blankSeen = false
        for line in lines {
            if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if blankSeen { continue }
                blankSeen = true
            } else {
                blankSeen = false
            }
            result.append(line)
        }
        return result.joined(separator: "\n")
    }
}
