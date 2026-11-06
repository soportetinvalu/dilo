import Combine

/// Un único resultado en RAM. No conserva audio, errores del CLI ni historial.
@MainActor
final class LastDictationComparison: ObservableObject {
    enum PolishStep: Equatable {
        case completed
        case disabled
        case fallback

        var summary: String {
            switch self {
            case .completed: return "ChatGPT completó el pulido; se usó su respuesta."
            case .disabled: return "Pulido desactivado; no se pidió una respuesta a ChatGPT."
            case .fallback: return "No se usó una respuesta de ChatGPT; se conservó el texto anterior."
            }
        }

        var afterTitle: String {
            self == .completed ? "Después de ChatGPT (texto usado)" : "Texto usado (sin pulir)"
        }
    }

    struct Snapshot: Equatable {
        let raw: String
        let finalText: String
        let step: PolishStep
    }

    @Published private(set) var snapshot: Snapshot?

    func capture(raw: String, finalText: String, step: PolishStep) {
        // Un resultado vacío nunca debe dejar visible un dictado anterior.
        snapshot = raw.isEmpty ? nil : Snapshot(raw: raw, finalText: finalText, step: step)
    }

    func clear() {
        if snapshot != nil { snapshot = nil }
    }
}
