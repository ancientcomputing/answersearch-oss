import AnswerSearchKit
import AppKit
import Carbon.HIToolbox
import Combine
import Foundation

@MainActor
final class KeyboardShortcutManager {
    private let onShortcut: () -> Void
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var activeShortcut: KeyboardShortcut?
    private var cancellable: AnyCancellable?

    init(appState: AppState, onShortcut: @escaping () -> Void) {
        self.onShortcut = onShortcut
        installEventHandler()
        apply(appState.settings.shortcut)
        cancellable = appState.$settings
            .map(\.shortcut)
            .removeDuplicates()
            .sink { [weak self] shortcut in
                self?.apply(shortcut)
            }
    }

    func invalidate() {
        unregister()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
        cancellable = nil
    }

    private func apply(_ requested: KeyboardShortcut) {
        let shortcut = requested.enabled ? requested.normalized : nil
        guard shortcut != activeShortcut else { return }

        unregister()
        activeShortcut = nil
        guard let shortcut else { return }

        let hotKeyID = EventHotKeyID(signature: OSType(fourCharCode("ANSR")), id: 1)
        let status = RegisterEventHotKey(
            shortcut.keyCode, shortcut.carbonModifiers, hotKeyID,
            GetApplicationEventTarget(), 0, &hotKeyRef
        )
        if status == noErr {
            activeShortcut = shortcut
        } else {
            presentShortcutError(shortcut)
        }
    }

    private func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    private func installEventHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }
                var hotKeyID = EventHotKeyID()
                GetEventParameter(
                    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                    nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
                )
                guard hotKeyID.id == 1 else { return noErr }
                let manager = Unmanaged<KeyboardShortcutManager>.fromOpaque(userData).takeUnretainedValue()
                Task { @MainActor in
                    manager.onShortcut()
                }
                return noErr
            },
            1, &eventType, selfPointer, &eventHandler
        )
    }

    private func presentShortcutError(_ shortcut: KeyboardShortcut) {
        let alert = NSAlert()
        alert.messageText = "Keyboard shortcut unavailable"
        alert.informativeText = "\(shortcut.displayName) could not be registered. Choose another shortcut in AnswerSearch Settings."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

extension KeyboardShortcut {
    var keyCode: UInt32 {
        switch key {
        case "return": UInt32(kVK_Return)
        case "f": UInt32(kVK_ANSI_F)
        case "k": UInt32(kVK_ANSI_K)
        default: UInt32(kVK_Space)
        }
    }

    var carbonModifiers: UInt32 {
        switch modifiers {
        case "control+shift": UInt32(controlKey | shiftKey)
        case "option+shift": UInt32(optionKey | shiftKey)
        default: UInt32(controlKey | optionKey)
        }
    }

    var displayName: String {
        let names = modifiers.split(separator: "+").map { $0.capitalized }.joined(separator: " + ")
        return "\(names) + \(key.capitalized)"
    }
}

private func fourCharCode(_ string: String) -> UInt32 {
    string.utf8.reduce(UInt32(0)) { ($0 << 8) + UInt32($1) }
}
