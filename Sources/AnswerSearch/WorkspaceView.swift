import AnswerSearchKit
import AppKit
import SwiftUI

struct WorkspaceView: View {
    @ObservedObject var viewModel: WorkspaceViewModel
    @FocusState private var composerFocused: Bool

    private let pageBackground = Color(red: 0.973, green: 0.969, blue: 0.949)
    private let textColor = Color(red: 0.09, green: 0.09, blue: 0.09)
    private let mutedColor = Color(red: 0.36, green: 0.38, blue: 0.37)
    private let accentColor = Color(red: 0.09, green: 0.42, blue: 0.53)
    private let followUpComposerID = "follow-up-composer"

    var body: some View {
        ZStack {
            pageBackground.ignoresSafeArea()
            if viewModel.result == nil && !viewModel.isSearching && viewModel.errorMessage.isEmpty {
                homeView
            } else {
                resultView
            }
        }
        .frame(minWidth: 900, minHeight: 650)
        .onAppear {
            composerFocused = true
            viewModel.loadResponseMode()
        }
    }

    private var homeView: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 130)
            shellHeader
                .padding(.bottom, 42)

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    modePicker
                    composerField(placeholder: "What do you want to know?")
                }
                .frame(width: 670)
                primarySearchButton
                    .frame(width: 104, height: 76)
                    .padding(.top, 30)
            }

            Text("AI-generated answers may contain mistakes. Verify important information.")
                .font(.system(size: 14))
                .foregroundStyle(mutedColor)
                .frame(width: 786, alignment: .leading)
                .padding(.top, 12)

            Spacer()
            footer
                .frame(width: 786, alignment: .leading)
                .padding(.bottom, 42)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var resultView: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .center) {
                            brandTitle
                            Spacer()
                            closeButton
                        }
                        .padding(.top, 56)
                        .padding(.bottom, 20)

                        if viewModel.isSearching {
                            searchingContent
                        } else if !viewModel.errorMessage.isEmpty {
                            errorContent
                        } else if let result = viewModel.result {
                            resultContent(result)
                        }
                    }
                    .frame(width: 820, alignment: .leading)
                    .padding(.bottom, viewModel.relatedMode ? 120 : 34)
                    .frame(maxWidth: .infinity)
                }
                .onChange(of: viewModel.relatedMode) {
                    guard viewModel.relatedMode else {
                        return
                    }
                    DispatchQueue.main.async {
                        withAnimation(.easeOut(duration: 0.18)) {
                            proxy.scrollTo(followUpComposerID, anchor: .bottom)
                        }
                    }
                }
            }

            if !viewModel.relatedMode {
                footer
                    .frame(width: 820, alignment: .leading)
                    .padding(.bottom, 28)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var shellHeader: some View {
        HStack(alignment: .center) {
            brandTitle
            Spacer()
            closeButton
                .padding(.top, 6)
        }
        .frame(width: 786)
    }

    private var brandTitle: some View {
        HStack(spacing: 12) {
            Image(nsImage: WorkspaceLogo.image)
                .resizable()
                .frame(width: 40, height: 40)
            Text("AnswerSearch")
                .font(.custom("Aptos Display", size: 44).weight(.heavy))
                .foregroundStyle(textColor)
                .lineLimit(1)
        }
    }

    private var closeButton: some View {
        Button("Close") {
            NSApp.keyWindow?.close()
        }
        .buttonStyle(LinkLikeButtonStyle(color: accentColor, underlined: false))
        .font(.system(size: 14, weight: .semibold))
    }

    private func composerField(placeholder: String) -> some View {
        TextField(placeholder, text: $viewModel.question, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.system(size: 18))
            .lineSpacing(4)
            .lineLimit(2...6)
            .focused($composerFocused)
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
            .frame(height: 76, alignment: .topLeading)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(accentColor.opacity(composerFocused ? 0.9 : 0.45), lineWidth: composerFocused ? 2 : 1)
            )
            .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
            .onSubmit {
                Task { await viewModel.submit() }
            }
    }

    private var primarySearchButton: some View {
        Button {
            Task { await viewModel.submit() }
        } label: {
            Text("Search")
                .font(.system(size: 17, weight: .bold))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .keyboardShortcut(.defaultAction)
        .buttonStyle(FilledSearchButtonStyle(accent: accentColor))
        .disabled(!viewModel.canSubmit)
    }

    private var modePicker: some View {
        HStack(spacing: 6) {
            Text("Answer Mode:")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(mutedColor)
            Picker("", selection: $viewModel.responseMode) {
                ForEach(viewModel.responseModeOptions, id: \.self) { mode in
                    Text(viewModel.label(for: mode)).tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 136)
            .onChange(of: viewModel.responseMode) {
                Task {
                    await viewModel.responseModeDidChange()
                }
            }
        }
        .help("Choose the Answer Mode for the next question")
    }

    private var searchingContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            questionLine(viewModel.lastQuestion)
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text(viewModel.status)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(mutedColor)
            }
            .padding(.top, 8)
        }
    }

    private var errorContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            questionLine(viewModel.lastQuestion)
            Text("Search failed")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color(red: 0.56, green: 0.18, blue: 0.18))
            Text(viewModel.errorMessage)
                .font(.system(size: 18))
                .lineSpacing(5)
                .foregroundStyle(mutedColor)
                .textSelection(.enabled)
            actionRow
        }
    }

    private func resultContent(_ result: SearchResult) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            questionLine(result.question.isEmpty ? viewModel.lastQuestion : result.question)
                .padding(.bottom, 14)

            if !viewModel.answerMetadata.isEmpty {
                Text(viewModel.answerMetadata)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(mutedColor)
                .padding(.bottom, 18)
            }

            MarkdownAnswerView(
                markdown: result.answerMarkdown,
                textColor: textColor,
                mutedColor: mutedColor
            )
                .padding(.bottom, 28)

            if !viewModel.displayedSearches.isEmpty {
                searchesBlock(viewModel.displayedSearches)
                    .padding(.bottom, 18)
            }

            if !viewModel.displayedSources.isEmpty {
                sourcesBlock(viewModel.displayedSources)
                    .padding(.bottom, 22)
            }

            Text("AI-generated answers may contain mistakes. Verify important information.")
                .font(.system(size: 13))
                .foregroundStyle(mutedColor)
                .padding(.top, 6)
                .padding(.bottom, viewModel.doubleCheckHelpText.isEmpty ? 28 : 8)

            if !viewModel.doubleCheckHelpText.isEmpty {
                Text(viewModel.doubleCheckHelpText)
                    .font(.system(size: 13))
                    .foregroundStyle(mutedColor)
                    .padding(.bottom, 28)
            }

            actionRow
        }
    }

    private func questionLine(_ question: String) -> some View {
        Text(question.isEmpty ? "Search" : question)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(mutedColor)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func searchesBlock(_ searches: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Search: \(searches.prefix(2).joined(separator: "; "))")
                .font(.system(size: 13))
                .foregroundStyle(mutedColor)
                .textSelection(.enabled)
        }
    }

    private func sourcesBlock(_ sources: [Source]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sources")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(textColor)
            ForEach(Array(sources.prefix(5).enumerated()), id: \.offset) { index, source in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(index + 1).")
                        .font(.system(size: 14))
                        .foregroundStyle(mutedColor)
                    Button(source.title.isEmpty ? source.url : source.title) {
                        viewModel.openSource(source)
                    }
                    .buttonStyle(LinkLikeButtonStyle(color: accentColor))
                    .font(.system(size: 14))
                    .lineLimit(2)
                }
            }
        }
        .padding(.top, 12)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color(red: 0.85, green: 0.84, blue: 0.80))
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private var actionRow: some View {
        if !viewModel.relatedMode {
            HStack(spacing: 10) {
                Button {
                    viewModel.copyAnswer()
                } label: {
                    Image(systemName: viewModel.copyFeedbackVisible ? "checkmark" : "doc.on.doc")
                        .frame(width: 18, height: 18)
                        .frame(width: 44, height: 42)
                }
                .buttonStyle(OutlineActionButtonStyle(accent: accentColor, isPrimary: false))
                .disabled(viewModel.result == nil)
                .help(viewModel.copyFeedbackVisible ? "Copied" : "Copy")
                .accessibilityLabel(viewModel.copyFeedbackVisible ? "Copied" : "Copy")

                Button {
                    viewModel.saveAnswer()
                } label: {
                    Image(systemName: "square.and.arrow.down")
                        .frame(width: 18, height: 18)
                        .frame(width: 44, height: 42)
                }
                .buttonStyle(OutlineActionButtonStyle(accent: accentColor, isPrimary: false))
                .disabled(viewModel.result == nil)
                .help("Save as")

                Button {
                    viewModel.askFollowUp()
                    composerFocused = true
                } label: {
                    Label("Ask a follow-up", systemImage: "questionmark")
                }
                .buttonStyle(OutlineActionButtonStyle(accent: accentColor, isPrimary: false))
                .disabled(viewModel.result == nil || viewModel.isSearching)

                if viewModel.canDoubleCheck {
                    Button {
                        Task { await viewModel.doubleCheck() }
                    } label: {
                        Label(viewModel.result?.doubleCheckLabel ?? "Double-check", systemImage: "sparkles")
                    }
                    .buttonStyle(OutlineActionButtonStyle(accent: accentColor, isPrimary: false))
                    .disabled(viewModel.isSearching)
                    .help("Asks your selected provider, without web search, to check this answer")
                }

                Button {
                    viewModel.newQuestion()
                    composerFocused = true
                } label: {
                    Label("New question", systemImage: "plus")
                }
                .buttonStyle(OutlineActionButtonStyle(accent: accentColor, isPrimary: true))
            }
            .padding(.bottom, 24)
        }

        if viewModel.relatedMode {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    modePicker
                    composerField(placeholder: "Ask a related question")
                }
                .frame(width: 670)
                primarySearchButton
                    .frame(width: 104, height: 76)
                    .padding(.top, 30)
            }
            .padding(.bottom, 20)
            .id(followUpComposerID)
        }
    }

    private var footer: some View {
        HStack(spacing: 20) {
            Text("Open source, Apache 2.0")
            Button("About") {
                open(AppLinks.project)
            }
                .buttonStyle(LinkLikeButtonStyle(color: mutedColor))
            Button("Privacy") {
                open(AppLinks.privacy)
            }
                .buttonStyle(LinkLikeButtonStyle(color: mutedColor))
            Button("Report an issue") {
                open(AppLinks.issues)
            }
                .buttonStyle(LinkLikeButtonStyle(color: mutedColor))
        }
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(mutedColor)
    }

    private func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}

