import Foundation
import os

/// Estado del CLI `codex` (ChatGPT), para el menú y Ajustes.
enum CodexStatus: Equatable {
    case unknown
    case checking
    case ready
    case notInstalled
    case notLoggedIn
    case usingAPIKey
    case failed(String)

    var summary: String {
        switch self {
        case .unknown: return "sin comprobar"
        case .checking: return "comprobando…"
        case .ready: return "listo (sesión de ChatGPT)"
        case .notInstalled: return "no está instalado — ejecuta: npm i -g @openai/codex"
        case .notLoggedIn: return "no has iniciado sesión — ejecuta en Terminal: codex login"
        case .usingAPIKey: return "está logueado con API key; ejecuta: codex logout && codex login (elige ChatGPT)"
        case .failed(let reason): return "error: \(reason)"
        }
    }
}

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

    private let settings: AppSettings
    private let log = Logger(subsystem: "local.dictado.DictadoMac", category: "Polisher")
    private var codexURL: URL?
    /// Opciones de `codex exec` que la versión instalada realmente admite.
    private var supportedFlags: [String] = []

    init(settings: AppSettings) {
        self.settings = settings
    }

    var isUsable: Bool { status == .ready && codexURL != nil }

    // MARK: Comprobación de instalación y login

    func refreshStatus() async {
        status = .checking
        guard let url = await locateCodex() else {
            codexURL = nil
            status = .notInstalled
            return
        }
        codexURL = url
        let env = Self.environment(for: url)
        do {
            // 1) ¿Hay sesión? `codex login status` termina con código 0 si hay sesión.
            let login = try await ProcessRunner.run(
                executable: url, arguments: ["login", "status"],
                environment: env, timeout: 20
            )
            if login.timedOut { status = .failed("codex no respondió al comprobar la sesión"); return }
            let text = (login.stdout + "\n" + login.stderr).lowercased()
            if login.exitCode != 0 { status = .notLoggedIn; return }
            if text.contains("api key") || text.contains("apikey") { status = .usingAPIKey; return }

            // 2) ¿Qué opciones admite esta versión de `codex exec`?
            let help = try await ProcessRunner.run(
                executable: url, arguments: ["exec", "--help"],
                environment: env, timeout: 20
            )
            let helpText = help.stdout + help.stderr
            supportedFlags = ["--skip-git-repo-check", "--ephemeral", "--ignore-user-config"]
                .filter { helpText.contains($0) }
            status = .ready
            log.info("codex listo en \(url.path, privacy: .public); opciones: \(self.supportedFlags.joined(separator: " "), privacy: .public)")
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    /// Busca el ejecutable: ruta de Ajustes → sitios habituales → el PATH de un shell de login.
    private func locateCodex() async -> URL? {
        let fm = FileManager.default

        let custom = (settings.codexPath as NSString).expandingTildeInPath.trimmingCharacters(in: .whitespaces)
        if !custom.isEmpty {
            return fm.isExecutableFile(atPath: custom) ? URL(fileURLWithPath: custom) : nil
        }

        let home = NSHomeDirectory()
        var candidates = [
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "\(home)/.local/bin/codex",
            "\(home)/.npm-global/bin/codex",
            "\(home)/.bun/bin/codex",
            "\(home)/.volta/bin/codex",
        ]
        // nvm: ~/.nvm/versions/node/<versión>/bin/codex
        let nvm = "\(home)/.nvm/versions/node"
        if let versions = try? fm.contentsOfDirectory(atPath: nvm) {
            candidates += versions.sorted().reversed().map { "\(nvm)/\($0)/bin/codex" }
        }
        if let found = candidates.first(where: { fm.isExecutableFile(atPath: $0) }) {
            return URL(fileURLWithPath: found)
        }

        // Último recurso: preguntarle al shell de login del usuario (carga su PATH).
        if let result = try? await ProcessRunner.run(
            executable: URL(fileURLWithPath: "/bin/zsh"),
            arguments: ["-lic", "command -v codex"],
            timeout: 8
        ) {
            let line = result.stdout
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .last { $0.hasPrefix("/") }
            if let line, fm.isExecutableFile(atPath: line) { return URL(fileURLWithPath: line) }
        }
        return nil
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
        let workDir = Self.emptyWorkDirectory()

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
                environment: Self.environment(for: codex),
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

    /// Entorno del subproceso: PATH con la carpeta de codex (necesita `node`) y sin API keys.
    private static func environment(for codex: URL) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "OPENAI_API_KEY")
        env.removeValue(forKey: "CODEX_API_KEY")
        let wanted = [codex.deletingLastPathComponent().path,
                      "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        let existing = (env["PATH"] ?? "").split(separator: ":").map(String.init)
        var seen = Set<String>()
        env["PATH"] = (wanted + existing).filter { seen.insert($0).inserted }.joined(separator: ":")
        env["HOME"] = NSHomeDirectory()
        return env
    }

    private static func emptyWorkDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("DictadoMac/codex-vacio", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
