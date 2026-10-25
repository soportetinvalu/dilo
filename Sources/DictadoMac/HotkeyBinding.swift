import Foundation

// Máscaras de modificadores. Los valores coinciden con CGEventFlags /
// NSEvent.ModifierFlags (se definen aquí como números para que este archivo
// solo dependa de Foundation).
enum ModifierMask {
    static let shift: UInt64 = 0x0002_0000
    static let control: UInt64 = 0x0004_0000
    static let option: UInt64 = 0x0008_0000
    static let command: UInt64 = 0x0010_0000
    /// Los cuatro modificadores "normales" (sin fn, bloq. mayús., etc.).
    static let all: UInt64 = shift | control | option | command
}

/// La tecla (o combinación) que activa el dictado. Se guarda en UserDefaults.
struct HotkeyBinding: Codable, Equatable {
    enum Kind: String, Codable {
        /// Un modificador solo (p. ej. Option derecha). Se distingue izquierda/derecha por keyCode.
        case modifierKey
        /// Una tecla normal, con o sin modificadores (p. ej. ⌃⌥Espacio, F5).
        case key
    }

    var kind: Kind
    var keyCode: UInt16
    /// Solo para `.key`: modificadores que deben estar pulsados (bits de `ModifierMask`).
    var modifiers: UInt64 = 0

    /// Valor inicial: Option derecha.
    static let `default` = HotkeyBinding(kind: .modifierKey, keyCode: 61)

    // MARK: Modificadores sueltos

    /// keyCode → (nombre, máscara "de dispositivo" que indica que ESA tecla concreta está pulsada).
    /// Las máscaras de dispositivo (NX_DEVICE*KEYMASK de IOKit) permiten saber si se pulsó
    /// la tecla izquierda o la derecha, y detectar bien la suelta cuando se mantienen las dos.
    private static let modifierKeys: [UInt16: (name: String, deviceMask: UInt64)] = [
        54: ("⌘ Comando derecha", 0x0000_0010),
        55: ("⌘ Comando izquierda", 0x0000_0008),
        56: ("⇧ Mayús izquierda", 0x0000_0002),
        60: ("⇧ Mayús derecha", 0x0000_0004),
        58: ("⌥ Option izquierda", 0x0000_0020),
        61: ("⌥ Option derecha", 0x0000_0040),
        59: ("⌃ Control izquierda", 0x0000_0001),
        62: ("⌃ Control derecha", 0x0000_2000),
        63: ("fn (🌐)", 0x0080_0000),
    ]

    static func isModifierKeyCode(_ keyCode: UInt16) -> Bool {
        modifierKeys[keyCode] != nil
    }

    static func deviceMask(forModifierKeyCode keyCode: UInt16) -> UInt64? {
        modifierKeys[keyCode]?.deviceMask
    }

    // MARK: Teclas normales

    private static let keyNames: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7",
        27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P",
        36: "Intro", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/",
        45: "N", 46: "M", 47: ".", 48: "Tab", 49: "Espacio", 50: "`", 51: "Borrar", 53: "Esc",
        96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9", 103: "F11",
        105: "F13", 106: "F16", 107: "F14", 109: "F10", 111: "F12", 113: "F15",
        115: "Inicio", 116: "Re Pág", 117: "Supr", 118: "F4", 119: "Fin", 120: "F2",
        121: "Av Pág", 122: "F1", 123: "←", 124: "→", 125: "↓", 126: "↑",
        64: "F17", 79: "F18", 80: "F19", 90: "F20",
    ]

    /// Teclas que se pueden usar SIN modificadores (no escriben nada al teclear).
    private static let bareAllowed: Set<UInt16> = [
        122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106, 64, 79, 80, 90,
    ]

    static func isAllowedWithoutModifiers(_ keyCode: UInt16) -> Bool {
        bareAllowed.contains(keyCode)
    }

    // MARK: Texto para mostrar

    var displayName: String {
        switch kind {
        case .modifierKey:
            return Self.modifierKeys[keyCode]?.name ?? "Tecla \(keyCode)"
        case .key:
            var text = ""
            if modifiers & ModifierMask.control != 0 { text += "⌃" }
            if modifiers & ModifierMask.option != 0 { text += "⌥" }
            if modifiers & ModifierMask.shift != 0 { text += "⇧" }
            if modifiers & ModifierMask.command != 0 { text += "⌘" }
            return text + (Self.keyNames[keyCode] ?? "Tecla \(keyCode)")
        }
    }
}