private struct LinkLikeButtonStyle: ButtonStyle {
    let color: Color
    var underlined = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(color.opacity(configuration.isPressed ? 0.65 : 1))
            .underline(underlined)
            .contentShape(Rectangle())
    }
}

private struct FilledSearchButtonStyle: ButtonStyle {
    let accent: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.white)
            .background(accent.opacity(configuration.isPressed ? 0.9 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct OutlineActionButtonStyle: ButtonStyle {
    let accent: Color
    let isPrimary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(accent)
            .padding(.horizontal, 14)
            .frame(height: 42)
            .background(isPrimary ? Color(red: 0.85, green: 0.93, blue: 0.95) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .contentShape(RoundedRectangle(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(accent.opacity(configuration.isPressed ? 0.7 : 0.85), lineWidth: 1)
            )
    }
}

private enum WorkspaceLogo {
    @MainActor static var image: NSImage {
        let image = NSApp.applicationIconImage ?? MenuBarIcon.image
        image.isTemplate = false
        return image
    }
}

private struct MarkdownAnswerView: View {
    let markdown: String
    let textColor: Color
    let mutedColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(Array(MarkdownBlock.parse(markdown).enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let level, let text):
                    Text(.init(text))
                        .font(.system(size: level <= 2 ? 24 : 20, weight: .bold))
                        .lineSpacing(4)
                        .foregroundStyle(textColor)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, level <= 2 ? 4 : 0)
                case .paragraph(let text):
                    paragraph(text)
                case .list(let ordered, let items):
                    list(ordered: ordered, items: items)
                case .table(let table):
                    MarkdownTableView(table: table, textColor: textColor, mutedColor: mutedColor)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func paragraph(_ text: String) -> some View {
        Text(.init(text))
            .font(.system(size: 21))
            .lineSpacing(8)
            .foregroundStyle(textColor)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func list(ordered: Bool, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(ordered ? "\(index + 1)." : "•")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(mutedColor)
                        .frame(width: ordered ? 28 : 18, alignment: .trailing)
                    Text(.init(item))
                        .font(.system(size: 21))
                        .lineSpacing(6)
                        .foregroundStyle(textColor)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

private struct MarkdownTableView: View {
    let table: MarkdownTable
    let textColor: Color
    let mutedColor: Color

    var body: some View {
        ScrollView(.horizontal) {
            VStack(alignment: .leading, spacing: 0) {
                tableRow(table.headers, isHeader: true)
                ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                    tableRow(row, isHeader: false)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color(red: 0.85, green: 0.84, blue: 0.80), lineWidth: 1)
            )
        }
    }

    private func tableRow(_ values: [String], isHeader: Bool) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(0..<table.headers.count, id: \.self) { index in
                tableCell(
                    index < values.count ? values[index] : "",
                    isHeader: isHeader,
                    isFirstColumn: index == 0
                )
            }
        }
        .background(
            isHeader
                ? Color(red: 0.91, green: 0.95, blue: 0.96)
                : Color.white.opacity(0.58)
        )
        .overlay(alignment: .leading) {
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    ForEach(1..<table.headers.count, id: \.self) { index in
                        Rectangle()
                            .fill(Color(red: 0.85, green: 0.84, blue: 0.80))
                            .frame(width: 0.5, height: geometry.size.height)
                            .offset(x: columnOffset(for: index))
                    }
                }
            }
            .allowsHitTesting(false)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(red: 0.85, green: 0.84, blue: 0.80))
                .frame(height: 0.5)
        }
    }

    private func columnOffset(for index: Int) -> CGFloat {
        guard index > 0 else {
            return 0
        }
        return 150 + CGFloat(index - 1) * 240
    }

    private func tableCell(_ text: String, isHeader: Bool, isFirstColumn: Bool) -> some View {
        Text(.init(text.isEmpty ? " " : text))
            .font(.system(size: 15, weight: isHeader ? .bold : .regular))
            .foregroundStyle(isHeader ? textColor : mutedColor)
            .lineLimit(nil)
            .textSelection(.enabled)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(width: isFirstColumn ? 150 : 240, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private enum MarkdownBlock {
    case heading(Int, String)
    case paragraph(String)
    case list(ordered: Bool, items: [String])
    case table(MarkdownTable)

    static func parse(_ markdown: String) -> [MarkdownBlock] {
        let lines = markdown.components(separatedBy: .newlines)
        var blocks: [MarkdownBlock] = []
        var paragraphLines: [String] = []
        var index = 0

        func flushParagraph() {
            let text = paragraphLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                blocks.append(.paragraph(text))
            }
            paragraphLines.removeAll()
        }

        while index < lines.count {
            if let table = MarkdownTable.parse(lines: lines, startIndex: index) {
                flushParagraph()
                blocks.append(.table(table.table))
                index = table.nextIndex
            } else if let heading = MarkdownHeading.parse(lines[index]) {
                flushParagraph()
                blocks.append(.heading(heading.level, heading.text))
                index += 1
            } else if let list = MarkdownList.parse(lines: lines, startIndex: index) {
                flushParagraph()
                blocks.append(.list(ordered: list.ordered, items: list.items))
                index = list.nextIndex
            } else if lines[index].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                flushParagraph()
                index += 1
            } else {
                paragraphLines.append(lines[index])
                index += 1
            }
        }
        flushParagraph()
        return blocks
    }
}

private enum MarkdownHeading {
    static func parse(_ line: String) -> (level: Int, text: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        var level = 0
        for character in trimmed {
            if character == "#" {
                level += 1
            } else {
                break
            }
        }
        guard (1...6).contains(level),
              trimmed.dropFirst(level).first == " " else {
            return nil
        }
        let text = trimmed.dropFirst(level)
            .trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else {
            return nil
        }
        return (level, String(text))
    }
}

private enum MarkdownList {
    static func parse(lines: [String], startIndex: Int) -> (ordered: Bool, items: [String], nextIndex: Int)? {
        guard let first = listItem(lines[startIndex]) else {
            return nil
        }
        var items = [first.text]
        var index = startIndex + 1
        while index < lines.count {
            guard let item = listItem(lines[index]), item.ordered == first.ordered else {
                break
            }
            items.append(item.text)
            index += 1
        }
        return items.isEmpty ? nil : (first.ordered, items, index)
    }

    private static func listItem(_ line: String) -> (ordered: Bool, text: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
            let text = trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces)
            return text.isEmpty ? nil : (false, String(text))
        }
        guard let dotIndex = trimmed.firstIndex(of: ".") else {
            return nil
        }
        let marker = trimmed[..<dotIndex]
        guard !marker.isEmpty,
              marker.allSatisfy(\.isNumber),
              trimmed.index(after: dotIndex) < trimmed.endIndex,
              trimmed[trimmed.index(after: dotIndex)] == " " else {
            return nil
        }
        let text = trimmed[trimmed.index(after: dotIndex)...]
            .trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : (true, String(text))
    }
}

