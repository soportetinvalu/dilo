// Ejecuta producción con un CLI sintético local: nunca inicia OAuth ni usa cuentas reales.
import Foundation

@main
struct CodexLoginTests {
    @MainActor static func main() async throws {
        var failures = 0
        var checks = 0
        func check(_ condition: Bool, _ message: String) {
            checks += 1
            if !condition { failures += 1 }
            print("\(condition ? "ok" : "FALLA") \(message)")
        }
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("dilo-login-tests-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let fake = root.appendingPathComponent("codex sintético")
        let calls = root.appendingPathComponent("calls")
        let state = root.appendingPathComponent("state")
        let mode = root.appendingPathComponent("mode")
        func write(_ url: URL, _ text: String) throws { try text.write(to: url, atomically: true, encoding: .utf8) }
        func read(_ url: URL) -> String { (try? String(contentsOf: url, encoding: .utf8)) ?? "" }
        try write(fake, #"""
        #!/bin/sh
        d="$(dirname "$0")"
        printf '%s\n' "$*" >> "$d/calls"
        if [ "$*" = 'login status' ]; then
          case "$(cat "$d/state")" in
            chatgpt) echo 'Logged in using ChatGPT' >&2; exit 0 ;;
            api) echo 'Logged in using an API key' >&2; exit 0 ;;
            bad) echo 'https://example.invalid/AUTH-SYNTHETIC-PRIVATE' >&2; exit 3 ;;
            unknown) echo 'Unknown authentication mode'; exit 0 ;;
            *) echo 'Not logged in' >&2; exit 1 ;;
          esac
        fi
        if [ "$*" = 'exec --help' ]; then
          [ "$(cat "$d/mode")" = helpfail ] && exit 2
          echo '--ephemeral --skip-git-repo-check --ignore-user-config'; exit 0
        fi
        [ "$#" = 1 ] && [ "$1" = login ] || exit 91
        echo $$ > "$d/pid"
        [ -z "${OPENAI_API_KEY+x}${CODEX_API_KEY+x}${CODEX_ACCESS_TOKEN+x}" ] || exit 92
        echo 'https://example.invalid/AUTH-SYNTHETIC-PRIVATE'
        echo 'AUTH-SYNTHETIC-PRIVATE' >&2
        case "$(cat "$d/mode")" in
          success) echo chatgpt > "$d/state"; exit 0 ;;
          bogus) exit 0 ;;
          fail) exit 7 ;;
          slow) exec /bin/sleep 30 ;;
          stubborn) trap '' TERM; exec /bin/sleep 30 ;;
          *) exit 8 ;;
        esac
        """#)
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fake.path)
        try write(state, "not")
        try write(mode, "success")
        let suite = "local.dilo.login-test.\(UUID().uuidString)"
        let store = UserDefaults(suiteName: suite)!
        defer { store.removePersistentDomain(forName: suite) }
        store.set(false, forKey: "polishEnabled")
        store.set(23.0, forKey: "polishTimeoutSeconds")
        store.set("modelo-personal", forKey: "codexModel")
        store.set(fake.path, forKey: "codexPath")
        let settings = AppSettings(store: store)
        let saved = store.persistentDomain(forName: suite)! as NSDictionary
        let polisher = TextPolisher(settings: settings)
        check(polisher.status == .unknown && !polisher.isConnecting && read(calls).isEmpty, "crear Dilo no inicia login ni procesos")
        await polisher.refreshStatus()
        check(polisher.status == .notLoggedIn && read(calls) == "login status\n", "comprobar no abre login")
        await polisher.connectChatGPT()
        check(polisher.status == .ready && polisher.isUsable && !polisher.isConnecting, "botón conecta con CLI sintético y relee estado")
        check(read(calls).components(separatedBy: "\n").filter { $0 == "login" }.count == 1, "solo una invocación login sin opciones")
        check(polisher.connectionMessage?.contains("Falta probar un dictado") == true, "no atribuye una petición real al estado local")
        check(saved.isEqual(store.persistentDomain(forName: suite)! as NSDictionary), "conectar conserva todos los ajustes persistidos y pulido apagado")
        let before = read(calls)
        await polisher.connectChatGPT()
        check(read(calls) == before + "login status\nexec --help\n", "sesión ChatGPT existente no se sustituye")
        try write(state, "api")
        let apiBefore = read(calls)
        await polisher.connectChatGPT()
        check(polisher.status == .usingAPIKey && !polisher.isUsable, "API key queda bloqueada")
        check(read(calls) == apiBefore + "login status\n", "no hace logout ni login sobre sesión API key")
        for invalid in ["bad", "unknown"] {
            try write(state, invalid)
            let before = read(calls)
            await polisher.connectChatGPT()
            if case .failed = polisher.status { check(true, "estado \(invalid) falla cerrado") }
            else { check(false, "estado \(invalid) falla cerrado") }
            check(read(calls) == before + "login status\n", "estado \(invalid) no abre OAuth")
            check(!polisher.status.summary.contains("AUTH-SYNTHETIC-PRIVATE"), "no muestra salida sensible de estado \(invalid)")
        }
        try write(state, "chatgpt"); try write(mode, "helpfail")
        await polisher.refreshStatus()
        check(!polisher.isUsable, "fallo de exec --help no se marca listo")
        for m in ["bogus", "fail"] {
            try write(state, "not"); try write(mode, m)
            await polisher.connectChatGPT()
            check(polisher.status == .notLoggedIn && !polisher.isConnecting && !polisher.isUsable, "login \(m) no afirma conexión")
            check(polisher.connectionMessage?.contains("No se pudo confirmar") == true, "login \(m) explica fallo sin salida del CLI")
        }
        try write(state, "not"); try write(mode, "slow")
        let pending = Task { await polisher.connectChatGPT() }
        // Esperar al CLI, no a un plazo que pueda adelantarse al preflight en CI.
        try? fm.removeItem(at: root.appendingPathComponent("pid"))
        for _ in 0..<200 {
            if fm.fileExists(atPath: root.appendingPathComponent("pid").path) { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        check(polisher.isConnecting && fm.fileExists(atPath: root.appendingPathComponent("pid").path), "conexión pendiente expone progreso")
        let during = read(calls)
        await polisher.connectChatGPT()
        await polisher.refreshStatus()
        check(read(calls) == during, "doble clic y refresco concurrente no lanzan procesos extra")
        polisher.cancelChatGPTConnection()
        await pending.value
        check(!polisher.isConnecting && polisher.connectionMessage?.contains("canceló") == true, "cancelación deja interfaz disponible")
        if let pid = Int32(read(root.appendingPathComponent("pid")).trimmingCharacters(in: .whitespacesAndNewlines)) {
            check(kill(pid, 0) != 0, "cancelar termina el proceso de login")
        } else { check(false, "PID sintético de cancelación presente") }

        let env = CodexInstallation.environment(for: fake, inherited: [
            "OPENAI_API_KEY": "synthetic", "CODEX_API_KEY": "synthetic", "CODEX_ACCESS_TOKEN": "synthetic",
            "PATH": "/bin:/bin", "CODEX_HOME": root.path,
        ])
        check(env["OPENAI_API_KEY"] == nil && env["CODEX_API_KEY"] == nil && env["CODEX_ACCESS_TOKEN"] == nil, "elimina claves y token heredados")
        check(env["PATH"]?.hasPrefix(root.path + ":") == true && env["CODEX_HOME"] == root.path, "PATH incluye binario y conserva hogar Codex del usuario")
        let login = CodexBrowserLogin()
        try write(mode, "stubborn")
        let start = ProcessInfo.processInfo.systemUptime
        let timeout = try await login.run(executable: fake, environment: env, workingDirectory: root, timeout: 0.1)
        check(timeout == .timedOut && ProcessInfo.processInfo.systemUptime - start < 6, "timeout termina incluso proceso que ignora SIGTERM")
        if let pid = Int32(read(root.appendingPathComponent("pid")).trimmingCharacters(in: .whitespacesAndNewlines)) {
            check(kill(pid, 0) != 0, "timeout no deja proceso vivo")
        }
        do {
            _ = try await login.run(executable: root.appendingPathComponent("missing"), environment: env, workingDirectory: root)
            check(false, "ejecutable inexistente debería fallar")
        } catch { check(true, "fallo de lanzamiento no bloquea continuación") }
        try write(mode, "success")
        let retry = try await login.run(executable: fake, environment: env, workingDirectory: root)
        check(retry == .exited(0), "se puede reintentar tras timeout y fallo de lanzamiento")
        let locatedCustom = await CodexInstallation.locate(customPath: fake.path, home: root.path)
        check(locatedCustom == fake, "ruta manual con espacios tiene prioridad")
        let invalidCustom = await CodexInstallation.locate(customPath: root.appendingPathComponent("missing").path, home: root.path)
        check(invalidCustom == nil, "ruta explícita inválida no se sustituye por otra cuenta/binario")
        let hermes = root.appendingPathComponent(".hermes/node/bin/codex")
        try fm.createDirectory(at: hermes.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.copyItem(at: fake, to: hermes)
        let locatedHermes = await CodexInstallation.locate(customPath: "", home: root.path)
        check(locatedHermes == hermes, "detecta ~/.hermes/node/bin/codex sin shell ni PATH")
        let local = root.appendingPathComponent(".local/bin/codex")
        try fm.createDirectory(at: local.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.copyItem(at: fake, to: local)
        let locatedLocal = await CodexInstallation.locate(customPath: "", home: root.path)
        check(locatedLocal == local, "conserva prioridad de rutas existentes")
        settings.codexPath = root.appendingPathComponent("missing").path
        await polisher.connectChatGPT()
        check(polisher.status == .notInstalled && !polisher.isConnecting, "ruta inexistente explica problema y permite reintentar")
        check(!read(calls).contains("logout"), "ningún caso cierra sesión")
        print("\(checks) comprobaciones; \(failures) fallos. CLI sintético, sin autenticación real.")
        exit(failures == 0 ? 0 : 1)
    }
}
