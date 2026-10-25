import Foundation

/// Cómo se usa la tecla de dictado.
enum DictationMode: String, CaseIterable, Identifiable {
    /// Mantener pulsada para hablar; al soltar se transcribe.
    case hold
    /// Una pulsación empieza, otra termina.
    case toggle

    var id: String { rawValue }

    var label: String {
        switch self {
        case .hold: return "Mantener pulsada para hablar"
        case .toggle: return "Pulsar para empezar y pulsar para terminar"
        }
    }
}

/// Esfuerzo de razonamiento que se le pide a codex (más bajo = más rápido).
enum CodexReasoning: String, CaseIterable, Identifiable {
    case low
    case medium
    case modelDefault = ""

    var id: String { rawValue }

    var label: String {
        switch self {
        case .low: return "Bajo (más rápido, recomendado)"
        case .medium: return "Medio"
        case .modelDefault: return "El predeterminado de codex"
        }
    }
}

/// Todos los ajustes del usuario. Se guardan en UserDefaults al instante.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    /// Tecla de dictado (valor inicial: Option derecha).
    @Published var hotkey: HotkeyBinding {
        didSet { saveJSON(hotkey, key: "hotkey") }
    }
    @Published var mode: DictationMode {
        didSet { defaults.set(mode.rawValue, forKey: "mode") }
    }
    /// Interruptor del pulido con ChatGPT (codex).
    @Published var polishEnabled: Bool {
        didSet { defaults.set(polishEnabled, forKey: "polishEnabled") }
    }
    /// Si codex tarda más que esto (segundos), se inserta el texto crudo.
    @Published var polishTimeoutSeconds: Double {
        didSet { defaults.set(polishTimeoutSeconds, forKey: "polishTimeoutSeconds") }
    }
    /// Ruta del ejecutable codex; vacío = buscarlo automáticamente.
    @Published var codexPath: String {
        didSet { defaults.set(codexPath, forKey: "codexPath") }
    }
    /// Modelo de codex (opcional); vacío = el predeterminado.
    @Published var codexModel: String {
        didSet { defaults.set(codexModel, forKey: "codexModel") }
    }
    @Published var codexReasoning: CodexReasoning {
        didSet { defaults.set(codexReasoning.rawValue, forKey: "codexReasoning") }
    }
    /// UID del micrófono elegido; vacío = el predeterminado del sistema.
    @Published var microphoneUID: String {
        didSet { defaults.set(microphoneUID, forKey: "microphoneUID") }
    }
    @Published var soundsEnabled: Bool {
        didSet { defaults.set(soundsEnabled, forKey: "soundsEnabled") }
    }

    private init() {
        let store = UserDefaults.standard // (variable local: así no se lee `self` antes de terminar de inicializar)
        store.register(defaults: [
            "mode": DictationMode.hold.rawValue,
            "polishEnabled": true,
            "polishTimeoutSeconds": 12.0,
            "codexPath": "",
            "codexModel": "",
            "codexReasoning": CodexReasoning.low.rawValue,
            "microphoneUID": "",
            "soundsEnabled": true,
        ])
        hotkey = Self.loadJSON(HotkeyBinding.self, key: "hotkey", from: store) ?? .default
        mode = DictationMode(rawValue: store.string(forKey: "mode") ?? "") ?? .hold
        polishEnabled = store.bool(forKey: "polishEnabled")
        polishTimeoutSeconds = store.double(forKey: "polishTimeoutSeconds")
        codexPath = store.string(forKey: "codexPath") ?? ""
        codexModel = store.string(forKey: "codexModel") ?? ""
        codexReasoning = CodexReasoning(rawValue: store.string(forKey: "codexReasoning") ?? "") ?? .low
        microphoneUID = store.string(forKey: "microphoneUID") ?? ""
        soundsEnabled = store.bool(forKey: "soundsEnabled")
    }

    private func saveJSON<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
    }

    private static func loadJSON<T: Decodable>(_ type: T.Type, key: String, from defaults: UserDefaults) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