private struct MarkdownTable {
    let headers: [String]
    let rows: [[String]]

    static func parse(lines: [String], startIndex: Int) -> (table: MarkdownTable, nextIndex: Int)? {
        guard startIndex + 1 < lines.count else {
            return nil
        }
        let header = cells(in: lines[startIndex])
        let separator = cells(in: lines[startIndex + 1])
        guard header.count >= 2,
              separator.count == header.count,
              separator.allSatisfy(isSeparatorCell) else {
            return nil
        }

        var rows: [[String]] = []
        var index = startIndex + 2
        while index < lines.count {
            let row = cells(in: lines[index])
            guard row.count == header.count else {
                break
            }
            rows.append(row)
            index += 1
        }

        guard !rows.isEmpty else {
            return nil
        }
        return (MarkdownTable(headers: header, rows: rows), index)
    }

    private static func cells(in line: String) -> [String] {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("|") else {
            return []
        }
        let content = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "|"))
        var cells: [String] = []
        var cell = ""
        var escaped = false
        for character in content {
            if escaped {
                cell.append(character)
                escaped = false
            } else if character == "\\" {
                cell.append(character)
                escaped = true
            } else if character == "|" {
                cells.append(cell.trimmingCharacters(in: .whitespacesAndNewlines))
                cell = ""
            } else {
                cell.append(character)
            }
        }
        cells.append(cell.trimmingCharacters(in: .whitespacesAndNewlines))
        return cells
    }

    private static func isSeparatorCell(_ cell: String) -> Bool {
        let stripped = cell.replacingOccurrences(of: ":", with: "")
        return stripped.count >= 3 && stripped.allSatisfy { $0 == "-" }
    }
}
