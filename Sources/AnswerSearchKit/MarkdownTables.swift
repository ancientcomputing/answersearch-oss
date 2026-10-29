import Foundation

/// Models sometimes emit pipe tables whose rows are split across lines or have stray `|`
/// delimiters. This repairs such tables into well-formed GitHub-style tables before rendering.
public enum MarkdownTables {
    public static func normalize(_ markdown: String) -> String {
        let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var normalized: [String] = []
        var inFence = false
        var i = 0
        while i < lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                inFence.toggle()
                normalized.append(lines[i])
                i += 1
                continue
            }
            if inFence {
                normalized.append(lines[i])
                i += 1
                continue
            }
            if isTableHeader(lines, i) {
                let (tableLines, next) = normalizeBlock(lines, i)
                normalized.append(contentsOf: tableLines)
                i = next
                continue
            }
            normalized.append(lines[i])
            i += 1
        }
        return normalized.joined(separator: "\n")
    }

    // MARK: Detection

    private static func isTableHeader(_ lines: [String], _ index: Int) -> Bool {
        index + 1 < lines.count && isRow(lines[index]) && isSeparator(lines[index + 1])
    }

    static func isRow(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed == "|" { return false }
        if trimmed.hasPrefix("|") && trimmed.hasSuffix("|") {
            return trimmed.filter { $0 == "|" }.count >= 2
        }
        return splitCells(trimmed).count >= 2 && trimmed.contains("|")
    }

    static func isSeparator(_ line: String) -> Bool {
        guard isRow(line) else { return false }
        return splitCells(line).allSatisfy { $0.trimmingCharacters(in: CharacterSet(charactersIn: " :-")).isEmpty }
    }

    static func splitCells(_ line: String) -> [String] {
        let trimmed = line.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "|"))
        var cells: [String] = []
        var cell = ""
        var escaped = false
        for character in trimmed {
            if escaped {
                cell.append(character)
                escaped = false
            } else if character == "\\" {
                cell.append(character)
                escaped = true
            } else if character == "|" {
                cells.append(cell.trimmingCharacters(in: .whitespaces))
                cell = ""
            } else {
                cell.append(character)
            }
        }
        cells.append(cell.trimmingCharacters(in: .whitespaces))
        return cells
    }

    private static func isListLine(_ line: String) -> Bool {
        if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") { return true }
        guard let range = line.range(of: ". "), range.lowerBound != line.startIndex else { return false }
        return line[..<range.lowerBound].allSatisfy { $0 >= "0" && $0 <= "9" }
    }

    private static func formatRow(_ cells: [String]) -> String {
        "| " + cells.joined(separator: " | ") + " |"
    }

    /// Strips one trailing unescaped `|`; returns nil when the line does not end in one.
    private static func trimTrailingDelimiter(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasSuffix("|") else { return nil }
        var backslashes = 0
        var index = trimmed.index(before: trimmed.endIndex)
        while index > trimmed.startIndex {
            index = trimmed.index(before: index)
            if trimmed[index] == "\\" { backslashes += 1 } else { break }
        }
        if backslashes % 2 == 1 { return nil }
        return String(trimmed.dropLast()).trimmingCharacters(in: .whitespaces)
    }

    private static func nextNonEmptyIsTableLike(_ lines: [String], from start: Int) -> Bool {
        for i in start..<max(start, lines.count) {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            return isRow(trimmed) || trimmed == "|"
        }
        return false
    }

    private static func skipDelimiters(_ lines: [String], from start: Int) -> Int {
        var i = start
        while i < lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty && nextNonEmptyIsTableLike(lines, from: i + 1) {
                i += 1
                continue
            }
            if trimmed == "|" {
                i += 1
                continue
            }
            return i
        }
        return i
    }

    private static func hasUnterminatedLastCell(_ lines: [String], _ rowIndex: Int) -> Bool {
        let row = lines[rowIndex].trimmingCharacters(in: .whitespaces)
        guard row.hasPrefix("|"), !row.hasSuffix("|") else { return false }
        for i in (rowIndex + 1)..<max(rowIndex + 1, lines.count) {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            if trimmed == "|" { return true }
            if isRow(trimmed) || trimmed.hasPrefix("#") || isListLine(trimmed) { return false }
            if trimTrailingDelimiter(trimmed) != nil { return true }
        }
        return false
    }

    private static func trailingContinuation(_ lines: [String], from start: Int) -> (String, Int)? {
        var parts: [String] = []
        for i in start..<max(start, lines.count) {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            if trimmed == "|" {
                return parts.isEmpty ? nil : (parts.joined(separator: " "), i + 1)
            }
            if isRow(trimmed) || trimmed.hasPrefix("#") || isListLine(trimmed) { return nil }
            if let continuation = trimTrailingDelimiter(trimmed) {
                if !continuation.isEmpty { parts.append(continuation) }
                return parts.isEmpty ? nil : (parts.joined(separator: " "), i + 1)
            }
            parts.append(trimmed)
        }
        return nil
    }

    private static func fit(_ input: [String], to columnCount: Int) -> [String] {
        var cells = input
        while cells.count > columnCount {
            guard let empty = cells.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).isEmpty }) else { break }
            cells.remove(at: empty)
        }
        if cells.count <= columnCount { return cells }
        var fitted = Array(cells[..<(columnCount - 1)])
        fitted.append(cells[(columnCount - 1)...].joined(separator: " \\| "))
        return fitted
    }

    // MARK: Normalization

    private static func normalizeBlock(_ lines: [String], _ start: Int) -> ([String], Int) {
        let headerCells = splitCells(lines[start])
        let columnCount = headerCells.count
        var separatorCells = splitCells(lines[start + 1])
        while separatorCells.count < columnCount { separatorCells.append("---") }
        var tableLines = [formatRow(headerCells), formatRow(Array(separatorCells[..<columnCount]))]

        var i = start + 2
        while i < lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                if nextNonEmptyIsTableLike(lines, from: i + 1) {
                    i += 1
                    continue
                }
                return (tableLines, i)
            }
            if !isRow(trimmed) { return (tableLines, i) }

            var cells = splitCells(lines[i])
            var pendingCellLines: [String] = []
            if hasUnterminatedLastCell(lines, i), !cells.isEmpty {
                pendingCellLines.append(cells.removeLast())
            }
            if cells.count >= columnCount {
                cells = fit(cells, to: columnCount)
                var next = i + 1
                if let (continuation, continuationNext) = trailingContinuation(lines, from: next) {
                    cells[columnCount - 1] = (cells[columnCount - 1] + " " + continuation).trimmingCharacters(in: .whitespaces)
                    next = continuationNext
                }
                tableLines.append(formatRow(cells))
                i = skipDelimiters(lines, from: next)
                continue
            }

            var next = i + 1
            while cells.count < columnCount && next < lines.count {
                let nextTrimmed = lines[next].trimmingCharacters(in: .whitespaces)
                if nextTrimmed.isEmpty {
                    next += 1
                    continue
                }
                if nextTrimmed == "|" {
                    if !pendingCellLines.isEmpty {
                        cells.append(pendingCellLines.joined(separator: " "))
                        pendingCellLines.removeAll()
                    }
                    next += 1
                    continue
                }
                if isRow(nextTrimmed) {
                    if !pendingCellLines.isEmpty {
                        cells.append(pendingCellLines.joined(separator: " "))
                        pendingCellLines.removeAll()
                    }
                    let nextCells = splitCells(nextTrimmed)
                    if nextCells.count > 1 && cells.count + nextCells.count > columnCount { break }
                    cells.append(contentsOf: nextCells)
                    next += 1
                    continue
                }
                if nextTrimmed.hasPrefix("#") || isListLine(nextTrimmed) { break }
                if let continuation = trimTrailingDelimiter(nextTrimmed) {
                    if !continuation.isEmpty { pendingCellLines.append(continuation) }
                    cells.append(pendingCellLines.joined(separator: " "))
                    pendingCellLines.removeAll()
                    next += 1
                    continue
                }
                pendingCellLines.append(nextTrimmed)
                next += 1
            }
            if cells.count < columnCount { return (tableLines, i) }
            tableLines.append(formatRow(Array(cells[..<columnCount])))
            i = skipDelimiters(lines, from: next)
        }
        return (tableLines, lines.count)
    }
}
