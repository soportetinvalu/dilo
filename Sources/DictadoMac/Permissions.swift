import AVFoundation
import AppKit
import ApplicationServices
import CoreGraphics

/// Los tres permisos que necesita la app y cómo pedirlos / abrir su panel en Ajustes del Sistema.
enum Permissions {
    enum Pane: String {
        case microphone = "Privacy_Microphone"
        case accessibility = "Privacy_Accessibility"
        case inputMonitoring = "Privacy_ListenEvent"
    }

    // MARK: Estado

    static var microphoneStatus: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }
    static var microphoneGranted: Bool { microphoneStatus == .authorized }

    /// Accesibilidad: necesaria para enviar ⌘V y para el tap de teclado.
    static var accessibilityGranted: Bool { AXIsProcessTrusted() }

    /// Monitoreo de entrada: necesario para leer teclas globales.
    static var inputMonitoringGranted: Bool { CGPreflightListenEventAccess() }

    // MARK: Solicitud

    static func requestMicrophone() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    static func requestAccessibility() {
        // "AXTrustedCheckOptionPrompt" es el valor de kAXTrustedCheckOptionPrompt.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func requestInputMonitoring() {
        _ = CGRequestListenEventAccess()
    }

    static func openSystemSettings(_ pane: Pane) {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane.rawValue)")!
        NSWorkspace.shared.open(url)
    }
}
