import AppKit
import CoreGraphics
import os

/// Escucha la tecla de dictado en todo el sistema con un CGEventTap.
/// - Modificadores sueltos (Option derecha, etc.): se detectan por `flagsChanged`; el evento se deja pasar.
/// - Teclas normales / combinaciones: se "tragan" (la app activa no las recibe) para no escribir caracteres.
/// Requiere los permisos de Accesibilidad y Monitoreo de entrada; si faltan, reintenta cada 2 s.
@MainActor
final class HotkeyManager: ObservableObject {
    static let shared = HotkeyManager()

    /// true cuando el tap está creado y activo (es decir, los permisos están concedidos).
    @Published private(set) var isActive = false

    /// Mientras sea true se ignoran las teclas (lo usa el grabador de atajo de Ajustes).
    var isSuspended = false
    /// La tecla configurada. Se actualiza desde AppDelegate cuando cambia en Ajustes.
    var binding: HotkeyBinding = .default {
        didSet { holdState = .idle } // al cambiar de tecla se descarta cualquier pulsación en curso
    }

    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    /// Se pulsó otra tecla mientras se mantenía el modificador (p. ej. Option+E para escribir "é"):
    /// no era un dictado, hay que descartar la grabación.
    var onInterrupt: (() -> Void)?

    private enum HoldState { case idle, down, interrupted }

    private var holdState: HoldState = .idle
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var maintenanceTimer: Timer?
    private let log = Logger(subsystem: "local.dictado.DictadoMac", category: "Hotkey")

    private init() {}

    // MARK: Ciclo de vida

    /// Crea el tap. Si faltan permisos, queda reintentando en segundo plano.
    func start() {
        if maintenanceTimer == nil {
            maintenanceTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
                Task { @MainActor in HotkeyManager.shared.maintain() }
            }
        }
        createTapIfNeeded()
    }

    /// Cada 2 s: crea el tap si aún no existe, o lo reactiva si el sistema lo desactivó.
    private func maintain() {
        if let tap {
            if !CGEvent.tapIsEnabled(tap: tap) {
                CGEvent.tapEnable(tap: tap, enable: true)
                log.notice("Tap de teclado reactivado")
            }
        } else {
            createTapIfNeeded()
        }
    }

    private func createTapIfNeeded() {
        guard tap == nil else { return }

        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        guard let newTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: hotkeyTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            if isActive { isActive = false }
            return // faltan permisos; se reintenta en el siguiente ciclo
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)
        tap = newTap
        runLoopSource = source
        isActive = true
        log.notice("Tap de teclado creado")
    }

    // MARK: Procesamiento de eventos (hilo principal)

    /// Devuelve true si el evento debe "tragarse".
    fileprivate func handle(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        guard !isSuspended else { return false }

        let keyCode = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
        switch binding.kind {
        case .modifierKey: return handleModifierKey(type: type, keyCode: keyCode, event: event)
        case .key: return handleKey(type: type, keyCode: keyCode, event: event)
        }
    }

    private func handleModifierKey(type: CGEventType, keyCode: UInt16, event: CGEvent) -> Bool {
        switch type {
        case .flagsChanged:
            if keyCode == binding.keyCode, let mask = HotkeyBinding.deviceMask(forModifierKeyCode: keyCode) {
                let pressed = event.flags.rawValue & mask != 0
                if pressed && holdState == .idle {
                    holdState = .down
                    fire(onPress)
                } else if !pressed && holdState != .idle {
                    let wasDown = holdState == .down
                    holdState = .idle
                    if wasDown { fire(onRelease) }
                }
            } else if holdState == .down {
                // Se pulsó otro modificador mientras se mantenía el nuestro: es un atajo, no un dictado.
                holdState = .interrupted
                fire(onInterrupt)
            }
        case .keyDown:
            if holdState == .down {
                holdState = .interrupted
                fire(onInterrupt)
            }
        default:
            break
        }
        return false // los modificadores nunca se tragan
    }

    private func handleKey(type: CGEventType, keyCode: UInt16, event: CGEvent) -> Bool {
        guard keyCode == binding.keyCode else { return false }
        switch type {
        case .keyDown:
            guard event.flags.rawValue & ModifierMask.all == binding.modifiers else { return false }
            // Las repeticiones automáticas al mantener pulsada la tecla se ignoran (pero se tragan).
            if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return true }
            if holdState != .down {
                holdState = .down
                fire(onPress)
            }
            return true
        case .keyUp:
            guard holdState == .down else { return false }
            holdState = .idle
            fire(onRelease)
            return true
        default:
            return false
        }
    }

    /// Las acciones se lanzan en la siguiente vuelta del bucle para salir rápido del callback del tap
    /// (si el callback tarda, macOS desactiva el tap).
    private func fire(_ action: (() -> Void)?) {
        guard let action else { return }
        DispatchQueue.main.async { action() }
    }
}

/// Función C del tap. No puede capturar variables: recibe el HotkeyManager por `userInfo`.
private func hotkeyTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let manager = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()
    // El tap está en el run loop principal, así que ya estamos en el hilo principal.
    let swallow = MainActor.assumeIsolated { manager.handle(type: type, event: event) }
    return swallow ? nil : Unmanaged.passUnretained(event)
}
