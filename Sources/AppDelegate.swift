import AppKit
import ServiceManagement

let repoURL = URL(string: "https://github.com/renjiexu/hopscreen")!

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var hotKeys: HotKeys!
    private var displays: [Display] = []
    /// Last known input per display id (read over DDC, or what we last switched to).
    private var currentInput: [String: UInt16] = [:]
    private let ddcQueue = DispatchQueue(label: "hopscreen.ddc", qos: .userInitiated)

    func applicationDidFinishLaunching(_ note: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let image = NSImage(systemSymbolName: "rectangle.2.swap", accessibilityDescription: "Hopscreen")
        image?.isTemplate = true
        statusItem.button?.image = image
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        hotKeys = HotKeys { [weak self] binding in self?.switchInput(binding.input, displayID: binding.displayID) }
        hotKeys.register(Settings.hotkeys)

        refreshDisplays()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in self?.refreshDisplays() }
    }

    /// Re-enumerates displays and reads their current inputs in the background.
    private func refreshDisplays() {
        ddcQueue.async {
            let found = Display.all()
            let current = Dictionary(found.compactMap { d in d.currentInput().map { (d.id, $0) } }) { a, _ in a }
            DispatchQueue.main.async {
                self.displays = found
                self.currentInput.merge(current) { _, new in new }
                var all = Settings.inputs
                for d in found where all[d.id] == nil {
                    all[d.id] = KnownInputs.defaults(vendor: d.vendor, current: current[d.id])
                }
                Settings.inputs = all
            }
        }
    }

    private func inputs(for display: Display) -> [InputSource] {
        Settings.inputs[display.id] ?? KnownInputs.defaults(vendor: display.vendor, current: currentInput[display.id])
    }

    private func displayName(_ display: Display) -> String {
        // Disambiguate identical models.
        displays.filter { $0.name == display.name }.count > 1
            ? "\(display.name) (\(display.id.split(separator: "-").last ?? ""))" : display.name
    }

    // MARK: Menu (rebuilt on every open so it reflects current state)

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let bindings = Settings.hotkeys

        if displays.isEmpty {
            menu.addItem(disabled("No DDC-capable external display"))
        }
        for display in displays {
            menu.addItem(disabled(displayName(display)))
            for input in inputs(for: display) {
                let item = item(input.name, #selector(switchFromMenu(_:)), (display.id, input.value))
                item.indentationLevel = 1
                item.state = currentInput[display.id] == input.value ? .on : .off
                if let b = bindings.first(where: { $0.displayID == display.id && $0.input == input.value }) {
                    item.title += "    \(b.display)"
                }
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())
        if !displays.isEmpty {
            menu.addItem(submenu("Hotkeys", hotkeysMenu(bindings)))
            menu.addItem(submenu("Inputs", inputsMenu()))
        }
        let login = item("Launch at Login", #selector(toggleLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(item("Refresh Displays", #selector(refreshFromMenu)))
        menu.addItem(.separator())
        menu.addItem(item("About Hopscreen", #selector(about)))
        menu.addItem(NSMenuItem(title: "Quit Hopscreen", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func hotkeysMenu(_ bindings: [HotkeyBinding]) -> NSMenu {
        let menu = NSMenu()
        for display in displays {
            if displays.count > 1 { menu.addItem(disabled(displayName(display))) }
            for input in inputs(for: display) {
                let b = bindings.first { $0.displayID == display.id && $0.input == input.value }
                let title = "\(input.name):  \(b?.display ?? "—")"
                let sub = NSMenu()
                sub.addItem(item(b == nil ? "Set Shortcut…" : "Change Shortcut…", #selector(recordHotkey(_:)), (display.id, input.value)))
                if b != nil { sub.addItem(item("Remove Shortcut", #selector(removeHotkey(_:)), (display.id, input.value))) }
                menu.addItem(submenu(title, sub))
            }
        }
        menu.addItem(.separator())
        menu.addItem(disabled("Tip: bind the input of the *other* computer"))
        return menu
    }

    private func inputsMenu() -> NSMenu {
        let menu = NSMenu()
        for display in displays {
            let sub = NSMenu()
            sub.addItem(item("Add Input…", #selector(addInput(_:)), display.id))
            sub.addItem(item("Read Current Input", #selector(readCurrentInput(_:)), display.id))
            sub.addItem(.separator())
            for input in inputs(for: display) {
                sub.addItem(item("Remove \(input.name) (0x\(hex(input.value)))", #selector(removeInput(_:)), (display.id, input.value)))
            }
            sub.addItem(.separator())
            sub.addItem(item("Reset to Defaults", #selector(resetInputs(_:)), display.id))
            if displays.count == 1 { return sub }
            menu.addItem(submenu(displayName(display), sub))
        }
        return menu
    }

    private func item(_ title: String, _ action: Selector, _ payload: Any? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = payload.map { payload -> Any in
            if let (id, value) = payload as? (String, UInt16) { return [id, Int(value)] as [Any] }
            return payload
        }
        return item
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func submenu(_ title: String, _ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    private func target(_ sender: NSMenuItem) -> (displayID: String, input: UInt16)? {
        guard let pair = sender.representedObject as? [Any], let id = pair[0] as? String, let v = pair[1] as? Int else { return nil }
        return (id, UInt16(v))
    }

    // MARK: Actions

    @objc private func switchFromMenu(_ sender: NSMenuItem) {
        guard let t = target(sender) else { return }
        switchInput(t.input, displayID: t.displayID)
    }

    private func switchInput(_ value: UInt16, displayID: String) {
        guard let display = displays.first(where: { $0.id == displayID }) else {
            NSSound.beep()
            return
        }
        ddcQueue.async {
            let ok = display.setInput(value)
            DispatchQueue.main.async {
                if ok {
                    self.currentInput[displayID] = value
                } else {
                    self.alert("Couldn't reach \(display.name)",
                               "The monitor didn't accept the DDC command. Make sure DDC/CI is enabled in the monitor's on-screen menu.")
                }
            }
        }
    }

    @objc private func recordHotkey(_ sender: NSMenuItem) {
        guard let t = target(sender) else { return }
        let name = Settings.inputs[t.displayID]?.first { $0.value == t.input }?.name ?? "input"
        hotKeys.unregisterAll()
        defer { hotKeys.register(Settings.hotkeys) }
        guard let key = HotKeys.record(prompt: "Shortcut for “\(name)”") else { return }
        var bindings = Settings.hotkeys.filter {
            !($0.displayID == t.displayID && $0.input == t.input) && !($0.keyCode == key.keyCode && $0.modifiers == key.modifiers)
        }
        bindings.append(HotkeyBinding(keyCode: key.keyCode, modifiers: key.modifiers, keyLabel: key.label,
                                      displayID: t.displayID, input: t.input))
        Settings.hotkeys = bindings
    }

    @objc private func removeHotkey(_ sender: NSMenuItem) {
        guard let t = target(sender) else { return }
        Settings.hotkeys = Settings.hotkeys.filter { !($0.displayID == t.displayID && $0.input == t.input) }
        hotKeys.register(Settings.hotkeys)
    }

    @objc private func addInput(_ sender: NSMenuItem) {
        guard let displayID = sender.representedObject as? String,
              let display = displays.first(where: { $0.id == displayID }) else { return }

        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 60, width: 260, height: 26))
        for known in KnownInputs.all { popup.addItem(withTitle: "\(known.name)  (0x\(hex(known.value)))") }
        popup.addItem(withTitle: "Custom…")
        let name = NSTextField(frame: NSRect(x: 0, y: 30, width: 260, height: 24))
        name.placeholderString = "Custom name, e.g. Work Laptop"
        let value = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        value.placeholderString = "Custom value, e.g. 0x12 or 18"
        let box = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 88))
        [popup, name, value].forEach(box.addSubview)

        let alert = NSAlert()
        alert.messageText = "Add Input to \(display.name)"
        alert.informativeText = "Pick a standard input, or choose Custom and enter the VCP 0x60 value. A name entered here overrides the default label."
        alert.accessoryView = box
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let customName = name.stringValue.trimmingCharacters(in: .whitespaces)
        var input: InputSource
        if popup.indexOfSelectedItem < KnownInputs.all.count {
            input = KnownInputs.all[popup.indexOfSelectedItem]
        } else {
            let raw = value.stringValue.trimmingCharacters(in: .whitespaces).lowercased()
            guard let v = raw.hasPrefix("0x") ? UInt16(raw.dropFirst(2), radix: 16) : UInt16(raw) else {
                self.alert("Invalid value", "Enter a number like 0x12 or 18.")
                return
            }
            input = InputSource(name: KnownInputs.name(for: v), value: v)
        }
        if !customName.isEmpty { input.name = customName }

        var all = Settings.inputs
        var list = (all[displayID] ?? inputs(for: display)).filter { $0.value != input.value }
        list.append(input)
        all[displayID] = list
        Settings.inputs = all
    }

    @objc private func removeInput(_ sender: NSMenuItem) {
        guard let t = target(sender), let display = displays.first(where: { $0.id == t.displayID }) else { return }
        var all = Settings.inputs
        all[t.displayID] = inputs(for: display).filter { $0.value != t.input }
        Settings.inputs = all
        Settings.hotkeys = Settings.hotkeys.filter { !($0.displayID == t.displayID && $0.input == t.input) }
        hotKeys.register(Settings.hotkeys)
    }

    @objc private func resetInputs(_ sender: NSMenuItem) {
        guard let displayID = sender.representedObject as? String,
              let display = displays.first(where: { $0.id == displayID }) else { return }
        var all = Settings.inputs
        all[displayID] = KnownInputs.defaults(vendor: display.vendor, current: currentInput[displayID])
        Settings.inputs = all
    }

    @objc private func readCurrentInput(_ sender: NSMenuItem) {
        guard let displayID = sender.representedObject as? String,
              let display = displays.first(where: { $0.id == displayID }) else { return }
        ddcQueue.async {
            let raw = display.read(vcp: Display.inputSourceVCP)
            DispatchQueue.main.async {
                guard let raw else {
                    self.alert(display.name, "The monitor didn't reply. Some monitors don't report their input over DDC; switching may still work.")
                    return
                }
                let v = raw.current & 0xFF
                self.currentInput[displayID] = v
                let known = self.inputs(for: display).first { $0.value == v }?.name
                self.alert(display.name, """
                    Current input: 0x\(hex(v)) (\(v))\(known.map { " — \($0)" } ?? "")
                    Raw reply: 0x\(hex(raw.current))

                    Note: this is the input the monitor is showing right now, which may be another computer.
                    """)
            }
        }
    }

    @objc private func refreshFromMenu() { refreshDisplays() }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            alert("Couldn't change login item", error.localizedDescription)
        }
    }

    @objc private func about() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        let a = NSAlert()
        a.messageText = "Hopscreen \(version)"
        a.informativeText = "Switch your monitor's input from the menu bar.\n\(repoURL.absoluteString)"
        a.addButton(withTitle: "OK")
        a.addButton(withTitle: "Open GitHub")
        NSApp.activate(ignoringOtherApps: true)
        if a.runModal() == .alertSecondButtonReturn { NSWorkspace.shared.open(repoURL) }
    }

    private func alert(_ title: String, _ text: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }
}
