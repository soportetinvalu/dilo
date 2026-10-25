import AppKit

/// Punto de entrada. App de barra de menú sin ventana principal (LSUIElement en Info.plist).
@main
enum DictadoMacApp {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate // `delegate` sigue vivo porque run() no vuelve hasta salir
        app.run()
    }
}
