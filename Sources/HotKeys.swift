// Global hotkeys via Carbon RegisterEventHotKey — works without Accessibility permission.

import AppKit
import Carbon.HIToolbox

final class HotKeys {
    private var refs: [EventHotKeyRef] = []
    private var bindings: [HotkeyBinding] = []
    private let onPress: (HotkeyBinding) -> Void
    private static weak var shared: HotKeys?
    private static let signature = OSType(0x484F5053) // 'HOPS'

    init(onPress: @escaping (HotkeyBinding) -> Void) {
        self.onPress = onPress
        HotKeys.shared = self
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            let index = Int(hotKeyID.id)
            DispatchQueue.main.async {
                guard let self = HotKeys.shared, self.bindings.indices.contains(index) else { return }
                self.onPress(self.bindings[index])
            }
            return noErr
        }, 1, &spec, nil, nil)
    }

    func register(_ bindings: [HotkeyBinding]) {
        unregisterAll()
        self.bindings = bindings
        for (i, b) in bindings.enumerated() {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: Self.signature, id: UInt32(i))
            if RegisterEventHotKey(b.keyCode, b.modifiers, id, GetApplicationEventTarget(), 0, &ref) == noErr, let ref {
                refs.append(ref)
            }
        }
    }

    func unregisterAll() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs = []
    }

    /// Shows a modal prompt and returns the next key combo pressed (must include ⌘, ⌥ or ⌃).
    static func record(prompt: String) -> (keyCode: UInt32, modifiers: UInt32, label: String)? {
        var result: (UInt32, UInt32, String)?
        let alert = NSAlert()
        alert.messageText = prompt
        alert.informativeText = "Press a shortcut that includes ⌘, ⌥ or ⌃."
        alert.addButton(withTitle: "Cancel")

        let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
            guard !flags.intersection([.command, .option, .control]).isEmpty else { return event }
            var mods: UInt32 = 0
            if flags.contains(.command) { mods |= UInt32(cmdKey) }
            if flags.contains(.option) { mods |= UInt32(optionKey) }
            if flags.contains(.control) { mods |= UInt32(controlKey) }
            if flags.contains(.shift) { mods |= UInt32(shiftKey) }
            result = (UInt32(event.keyCode), mods, keyLabel(for: event))
            NSApp.stopModal(withCode: .OK)
            return nil
        }
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
        if let monitor { NSEvent.removeMonitor(monitor) }
        return result
    }

    private static func keyLabel(for event: NSEvent) -> String {
        let special: [Int: String] = [
            kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Escape: "⎋",
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
            kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        ]
        return special[Int(event.keyCode)] ?? (event.charactersIgnoringModifiers ?? "?").uppercased()
    }
}
