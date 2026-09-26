import Carbon.HIToolbox
import Foundation

struct InputSource: Codable, Equatable {
    var name: String
    var value: UInt16
}

struct HotkeyBinding: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32 // Carbon modifier mask
    var keyLabel: String
    var displayID: String
    var input: UInt16

    var display: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + keyLabel
    }
}

/// Well-known VCP 0x60 values (MCCS plus common vendor extensions).
enum KnownInputs {
    static let all: [InputSource] = [
        InputSource(name: "DisplayPort 1", value: 0x0F),
        InputSource(name: "DisplayPort 2", value: 0x10),
        InputSource(name: "HDMI 1", value: 0x11),
        InputSource(name: "HDMI 2", value: 0x12),
        InputSource(name: "Thunderbolt / USB-C", value: 0x19),
        InputSource(name: "USB-C", value: 0x1B),
        InputSource(name: "VGA", value: 0x01),
        InputSource(name: "DVI", value: 0x03),
    ]

    static func name(for value: UInt16) -> String {
        all.first { $0.value == value }?.name ?? "Input 0x\(hex(value))"
    }

    /// Starting list for a display seen for the first time.
    static func defaults(vendor: String, current: UInt16?) -> [InputSource] {
        var inputs = all.filter { [0x0F, 0x11, 0x12, 0x1B].contains($0.value) }
        if vendor == "DEL" { inputs.insert(all.first { $0.value == 0x19 }!, at: 3) }
        if let current, current != 0, !inputs.contains(where: { $0.value == current }) {
            inputs.append(InputSource(name: name(for: current), value: current))
        }
        return inputs
    }
}

func hex(_ v: UInt16) -> String { String(v, radix: 16, uppercase: true).leftPadded(to: 2) }

private extension String {
    func leftPadded(to n: Int) -> String { count >= n ? self : String(repeating: "0", count: n - count) + self }
}

enum Settings {
    private static let d = UserDefaults.standard

    /// Inputs per display id.
    static var inputs: [String: [InputSource]] {
        get { decode("inputsByDisplay") ?? [:] }
        set { encode(newValue, "inputsByDisplay") }
    }

    static var hotkeys: [HotkeyBinding] {
        get { decode("hotkeys") ?? [] }
        set { encode(newValue, "hotkeys") }
    }

    private static func decode<T: Decodable>(_ key: String) -> T? {
        d.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    private static func encode<T: Encodable>(_ value: T, _ key: String) {
        d.set(try? JSONEncoder().encode(value), forKey: key)
    }
}
