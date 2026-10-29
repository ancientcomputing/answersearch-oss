import AppKit
import SwiftUI

@MainActor
final class WorkspaceWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var viewModel: WorkspaceViewModel?

    func show(appState: AppState) {
        if window == nil {
            let model = WorkspaceViewModel(appState: appState)
            viewModel = model
            let hostingController = NSHostingController(rootView: WorkspaceView(viewModel: model))
            let workspaceWindow = NSWindow(contentViewController: hostingController)
            workspaceWindow.title = "AnswerSearch"
            workspaceWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            workspaceWindow.contentMinSize = NSSize(width: 760, height: 560)
            workspaceWindow.setContentSize(NSSize(width: 860, height: 680))
            workspaceWindow.isReleasedWhenClosed = false
            workspaceWindow.delegate = self
            workspaceWindow.center()
            window = workspaceWindow
        } else {
            viewModel?.loadResponseMode()
        }

        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        guard notification.object as? NSWindow === window else { return }
        viewModel?.resetToQuestionPage()
    }
}
