import Foundation

/// Estado local: no acredita vigencia del token ni una petición real a ChatGPT.
enum CodexStatus: Equatable {
    case unknown, checking, ready, notInstalled, notLoggedIn, usingAPIKey
    case failed(String)

    var summary: String {
        switch self {
        case .unknown: return "sin comprobar"
        case .checking: return "comprobando…"
        case .ready: return "listo (sesión local de ChatGPT)"
        case .notInstalled: return "no se encontró codex; revisa la ruta o elige el ejecutable"
        case .notLoggedIn: return "sin sesión — pulsa «Conectar ChatGPT»"
        case .usingAPIKey: return "hay una sesión con API key; Dilo no la sustituirá ni la usará"
        case .failed(let reason): return "error: \(reason)"
        }
    }

    /// Fallo cerrado: un error de configuración no se interpreta como permiso para reemplazar sesión.
    static func fromLoginStatus(_ result: ProcessResult) -> CodexStatus {
        if result.timedOut { return .failed("codex no respondió al comprobar la sesión") }
        let text = (result.stdout + "\n" + result.stderr).lowercased()
        if result.exitCode == 0 {
            if text.contains("api key") || text.contains("apikey") { return .usingAPIKey }
            if text.contains("logged in using chatgpt") { return .ready }
        } else if text.trimmingCharacters(in: .whitespacesAndNewlines) == "not logged in" {
            return .notLoggedIn
        }
        return .failed("no se pudo reconocer el estado de sesión de codex; no se ha cambiado la cuenta")
    }
}

enum CodexInstallation {
    static func locate(customPath: String, home: String = NSHomeDirectory()) async -> URL? {
        let fm = FileManager.default
        let custom = (customPath as NSString).expandingTildeInPath.trimmingCharacters(in: .whitespaces)
        if !custom.isEmpty {
            return fm.isExecutableFile(atPath: custom) ? URL(fileURLWithPath: custom) : nil
        }
        var candidates = [
            "/opt/homebrew/bin/codex", "/usr/local/bin/codex",
            "\(home)/.local/bin/codex", "\(home)/.npm-global/bin/codex",
            "\(home)/.bun/bin/codex", "\(home)/.volta/bin/codex",
            "\(home)/.hermes/node/bin/codex",
        ]
        let nvm = "\(home)/.nvm/versions/node"
        if let versions = try? fm.contentsOfDirectory(atPath: nvm) {
            candidates += versions.sorted().reversed().map { "\(nvm)/\($0)/bin/codex" }
        }
        if let found = candidates.first(where: { fm.isExecutableFile(atPath: $0) }) {
            return URL(fileURLWithPath: found)
        }
        // Conserva la búsqueda histórica por el shell de login del usuario.
        if let result = try? await ProcessRunner.run(
            executable: URL(fileURLWithPath: "/bin/zsh"), arguments: ["-lic", "command -v codex"], timeout: 8
        ) {
            let line = result.stdout.split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }.last { $0.hasPrefix("/") }
            if let line, fm.isExecutableFile(atPath: line) { return URL(fileURLWithPath: line) }
        }
        return nil
    }

    static func environment(for codex: URL, inherited: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        var env = inherited
        for key in ["OPENAI_API_KEY", "CODEX_API_KEY", "CODEX_ACCESS_TOKEN"] { env.removeValue(forKey: key) }
        let wanted = [codex.deletingLastPathComponent().path,
                      "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        let existing = (env["PATH"] ?? "").split(separator: ":").map(String.init)
        var seen = Set<String>()
        env["PATH"] = (wanted + existing).filter { seen.insert($0).inserted }.joined(separator: ":")
        env["HOME"] = NSHomeDirectory()
        return env
    }
}

/// Solo inicia el OAuth oficial por una acción explícita de Ajustes. No pasa por Terminal ni shell.
/// stdout/stderr van directamente a /dev/null: Dilo no recibe URLs, códigos ni tokens del login.
@MainActor
final class CodexBrowserLogin {
    enum Outcome: Equatable { case exited(Int32), cancelled, timedOut }
    enum Failure: Error { case alreadyRunning }
    private var process: Process?
    private var continuation: CheckedContinuation<Outcome, Error>?
    private var timer: Task<Void, Never>?
    private var stopReason: Outcome?

    func run(executable: URL, environment: [String: String], workingDirectory: URL, timeout: TimeInterval = 300) async throws -> Outcome {
        guard process == nil else { throw Failure.alreadyRunning }
        return try await withCheckedThrowingContinuation { continuation in
            let child = Process()
            child.executableURL = executable
            child.arguments = ["login"] // Sin --with-api-key, --device-auth ni tokens.
            child.environment = environment
            child.currentDirectoryURL = workingDirectory
            child.standardInput = FileHandle.nullDevice
            child.standardOutput = FileHandle.nullDevice
            child.standardError = FileHandle.nullDevice
            child.terminationHandler = { [weak self] child in
                Task { @MainActor [weak self] in self?.finished(child) }
            }
            self.process = child
            self.continuation = continuation
            self.stopReason = nil
            do {
                try child.run()
                timer = Task { [weak self] in
                    do { try await Task.sleep(nanoseconds: UInt64(max(0.01, timeout) * 1_000_000_000)) }
                    catch { return }
                    self?.stop(.timedOut)
                }
            } catch {
                self.process = nil
                self.continuation = nil
                continuation.resume(throwing: error)
            }
        }
    }

    func cancel() { stop(.cancelled) }

    private func stop(_ reason: Outcome) {
        guard let process, process.isRunning, stopReason == nil else { return }
        stopReason = reason
        process.terminate()
        Task { [weak process] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if let process, process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
    }

    private func finished(_ child: Process) {
        guard process === child else { return }
        timer?.cancel()
        timer = nil
        process = nil
        let continuation = self.continuation
        self.continuation = nil
        continuation?.resume(returning: stopReason ?? .exited(child.terminationStatus))
    }
}
