import AppKit
import ServiceManagement
import SwiftUI

/// Ventana de Ajustes: tecla, modo, pulido con ChatGPT, micrófono, permisos.
struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var transcriber: ParakeetTranscriber
    @ObservedObject var polisher: TextPolisher
    @ObservedObject var hotkeys: HotkeyManager

    @State private var microphones: [AudioInputDevice] = []
    @State private var permissionTick = 0 // se incrementa cada segundo para refrescar el estado de los permisos
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchError: String?
    private var codexBusy: Bool { polisher.isConnecting || polisher.status == .checking }

    var body: some View {
        Form {
            hotkeySection
            polishSection
            microphoneSection
            permissionsSection
            generalSection
        }
        .formStyle(.grouped)
        .frame(width: 580, height: 700)
        .onAppear { microphones = AudioDevices.inputDevices() }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            permissionTick += 1
        }
    }

    // MARK: Tecla

    private var hotkeySection: some View {
        Section("Tecla de dictado") {
            ShortcutRecorderView(binding: $settings.hotkey)

            Picker("Modo", selection: $settings.mode) {
                ForEach(DictationMode.allCases) { Text($0.label).tag($0) }
            }

            if !hotkeys.isActive {
                Text("La tecla no está activa. Revisa «Permisos» más abajo; si sigue sin responder tras concederlos, consulta LEEME CHRISTIAN.txt.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Text("Puedes usar un modificador solo (p. ej. Option derecha), una combinación (⌃⌥Espacio) o una tecla F. Si usas un modificador y pulsas otra tecla a la vez (p. ej. Option+E), la grabación se descarta.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Pulido

    private var polishSection: some View {
        Section("Pulido del texto con ChatGPT") {
            Toggle("Pulir el texto con ChatGPT (puntuación, mayúsculas, muletillas)", isOn: $settings.polishEnabled)

            if settings.polishEnabled {
                Stepper(value: $settings.polishTimeoutSeconds, in: 3...60, step: 1) {
                    Text("Si tarda más de \(Int(settings.polishTimeoutSeconds)) s, se inserta el texto sin pulir")
                }

                HStack {
                    Text("codex: \(polisher.status.summary)")
                        .font(.callout)
                        .foregroundStyle(polisher.status == .ready ? Color.green : Color.orange)
                    Spacer()
                    Button("Comprobar de nuevo") { Task { await polisher.refreshStatus() } }
                        .disabled(codexBusy)
                }

                HStack {
                    if polisher.isConnecting {
                        ProgressView().controlSize(.small)
                        Button("Cancelar conexión") { polisher.cancelChatGPTConnection() }
                    } else {
                        Button("Conectar ChatGPT") { Task { await polisher.connectChatGPT() } }
                            .disabled(codexBusy || polisher.status == .ready || polisher.status == .usingAPIKey)
                    }
                }
                if let message = polisher.connectionMessage {
                    Text(message).font(.caption).fixedSize(horizontal: false, vertical: true)
                }
                Text("La conexión se completa en tu navegador, sin Terminal. Dilo comprueba la sesión antes de abrirlo; no conectes otra cuenta desde otra app al mismo tiempo. Codex guarda la sesión en tu Mac; cancelar no cierra una sesión ya completada.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    TextField("Ruta de codex (vacío = automática)", text: $settings.codexPath)
                        .textFieldStyle(.roundedBorder)
                    Button("Elegir…") { chooseCodex() }
                }
                .disabled(codexBusy)
                Text("Detección automática: incluye ~/.hermes/node/bin/codex. Una ruta escrita tiene prioridad.")
                    .font(.caption).foregroundStyle(.secondary)
                TextField("Modelo (opcional, vacío = el predeterminado de codex)", text: $settings.codexModel)
                    .textFieldStyle(.roundedBorder)
                Picker("Esfuerzo de razonamiento", selection: $settings.codexReasoning) {
                    ForEach(CodexReasoning.allCases) { Text($0.label).tag($0) }
                }
                Text("Solo se envía el TEXTO transcrito (nunca el audio). Usa tu sesión de ChatGPT con el CLI codex; no se usa ninguna API key.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func chooseCodex() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Elige el ejecutable «codex»"
        if panel.runModal() == .OK, let url = panel.url {
            settings.codexPath = url.path
            Task { await polisher.refreshStatus() }
        }
    }

    // MARK: Micrófono

    private var microphoneSection: some View {
        Section("Micrófono") {
            Picker("Entrada de audio", selection: $settings.microphoneUID) {
                Text("Predeterminado del sistema").tag("")
                ForEach(microphones) { Text($0.name).tag($0.uid) }
                if !settings.microphoneUID.isEmpty && !microphones.contains(where: { $0.uid == settings.microphoneUID }) {
                    Text("(micrófono desconectado)").tag(settings.microphoneUID)
                }
            }
            Button("Actualizar lista") { microphones = AudioDevices.inputDevices() }
        }
    }

    // MARK: Permisos

    private var permissionsSection: some View {
        Section("Permisos") {
            let _ = permissionTick // vuelve a evaluar esta sección cada segundo

            permissionRow(
                title: "Micrófono",
                granted: Permissions.microphoneGranted,
                action: {
                    if Permissions.microphoneStatus == .notDetermined {
                        Task { _ = await Permissions.requestMicrophone() }
                    } else {
                        Permissions.openSystemSettings(.microphone)
                    }
                }
            )
            permissionRow(
                title: "Accesibilidad (pegar el texto)",
                granted: Permissions.accessibilityGranted,
                action: {
                    Permissions.requestAccessibility()
                    Permissions.openSystemSettings(.accessibility)
                }
            )
            permissionRow(
                title: "Monitoreo de entrada (leer la tecla)",
                granted: Permissions.inputMonitoringGranted,
                action: {
                    Permissions.requestInputMonitoring()
                    Permissions.openSystemSettings(.inputMonitoring)
                }
            )
            Text("Activa «Dilo» en Privacidad y seguridad. Si los permisos figuran activos pero no funcionan, sal de Dilo y, si el panel ofrece −/+, quita solo su entrada y añade la copia actual desde tu carpeta de usuario → Aplicaciones → Dilo. Quitar la entrada no elimina la app ni tus ajustes. En Micrófono, o sin −/+, desactiva y activa el permiso si es posible; vuelve a abrir Dilo y concédelo si se solicita. Consulta LEEME CHRISTIAN.txt para los pasos. No se restablecen permisos automáticamente y volver a concederlos no garantiza resolver el fallo.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func permissionRow(title: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(granted ? Color.green : Color.orange)
            Text(title)
            Spacer()
            if !granted { Button("Conceder…", action: action) }
        }
    }

    // MARK: General

    private var generalSection: some View {
        Section("General") {
            HStack {
                Text("Modelo de voz (Parakeet v3, español): \(transcriber.state.description)")
                    .font(.callout)
                Spacer()
                if case .failed = transcriber.state {
                    Button("Reintentar") { Task { await transcriber.prepare() } }
                }
            }
            Toggle("Sonido al empezar y terminar de grabar", isOn: $settings.soundsEnabled)
            Toggle("Abrir al iniciar sesión", isOn: Binding(
                get: { launchAtLogin },
                set: { setLaunchAtLogin($0) }
            ))
            if let launchError {
                Text(launchError).font(.caption).foregroundStyle(.red)
            }
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = enabled
            launchError = nil
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            launchError = "No se pudo cambiar: \(error.localizedDescription). Mueve la app a /Applications e inténtalo de nuevo."
        }
    }
}
