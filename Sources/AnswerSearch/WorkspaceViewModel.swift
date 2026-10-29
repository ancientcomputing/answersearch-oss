import AnswerSearchKit
import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class WorkspaceViewModel: ObservableObject {
    @Published var question = ""
    @Published var relatedMode = false
    @Published private(set) var status = "Ready"
    @Published private(set) var isSearching = false
    @Published private(set) var result: SearchResult?
    @Published private(set) var errorMessage = ""
    @Published private(set) var lastQuestion = ""
    @Published var responseMode: ResponseMode = .default
    @Published private(set) var responseModeOptions: [ResponseMode] = [.aiFast, .webQuick, .webDeep]
    @Published private(set) var copyFeedbackVisible = false

    private let appState: AppState
    private var searchGeneration = 0
    private var isApplyingConfig = false
    private var settingsObserverTask: Task<Void, Never>?
    private var copyFeedbackTask: Task<Void, Never>?

    init(appState: AppState) {
        self.appState = appState
        loadResponseMode()
        settingsObserverTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .answerSearchSettingsDidChange) {
                guard !Task.isCancelled else { return }
                self?.loadResponseMode()
            }
        }
    }

    deinit {
        settingsObserverTask?.cancel()
        copyFeedbackTask?.cancel()
    }

    var canSubmit: Bool {
        !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSearching
    }

    func label(for mode: ResponseMode) -> String {
        mode.label
    }

    var canDoubleCheck: Bool {
        guard let result else { return false }
        return result.answeredBy == .localAI && AppState.providerAnswersAvailable && appState.hasAPIKey
    }

    var doubleCheckHelpText: String {
        guard canDoubleCheck, let label = result?.doubleCheckLabel, !label.isEmpty else { return "" }
        return "\(label) without web search."
    }

    var displayedSources: [Source] {
        result?.showSources == true ? result?.sources ?? [] : []
    }

    var displayedSearches: [String] {
        uniqueTrimmedValues(result?.searches ?? [])
    }

    var answerMetadata: String {
        guard let result else { return "" }
        var parts: [String] = []
        if !result.answeredByLabel.isEmpty {
            parts.append(result.answeredByLabel)
        }
        if !result.model.isEmpty {
            parts.append(result.model)
        }
        if result.webSearchUsed {
            parts.append("Web search used")
        }
        return parts.joined(separator: " | ")
    }

    func loadResponseMode() {
        isApplyingConfig = true
        responseModeOptions = appState.availableModes
        responseMode = appState.effectiveMode(appState.settings.responseMode)
        isApplyingConfig = false
    }

    func responseModeDidChange() async {
        guard !isApplyingConfig else { return }
        let mode = responseMode
        do {
            try appState.update { $0.responseMode = mode }
        } catch {
            status = "Mode not saved"
        }
    }

    func submit() async {
        await submit(related: relatedMode, doubleCheck: false)
    }

    func askFollowUp() {
        relatedMode = true
        question = ""
        status = "Follow-up"
    }

    func newQuestion() {
        loadResponseMode()
        resetToQuestionPage(invalidateSearch: false)
    }

    func resetToQuestionPage() {
        resetToQuestionPage(invalidateSearch: true)
    }

    private func resetToQuestionPage(invalidateSearch: Bool) {
        if invalidateSearch {
            searchGeneration += 1
            isSearching = false
        }
        relatedMode = false
        question = ""
        result = nil
        errorMessage = ""
        lastQuestion = ""
        status = "Ready"
    }

    func doubleCheck() async {
        let previousQuestion = (result?.question ?? lastQuestion).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !previousQuestion.isEmpty, !isSearching else { return }
        question = previousQuestion
        relatedMode = false
        await submit(related: false, doubleCheck: true)
    }

    private func submit(related: Bool, doubleCheck: Bool) async {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSearching else { return }
        isSearching = true
        result = nil
        errorMessage = ""
        lastQuestion = trimmed
        status = "Thinking..."
        searchGeneration += 1
        let generation = searchGeneration
        defer {
            if searchGeneration == generation {
                isSearching = false
            }
        }

        do {
            let locale = Locale.current.identifier.replacingOccurrences(of: "_", with: "-")
            let input = SearchInput(question: trimmed, related: related, doubleCheck: doubleCheck, locale: locale)
            let answer = try await appState.engine.search(input) { [weak self] message in
                guard let self, self.searchGeneration == generation else { return }
                self.status = message
            }
            guard searchGeneration == generation else { return }
            result = answer
            if answer.answeredBy == .configuredProvider, answer.responseMode == .aiFast {
                responseMode = .aiFast
            }
            question = ""
            relatedMode = false
            status = "Done"
        } catch {
            guard searchGeneration == generation else { return }
            errorMessage = error.localizedDescription
            status = "Failed"
        }
    }

    func copyAnswer() {
        guard let answer = result?.answer else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(answer, forType: .string)
        status = "Copied"
        copyFeedbackVisible = true
        copyFeedbackTask?.cancel()
        copyFeedbackTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1_100))
            guard !Task.isCancelled else { return }
            self?.copyFeedbackVisible = false
        }
    }

    func saveAnswer() {
        guard let result, !result.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            status = "Nothing to save"
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = AnswerExport.suggestedFilename(for: result.question.isEmpty ? lastQuestion : result.question)

        NSApp.activate(ignoringOtherApps: true)
        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                guard let self else { return }
                do {
                    try AnswerExport.text(for: result, fallbackQuestion: self.lastQuestion)
                        .write(to: url, atomically: true, encoding: .utf8)
                    self.status = "Saved"
                } catch {
                    self.errorMessage = error.localizedDescription
                    self.status = "Save failed"
                }
            }
        }
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            panel.begin(completionHandler: completion)
        }
    }

    func openSource(_ source: Source) {
        guard let url = URL(string: source.url), ["http", "https"].contains(url.scheme?.lowercased()) else { return }
        NSWorkspace.shared.open(url)
    }

    private func uniqueTrimmedValues(_ values: [String]) -> [String] {
        AnswerExport.uniqueTrimmed(values)
    }
}
