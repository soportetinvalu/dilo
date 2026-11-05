import Foundation
import Combine
import os

enum PolishOutcome {
    case polished(String)
    /// No se pudo pulir: se debe insertar el texto crudo. `reason` explica por qué.
    case fallback(reason: String)
}

/// Pule el texto dictado con ChatGPT a través del CLI oficial `codex` (sesión "Sign in with ChatGPT").
/// - Solo se envía el TEXTO transcrito; el audio nunca sale del Mac.
/// - No se usa ninguna API key: se quitan OPENAI_API_KEY/CODEX_API_KEY del entorno y,
///   si codex estuviera logueado con API key, el pulido se bloquea.
@MainActor
final class TextPolisher: ObservableObject {
    @Published private(set) var status: CodexStatus = .unknown
    @Published private(set) var isConnecting = false
    @Published private(set) var connectionMessage: String?
    private let browserLogin = CodexBrowserLogin()
    private var connectionCancelled = false

    private let settings: AppSettings
    private let log = Logger(subsystem: "local.dictado.DictadoMac", category: "Polisher")
    private var codexURL: URL?
    /// Opciones de `codex exec` que la versión instalada realmente admite.
    private var supportedFlags: [String] = []

    private let home: String
    private let inheritedEnvironment: [String: String]
    private let workDirectory: URL?

    init(settings: AppSettings, home: String = NSHomeDirectory(),
         environment: [String: String] = ProcessInfo.processInfo.environment,
         workDirectory: URL? = nil) {
        self.settings = settings
        self.home = home
        self.inheritedEnvironment = environment
        self.workDirectory = workDirectory
    }

    private func environment(for url: URL) -> [String: String] {
        CodexInstallation.environment(for: url, inherited: inheritedEnvironment, home: home)
    }

    var isUsable: Bool { !isConnecting && status == .ready && codexURL != nil }

    // MARK: Comprobación de instalación y login

    func refreshStatus() async {
        guard !isConnecting, status != .checking else { return }
        await checkStatus()
    }

    /// Nunca se llama al arrancar la app: únicamente desde el botón de Ajustes.
    func connectChatGPT() async {
        guard !isConnecting, status != .checking else { return }
        isConnecting = true
        connectionCancelled = false
        connectionMessage = nil
        defer { isConnecting = false }
        // Se relee la sesión justo antes de iniciar OAuth. Una sesión existente no se sustituye.
        await checkStatus()
        guard !connectionCancelled else { connectionMessage = "Conexión cancelada."; return }
        guard status == .notLoggedIn, let url = codexURL else {
            if status == .ready { connectionMessage = "Ya hay una sesión local de ChatGPT. No se ha cambiado la cuenta." }
            else if status == .usingAPIKey { connectionMessage = "Hay otra sesión de codex. Dilo no cierra ni sustituye cuentas existentes." }
            else { connectionMessage = "No se pudo iniciar la conexión: \(status.summary)." }
            return
        }
        connectionMessage = "Completa la conexión en tu navegador. Si no se abre, cancela y comprueba la instalación de codex."
        do {
            let outcome = try await browserLogin.run(
                executable: url, environment: environment(for: url),
                workingDirectory: workDirectory ?? Self.emptyWorkDirectory()
            )
            // La salida 0 del proceso no basta: volver a comprobar el tipo de sesión local.
            await checkStatus()
            switch outcome {
            case .exited(0) where status == .ready:
                connectionMessage = "Sesión local de ChatGPT conectada. Falta probar un dictado con pulido."
            case .cancelled:
                connectionMessage = "Se canceló la espera. No se ha cerrado ninguna sesión; comprueba el estado si terminaste en el navegador."
            case .timedOut:
                connectionMessage = "Se agotaron los 5 minutos de espera. Puedes volver a intentarlo."
            default:
                connectionMessage = "No se pudo confirmar la conexión. Revisa codex y vuelve a intentarlo; no se ha cerrado ninguna sesión."
            }
        } catch {
            connectionMessage = "No se pudo iniciar la conexión con codex. Revisa el ejecutable y vuelve a intentarlo."
        }
    }

