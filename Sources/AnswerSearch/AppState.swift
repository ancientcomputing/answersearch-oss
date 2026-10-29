import AnswerSearchKit
import AppKit
import Foundation
import LocalLMLabSDKCore

extension Notification.Name {
    static let answerSearchSettingsDidChange = Notification.Name("answerSearchSettingsDidChange")
}

/// App-wide state: persisted settings, API-key presence, and the answer engine built on the
/// LocalLM Lab SDK.
@MainActor
final class AppState: ObservableObject {
    @Published private(set) var settings: AppSettings
    @Published private(set) var hasAPIKey: Bool
    @Published private(set) var settingsFileExisted: Bool

    let store: SettingsStore
    let credentials: CredentialStore
    let engine: AnswerEngine

    /// Hosted providers need macOS 27 (SDK `RemoteModelProvider`); macOS 26 runs Local AI only.
    static var providerAnswersAvailable: Bool {
        ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 0))
    }

    init(
        store: SettingsStore = SettingsStore(),
        credentials: CredentialStore = KeychainCredentialStore(),
        engine: AnswerEngine? = nil
    ) {
        let loaded = store.load()
        self.store = store
        self.credentials = credentials
        self.settings = loaded
        self.settingsFileExisted = store.exists
        self.hasAPIKey = credentials.apiKey(for: loaded.provider) != nil

        if let engine {
            self.engine = engine
        } else {
            let lab = LocalLMLab(configuration: .init(providers: [SystemModelProvider()]))
            self.engine = AnswerEngine(
                settings: loaded,
                local: AppleLocalAnswerer(lab: lab),
                provider: SDKProviderAnswerer(lab: lab, credentials: credentials)
            )
        }
    }

    var localAI: LocalAIAvailability { engine.localAIAvailability }

    /// Local AI mode is offered only when the Mac supports it and the user opted in.
    var localAIEnabled: Bool { settings.automaticallyUseLocalAI && localAI.supported }

    /// True until the user has what they need to get an answer.
    var needsSetup: Bool {
        if Self.providerAnswersAvailable { return !hasAPIKey }
        return !localAIEnabled
    }

    var availableModes: [ResponseMode] {
        var modes: [ResponseMode] = []
        if localAIEnabled { modes.append(.localFast) }
        if Self.providerAnswersAvailable { modes.append(contentsOf: [.aiFast, .webQuick, .webDeep]) }
        return modes
    }

    /// A stored mode the Mac can't currently run falls back to the nearest usable one.
    func effectiveMode(_ mode: ResponseMode) -> ResponseMode {
        let modes = availableModes
        if modes.contains(mode) { return mode }
        return modes.first(where: { $0 != .localFast }) ?? modes.first ?? mode
    }

    // MARK: Mutations

    /// Applies, persists and broadcasts a settings change.
    func update(_ change: (inout AppSettings) -> Void) throws {
        var next = settings
        change(&next)
        try store.save(next)
        settings = next
        settingsFileExisted = true
        engine.settings = next
        NotificationCenter.default.post(name: .answerSearchSettingsDidChange, object: nil)
    }

    func saveAPIKey(_ key: String, for provider: ProviderKind) throws {
        try credentials.setAPIKey(key, for: provider)
        refreshKeyState()
    }

    func deleteAPIKey() throws {
        try credentials.setAPIKey(nil, for: settings.provider)
        refreshKeyState()
    }

    /// Removes every stored key, the settings file and the remembered question.
    func deleteAllLocalData() throws {
        try credentials.deleteAllKeys()
        try store.delete()
        settings = AppSettings()
        engine.settings = settings
        engine.clearPrevious()
        settingsFileExisted = false
        refreshKeyState()
        NotificationCenter.default.post(name: .answerSearchSettingsDidChange, object: nil)
    }

    func refreshKeyState() {
        hasAPIKey = credentials.apiKey(for: settings.provider) != nil
    }
}
