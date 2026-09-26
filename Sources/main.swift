import AppKit

// CLI mode, handy for scripting:
//   Hopscreen --list
//   Hopscreen --set 0x11 [--display "U3225QE"]
let args = CommandLine.arguments
if args.count >= 2 {
    let displays = Display.all()
    var filtered = displays
    if let i = args.firstIndex(of: "--display"), i + 1 < args.count {
        filtered = displays.filter { $0.name.localizedCaseInsensitiveContains(args[i + 1]) || $0.id == args[i + 1] }
    }
    switch args[1] {
    case "--list":
        if displays.isEmpty { print("No DDC-capable external display found."); exit(1) }
        for d in displays {
            let current = d.currentInput().map { "0x\(hex($0)) (\(KnownInputs.name(for: $0)))" } ?? "no reply"
            print("\(d.name)\n  id: \(d.id)\n  current input: \(current)")
        }
        exit(0)
    case "--set" where args.count >= 3:
        let raw = args[2].lowercased()
        guard let v = raw.hasPrefix("0x") ? UInt16(raw.dropFirst(2), radix: 16) : UInt16(raw) else {
            print("Invalid value \(args[2])"); exit(2)
        }
        let ok = filtered.filter { $0.setInput(v) }
        print("Switched \(ok.count) display(s) to 0x\(hex(v))")
        exit(ok.isEmpty ? 1 : 0)
    case "--help", "-h":
        print("Usage: Hopscreen [--list | --set <value> [--display <name|id>]]")
        exit(0)
    default:
        break
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
