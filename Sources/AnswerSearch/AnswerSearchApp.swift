import AppKit
import SwiftUI

@main
struct AnswerSearchApp: App {
    @StateObject private var controller = AppController()
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some Scene {
        MenuBarExtra {
            Button("Open AnswerSearch") {
                controller.openAnswerSearch()
            }

            Button("Settings") {
                controller.openSettings()
            }

            Divider()

            Toggle("Launch at Login", isOn: Binding(
                get: { launchAtLogin },
                set: { enabled in
                    do {
                        try LaunchAtLogin.setEnabled(enabled)
                    } catch {
                        NSSound.beep()
                    }
                    launchAtLogin = LaunchAtLogin.isEnabled
                }
            ))
            .onAppear {
                launchAtLogin = LaunchAtLogin.isEnabled
            }

            Divider()

            Text(controller.statusText)
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Quit") {
                controller.quit()
            }
        } label: {
            Image(nsImage: MenuBarIcon.image)
                .renderingMode(.template)
                .accessibilityLabel("AnswerSearch")
        }
        .menuBarExtraStyle(.menu)
    }
}

enum MenuBarIcon {
    static var image: NSImage {
        if let bundled = Bundle.main.url(forResource: "answersearch_menu", withExtension: "png"),
           let image = NSImage(contentsOf: bundled) {
            image.isTemplate = true
            image.size = NSSize(width: 18, height: 18)
            return image
        }
        return NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "AnswerSearch") ?? NSImage()
    }
}
