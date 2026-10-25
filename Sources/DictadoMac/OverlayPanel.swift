import AppKit
import SwiftUI

enum OverlayMode: Equatable {
    case hidden
    case recording
    case transcribing
    case polishing
    case message(String)
}

@MainActor
final class OverlayModel: ObservableObject {
    @Published var mode: OverlayMode = .hidden
    /// Volumen del micrófono 0...1 (hace "latir" el punto rojo).
    @Published var level: Float = 0
}

/// Indicador flotante pequeño (abajo al centro). No roba el foco ni recibe clics.
@MainActor
final class OverlayController {
    private let model = OverlayModel()
    private var panel: NSPanel?
    private var hosting: NSHostingView<OverlayView>?
    private var hideTask: Task<Void, Never>?

    func show(_ mode: OverlayMode, autoHideAfter seconds: Double? = nil) {
        hideTask?.cancel()
        model.mode = mode
        model.level = 0
        ensurePanel()
        resizeAndPosition()
        panel?.orderFrontRegardless()
        // SwiftUI actualiza el contenido en la vuelta siguiente: se reajusta el tamaño entonces.
        Task { @MainActor [weak self] in self?.resizeAndPosition() }

        if let seconds {
            hideTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self?.hide()
            }
        }
    }

    func updateLevel(_ level: Float) {
        model.level = level
    }

    func hide() {
        hideTask?.cancel()
        model.mode = .hidden
        panel?.orderOut(nil)
    }

    private func ensurePanel() {
        guard panel == nil else { return }
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 44),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let hosting = NSHostingView(rootView: OverlayView(model: model))
        panel.contentView = hosting
        self.hosting = hosting
        self.panel = panel
    }

    /// Ajusta el tamaño al contenido y lo coloca abajo al centro de la pantalla donde está el ratón.
    private func resizeAndPosition() {
        guard let panel, let hosting else { return }
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        panel.setContentSize(size)

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let area = screen?.visibleFrame else { return }
        let origin = NSPoint(x: area.midX - size.width / 2, y: area.minY + 70)
        panel.setFrameOrigin(origin)
    }
}

private struct OverlayView: View {
    @ObservedObject var model: OverlayModel

    var body: some View {
        HStack(spacing: 10) {
            indicator
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 360, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Capsule().fill(Color.black.opacity(0.82)))
        .padding(6) // margen para que la sombra no se corte
    }

    @ViewBuilder
    private var indicator: some View {
        switch model.mode {
        case .recording:
            Circle()
                .fill(Color.red)
                .frame(width: 12, height: 12)
                .scaleEffect(1 + CGFloat(model.level) * 0.9)
                .animation(.easeOut(duration: 0.08), value: model.level)
        case .transcribing, .polishing:
            ProgressView()
                .controlSize(.small)
                .environment(\.colorScheme, .dark)
        case .message, .hidden:
            Image(systemName: "info.circle")
                .foregroundStyle(.white)
        }
    }

    private var label: String {
        switch model.mode {
        case .hidden: return ""
        case .recording: return "Grabando…"
        case .transcribing: return "Transcribiendo…"
        case .polishing: return "Puliendo con ChatGPT…"
        case .message(let text): return text
        }
    }
}
