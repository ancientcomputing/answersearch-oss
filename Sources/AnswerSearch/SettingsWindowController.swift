import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private var viewModel: SettingsViewModel?
    private var launchHandler: (() -> Void)?

    func show(appState: AppState, onLaunch: @escaping () -> Void) {
        launchHandler = onLaunch
        if window == nil {
            let model = SettingsViewModel(appState: appState)
            viewModel = model
            let view = SettingsView(
                viewModel: model,
                onDone: { [weak self] in
                    self?.window?.close()
                },
                onLaunch: { [weak self] in
                    self?.window?.close()
                    self?.launchHandler?()
                }
            )
            let hostingController = NSHostingController(rootView: view)
            let settingsWindow = NSWindow(contentViewController: hostingController)
            settingsWindow.title = "AnswerSearch Settings"
            settingsWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            settingsWindow.contentMinSize = NSSize(width: 620, height: 520)
            settingsWindow.contentMaxSize = NSSize(width: 620, height: CGFloat.greatestFiniteMagnitude)
            settingsWindow.setContentSize(NSSize(width: 620, height: 760))
            settingsWindow.isReleasedWhenClosed = false
            settingsWindow.center()
            window = settingsWindow
        } else {
            viewModel?.load()
        }

        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