    func cancelChatGPTConnection() {
        connectionCancelled = true
        browserLogin.cancel()
    }

    private func checkStatus() async {
        status = .checking
        guard let url = await CodexInstallation.locate(customPath: settings.codexPath, home: home) else {
            codexURL = nil
            status = .notInstalled
            return
        }
        codexURL = url
        let env = environment(for: url)
        do {
            let login = try await ProcessRunner.run(
                executable: url, arguments: ["login", "status"], environment: env, timeout: 20
            )
            let accountStatus = CodexStatus.fromLoginStatus(login)
            guard accountStatus == .ready else { status = accountStatus; return }
            let help = try await ProcessRunner.run(
                executable: url, arguments: ["exec", "--help"], environment: env, timeout: 20
            )
            guard !help.timedOut, help.exitCode == 0 else {
                status = .failed("codex no respondió al comprobar las opciones de pulido")
                return
            }
            let helpText = help.stdout + help.stderr
            supportedFlags = ["--skip-git-repo-check", "--ephemeral", "--ignore-user-config"]
                .filter { helpText.contains($0) }
            status = .ready
        } catch {
            // No propagar salida de autenticación, URLs ni detalles potencialmente sensibles.
            status = .failed("no se pudo ejecutar codex; revisa su ruta y permisos")
        }
    }

    // MARK: Pulido

    /// Nunca lanza errores: si algo falla devuelve `.fallback` y el llamador inserta el texto crudo.
    func polish(_ raw: String) async -> PolishOutcome {
        guard isUsable, let codex = codexURL else {
            return .fallback(reason: "codex no está listo (\(status.summary))")
        }
        let timeout = max(3, settings.polishTimeoutSeconds)

        let outFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("dictado-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: outFile) }

        // Directorio de trabajo vacío y propio: codex no ve ningún proyecto del usuario.
        let workDir = workDirectory ?? Self.emptyWorkDirectory()

        var args = ["exec"] + supportedFlags
        args += ["--sandbox", "read-only", "--color", "never", "-o", outFile.path, "-C", workDir.path]
        let reasoning = settings.codexReasoning.rawValue
        if !reasoning.isEmpty { args += ["-c", "model_reasoning_effort=\"\(reasoning)\""] }
        let model = settings.codexModel.trimmingCharacters(in: .whitespaces)
        if !model.isEmpty { args += ["-m", model] }
        args.append("-") // el prompt se lee de stdin (no aparece en la lista de procesos)

        do {
            let started = Date()
            let result = try await ProcessRunner.run(
                executable: codex, arguments: args,
                stdin: PolishPrompt.build(for: raw),
                environment: environment(for: codex),
                workingDirectory: workDir,
                timeout: timeout
            )
            let elapsed = Date().timeIntervalSince(started)

            if result.timedOut {
                return .fallback(reason: "codex tardó más de \(Int(timeout)) s")
            }
            if result.exitCode != 0 {
                let detail = result.stderr
                    .split(separator: "\n").map(String.init)
                    .last { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? "código \(result.exitCode)"
                return .fallback(reason: "codex falló: \(detail)")
            }

            let fromFile = (try? String(contentsOf: outFile, encoding: .utf8)) ?? ""
            let answer = PolishPrompt.clean(fromFile.isEmpty ? result.stdout : fromFile)
            guard PolishPrompt.looksSane(raw: raw, polished: answer) else {
                return .fallback(reason: "la respuesta de ChatGPT no parecía un texto corregido")
            }
            log.info("Pulido en \(elapsed, format: .fixed(precision: 1)) s")
            return .polished(answer)
        } catch {
            return .fallback(reason: "no se pudo ejecutar codex: \(error.localizedDescription)")
        }
    }

    // MARK: Utilidades

    private static func emptyWorkDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("DictadoMac/codex-vacio", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
