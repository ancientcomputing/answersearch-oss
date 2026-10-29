import AnswerSearchKit
import AppKit
import Foundation

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var isSaving = false
    @Published var statusMessage = ""
    @Published var isErrorStatus = false
    @Published private(set) var isReadyToLaunch = false

    @Published var provider: ProviderKind = .anthropic
    @Published var apiKey = ""
    @Published var model = ""
    @Published var responseMode: ResponseMode = .default
    @Published var startAtSignIn = false
    @Published var automaticallyUseLocalAI = false
    @Published var keyboardShortcutEnabled = true
    @Published var keyboardShortcutModifiers = KeyboardShortcut.suggested.modifiers
    @Published var keyboardShortcutKey = KeyboardShortcut.suggested.key
    @Published var userCity = ""
    @Published var userRegion = ""
    @Published var userCountry = ""
    @Published var userTimezone = TimeZone.current.identifier

    let appState: AppState
    private var isApplyingConfig = false

    init(appState: AppState) {
        self.appState = appState
        load()
    }

    var title: String {
        if isReadyToLaunch { return "Setup Complete" }
        return appState.needsSetup ? "Setup" : "Settings"
    }

    var needsSetup: Bool { appState.needsSetup }
    var providerAnswersAvailable: Bool { AppState.providerAnswersAvailable }
    var providerOptions: [ProviderKind] { ProviderKind.allCases }
    var apiKeyPlaceholder: String { appState.hasAPIKey ? "Leave unchanged" : "Required" }
    var canSaveCredentialSection: Bool { !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var localAIAvailable: Bool { appState.localAI.supported }

    var responseModeOptions: [ResponseMode] {
        var modes: [ResponseMode] = []
        if localAIAvailable && automaticallyUseLocalAI { modes.append(.localFast) }
        if providerAnswersAvailable { modes.append(contentsOf: [.aiFast, .webQuick, .webDeep]) }
        return modes
    }

    var localAIStatusText: String {
        let status = appState.localAI
        if status.supported { return "Available on this Mac." }
        if status.reason == "api_unavailable" {
            return "Local AI needs macOS 26 and Apple Intelligence. AnswerSearch will use your selected provider."
        }
        if !status.detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return status.detail }
        return "Local AI is not available on this Mac. AnswerSearch will use your selected provider."
    }

    var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return "Version \(version ?? "development")"
    }

    // MARK: Loading

    func load() {
        isApplyingConfig = true
        defer { isApplyingConfig = false }
        let settings = appState.settings
        provider = settings.provider
        model = settings.model
        automaticallyUseLocalAI = settings.automaticallyUseLocalAI && localAIAvailable
        responseMode = appState.effectiveMode(settings.responseMode)
        startAtSignIn = LaunchAtLogin.isEnabled
        keyboardShortcutEnabled = settings.shortcut.enabled
        keyboardShortcutModifiers = settings.shortcut.modifiers
        keyboardShortcutKey = settings.shortcut.key
        userCity = settings.userCity
        userRegion = settings.userRegion
        userCountry = settings.userCountry
        userTimezone = settings.userTimezone.isEmpty ? TimeZone.current.identifier : settings.userTimezone
    }

    // MARK: Saving

    func save() {
        persist(successMessage: "Saved.")
    }

    func saveCredentialSection() {
        persist(successMessage: "AI provider saved.")
    }

    private func persist(successMessage: String) {
        isSaving = true
        defer { isSaving = false }
        let wasSettingUp = appState.needsSetup
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try appState.update { settings in
                settings.provider = provider
                settings.model = trimmedModel.isEmpty ? provider.defaultModel : trimmedModel
                settings.responseMode = appState.effectiveMode(responseMode)
                settings.automaticallyUseLocalAI = automaticallyUseLocalAI
                settings.shortcut = KeyboardShortcut(
                    enabled: keyboardShortcutEnabled, key: keyboardShortcutKey, modifiers: keyboardShortcutModifiers
                ).normalized
                settings.userCity = userCity.trimmingCharacters(in: .whitespacesAndNewlines)
                settings.userRegion = userRegion.trimmingCharacters(in: .whitespacesAndNewlines)
                settings.userCountry = userCountry.trimmingCharacters(in: .whitespacesAndNewlines)
                settings.userTimezone = userTimezone.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if !trimmedKey.isEmpty {
                try appState.saveAPIKey(trimmedKey, for: provider)
                apiKey = ""
            } else {
                appState.refreshKeyState()
            }
            model = appState.settings.model
            isReadyToLaunch = wasSettingUp && !appState.needsSetup
            setStatus(isReadyToLaunch ? "Saved. AnswerSearch is ready." : successMessage, isError: false)
        } catch {
            setStatus(error.localizedDescription, isError: true)
        }
    }

    func deleteAPIKey() {
        do {
            try appState.deleteAPIKey()
            apiKey = ""
            isReadyToLaunch = false
            setStatus("API key deleted.", isError: false)
        } catch {
            setStatus(error.localizedDescription, isError: true)
        }
    }

    func deleteAll() {
        do {
            try appState.deleteAllLocalData()
            apiKey = ""
            isReadyToLaunch = false
            load()
            setStatus("Local data deleted.", isError: false)
        } catch {
            setStatus(error.localizedDescription, isError: true)
        }
    }

    // MARK: Immediate settings

    func providerDidChange() {
        guard !isApplyingConfig else { return }
        model = provider.defaultModel
        setStatus("Model set to the selected provider's default. Save to apply.", isError: false)
    }

    func responseModeDidChange() {
        guard !isApplyingConfig, responseModeOptions.contains(responseMode) else { return }
        applyImmediately("Answer Mode saved.") { $0.responseMode = self.responseMode }
    }

    func localAISettingDidChange() {
        guard !isApplyingConfig else { return }
        let enabled = automaticallyUseLocalAI
        if !enabled, responseMode == .localFast {
            isApplyingConfig = true
            responseMode = AppState.providerAnswersAvailable ? .aiFast : .localFast
            isApplyingConfig = false
        }
        let mode = responseMode
        applyImmediately("Local AI setting saved.") {
            $0.automaticallyUseLocalAI = enabled
            $0.responseMode = mode
        }
    }

    func startAtSignInDidChange() {
        guard !isApplyingConfig else { return }
        do {
            try LaunchAtLogin.setEnabled(startAtSignIn)
            setStatus("Startup setting saved.", isError: false)
        } catch {
            isApplyingConfig = true
            startAtSignIn = LaunchAtLogin.isEnabled
            isApplyingConfig = false
            setStatus(error.localizedDescription, isError: true)
        }
    }

    func keyboardShortcutDidChange() {
        guard !isApplyingConfig else { return }
        let shortcut = KeyboardShortcut(
            enabled: keyboardShortcutEnabled, key: keyboardShortcutKey, modifiers: keyboardShortcutModifiers
        ).normalized
        applyImmediately("Keyboard shortcut saved.") { $0.shortcut = shortcut }
    }

    func resetShortcut() {
        keyboardShortcutModifiers = KeyboardShortcut.suggested.modifiers
        keyboardShortcutKey = KeyboardShortcut.suggested.key
        keyboardShortcutDidChange()
    }

    private func applyImmediately(_ message: String, _ change: @escaping (inout AppSettings) -> Void) {
        do {
            try appState.update(change)
            setStatus(message, isError: false)
        } catch {
            load()
            setStatus(error.localizedDescription, isError: true)
        }
    }

    func openLink(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    func markAnswerSearchLaunched() {
        isReadyToLaunch = false
        setStatus("Opening AnswerSearch.", isError: false)
    }

    private func setStatus(_ message: String, isError: Bool) {
        statusMessage = message
        isErrorStatus = isError
    }
}
