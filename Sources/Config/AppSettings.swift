import AppKit
import Foundation

struct AppSettings: Codable, Equatable {
    var provider: TranslationProvider = .google
    var baseURL: String = ""
    var apiKey: String = ""
    var model: String = "openai/gpt-5-nano"
    var hotkey: KeyboardShortcut = .defaultShortcut
    var enableCtrlSpace: Bool = true
    var enableDoubleCommand: Bool = true

    var hotkeyDisplay: String {
        get { hotkey.displayString }
        set {
            if let parsed = KeyboardShortcut.parse(from: newValue) {
                hotkey = parsed
            }
        }
    }
}

enum TranslationProvider: String, Codable, CaseIterable, Identifiable {
    case google
    case openAICompatible

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .google:
            return "Google"
        case .openAICompatible:
            return "OpenAI Compatible"
        }
    }
}

struct KeyboardShortcut: Codable, Equatable {
    var keyCode: UInt16
    var modifiers: NSEvent.ModifierFlags

    static let defaultShortcut = KeyboardShortcut(
        keyCode: 49,
        modifiers: [.control]
    )

    var displayString: String {
        let modifierText: String
        if modifiers.contains(.command) && modifiers.contains(.shift) {
            modifierText = "⌘⇧"
        } else if modifiers.contains(.control) && modifiers.contains(.option) {
            modifierText = "⌃⌥"
        } else if modifiers.contains(.control) && modifiers.contains(.command) {
            modifierText = "⌃⌘"
        } else if modifiers.contains(.option) && modifiers.contains(.shift) {
            modifierText = "⌥⇧"
        } else if modifiers.contains(.control) {
            modifierText = "⌃"
        } else if modifiers.contains(.option) {
            modifierText = "⌥"
        } else {
            modifierText = ""
        }

        let keyText: String
        switch keyCode {
        case 49:
            keyText = "Space"
        case 17:
            keyText = "T"
        default:
            keyText = "KeyCode(\(keyCode))"
        }

        return modifierText + keyText
    }

    static func parse(from string: String) -> KeyboardShortcut? {
        let normalized = string.lowercased().replacingOccurrences(of: " ", with: "")

        switch normalized {
        case "⌃space", "ctrlspace", "controlspace":
            return .defaultShortcut
        case "⌃⌥space", "ctrloptionspace", "controloptionspace":
            return KeyboardShortcut(keyCode: 49, modifiers: [.control, .option])
        case "⌘⇧space", "commandshiftspace":
            return KeyboardShortcut(keyCode: 49, modifiers: [.command, .shift])
        case "⌃⌘t", "ctrlcommandt", "controlcommandt":
            return KeyboardShortcut(keyCode: 17, modifiers: [.control, .command])
        case "⌥⇧t", "optionshiftt":
            return KeyboardShortcut(keyCode: 17, modifiers: [.option, .shift])
        default:
            return nil
        }
    }
}

extension NSEvent.ModifierFlags: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(UInt.self)
        self.init(rawValue: rawValue)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
