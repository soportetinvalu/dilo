import Foundation
import Darwin

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
    // Las costuras de rutas/shell permiten probar la precedencia sin consultar el host.
    static func locate(
        customPath: String, home: String = NSHomeDirectory(),
        systemCandidates: [String] = ["/opt/homebrew/bin/codex", "/usr/local/bin/codex"],
        shellLookup: () async -> String? = loginShellPath
    ) async -> URL? {
        let fm = FileManager.default
        let trimmed = customPath.trimmingCharacters(in: .whitespaces)
        let custom = trimmed.hasPrefix("~/") ? home + String(trimmed.dropFirst()) : trimmed
        if !custom.isEmpty {
            return fm.isExecutableFile(atPath: custom) ? URL(fileURLWithPath: custom) : nil
        }
        var candidates = systemCandidates + [
            "\(home)/.local/bin/codex", "\(home)/.npm-global/bin/codex",
            "\(home)/.bun/bin/codex", "\(home)/.volta/bin/codex",
        ]
        let nvm = "\(home)/.nvm/versions/node"
        if let versions = try? fm.contentsOfDirectory(atPath: nvm) {
            candidates += versions.sorted().reversed().map { "\(nvm)/\($0)/bin/codex" }
        }
        if let found = candidates.first(where: { fm.isExecutableFile(atPath: $0) }) {
            return URL(fileURLWithPath: found)
        }
        // El fallback nuevo va DESPUÉS del shell: no cambia el Codex/cuenta elegido antes.
        if let path = await shellLookup(), fm.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        let hermes = "\(home)/.hermes/node/bin/codex"
        return fm.isExecutableFile(atPath: hermes) ? URL(fileURLWithPath: hermes) : nil
    }

    static func loginShellPath() async -> String? {
        if let result = try? await ProcessRunner.run(
            executable: URL(fileURLWithPath: "/bin/zsh"), arguments: ["-lic", "command -v codex"], timeout: 8
        ) {
            return result.stdout.split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }.last { $0.hasPrefix("/") }
        }
        return nil
    }

    static func environment(
        for codex: URL, inherited: [String: String] = ProcessInfo.processInfo.environment,
        home: String = NSHomeDirectory()
    ) -> [String: String] {
        var env = inherited
        for key in ["OPENAI_API_KEY", "CODEX_API_KEY", "CODEX_ACCESS_TOKEN"] { env.removeValue(forKey: key) }
        let wanted = [codex.deletingLastPathComponent().path,
                      "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        let existing = (env["PATH"] ?? "").split(separator: ":").map(String.init)
        var seen = Set<String>()
        env["PATH"] = (wanted + existing).filter { seen.insert($0).inserted }.joined(separator: ":")
        env["HOME"] = home
        return env
    }
}

/// Solo inicia el OAuth oficial por una acción explícita de Ajustes. No pasa por Terminal ni shell.
/// stdout/stderr van directamente a /dev/null: Dilo no recibe URLs, códigos ni tokens del login.
@MainActor
final class CodexBrowserLogin {
    enum Outcome: Equatable { case exited(Int32), cancelled, timedOut }
    enum Failure: Error { case alreadyRunning }
    private var pid: pid_t?
    private var continuation: CheckedContinuation<Outcome, Error>?
    private var timer: Task<Void, Never>?
    private var stopReason: Outcome?

    func run(executable: URL, environment: [String: String], workingDirectory: URL, timeout: TimeInterval = 300) async throws -> Outcome {
        guard pid == nil else { throw Failure.alreadyRunning }
        // El grupo se crea ATÓMICAMENTE antes de ejecutar el wrapper/CLI: no hay ventana
        // run() → setpgid(). Ninguna señal se envía al grupo de Dilo ni a otro Codex.
        let child = try Self.spawn(executable, environment, workingDirectory)
        pid = child
        stopReason = nil
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            timer = Task { [weak self] in
                do { try await Task.sleep(nanoseconds: UInt64(max(0.01, timeout) * 1_000_000_000)) }
                catch { return }
                self?.stop(.timedOut)
            }
            DispatchQueue.global(qos: .utility).async {
                var info = siginfo_t()
                var result: Int32
                // WNOWAIT conserva el PID hasta recoger el grupo en el actor principal;
                // así no puede reutilizarse mientras cancel()/finished() envían señales.
                repeat { result = waitid(P_PID, id_t(child), &info, WEXITED | WNOWAIT) } while result == -1 && errno == EINTR
                Task { @MainActor in self.finished(child) }
            }
        }
    }

    private static func spawn(_ executable: URL, _ environment: [String: String], _ directory: URL) throws -> pid_t {
        func checked(_ code: Int32) throws {
            if code != 0 { throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO) }
        }
        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        try checked(posix_spawn_file_actions_init(&actions))
        defer { posix_spawn_file_actions_destroy(&actions) }
        try checked(posix_spawnattr_init(&attributes))
        defer { posix_spawnattr_destroy(&attributes) }
        try checked(posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT)))
        try checked(posix_spawnattr_setpgroup(&attributes, 0))
        try checked(posix_spawn_file_actions_addchdir_np(&actions, directory.path))
        for descriptor in Int32(0)...Int32(2) {
            try checked(posix_spawn_file_actions_addopen(&actions, descriptor, "/dev/null", descriptor == 0 ? O_RDONLY : O_WRONLY, 0))
        }
        // Sin shell, --with-api-key, --device-auth ni tokens.
        let argv: [UnsafeMutablePointer<CChar>?] = [executable.path, "login"].map { (value: String) in
            value.withCString { strdup($0) }
        } + [nil]
        let envp: [UnsafeMutablePointer<CChar>?] = environment.map { entry in
            "\(entry.key)=\(entry.value)".withCString { strdup($0) }
        } + [nil]
        defer { for pointer in argv + envp { free(pointer) } }
        var child: pid_t = 0
        try argv.withUnsafeBufferPointer { args in
            try envp.withUnsafeBufferPointer { env in
                try checked(posix_spawn(&child, executable.path, &actions, &attributes,
                                        UnsafeMutablePointer(mutating: args.baseAddress!),
                                        UnsafeMutablePointer(mutating: env.baseAddress!)))
            }
        }
        return child
    }

    func cancel() { stop(.cancelled) }

    private func stop(_ reason: Outcome) {
        guard let pid, stopReason == nil else { return }
        stopReason = reason
        // OAuth no requiere vaciar buffers: cortar TODO el grupo evita que un wrapper
        // muera primero y deje un hijo que ignore TERM guardando una sesión más tarde.
        kill(-pid, SIGKILL)
    }

    private func finished(_ child: pid_t) {
        guard pid == child else { return }
        // También recoge descendientes del grupo si un wrapper terminó antes que ellos.
        kill(-child, SIGKILL)
        var status: Int32 = 0
        var result: pid_t
        repeat { result = waitpid(child, &status, 0) } while result == -1 && errno == EINTR
        let exitCode = result == child && status & 0x7f == 0 ? (status >> 8) & 0xff : -1
        timer?.cancel()
        timer = nil
        pid = nil
        let continuation = self.continuation
        self.continuation = nil
        continuation?.resume(returning: stopReason ?? .exited(exitCode))
    }
}
