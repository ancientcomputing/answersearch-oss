import AppKit
import Foundation

/// Owns the app's windows and the menu bar status line.
@MainActor
final class AppController: ObservableObject {
    @Published private(set) var statusText = "AnswerSearch ready"

    let appState: AppState
    private let workspaceWindow = WorkspaceWindowController()
    private let settingsWindow = SettingsWindowController()
    private var shortcutManager: KeyboardShortcutManager?

    init(appState: AppState = AppState()) {
        self.appState = appState
        shortcutManager = KeyboardShortcutManager(appState: appState) { [weak self] in
            self?.openAnswerSearch()
        }
        refreshStatus()
        // Let the menu-bar item appear first, then show the workspace (or setup on first run).
        DispatchQueue.main.async { [weak self] in
            self?.openAnswerSearch()
        }
    }

    func openAnswerSearch() {
        if appState.needsSetup {
            openSettings()
            return
        }
        workspaceWindow.show(appState: appState)
        refreshStatus()
    }

    func openSettings() {
        settingsWindow.show(appState: appState) { [weak self] in
            guard let self else { return }
            self.workspaceWindow.show(appState: self.appState)
            self.refreshStatus()
        }
        refreshStatus()
    }

    func quit() {
        shortcutManager?.invalidate()
        NSApplication.shared.terminate(nil)
    }

    func refreshStatus() {
        if appState.needsSetup {
            statusText = "Setup needed"
        } else {
            statusText = "AnswerSearch \(appState.settings.provider.shortName) \(appState.settings.model)"
        }
    }
}
