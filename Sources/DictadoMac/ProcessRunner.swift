import Foundation

struct ProcessResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
    let timedOut: Bool
}

/// Caja mínima para pasar datos entre hilos sin errores de concurrencia.
private final class Box<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}

/// Ejecuta un programa externo con un tiempo máximo. Nunca pasa por un shell:
/// los argumentos van tal cual y el texto del usuario va por stdin.
enum ProcessRunner {
    static func run(
        executable: URL,
        arguments: [String],
        stdin: String? = nil,
        environment: [String: String]? = nil,
        workingDirectory: URL? = nil,
        timeout: TimeInterval
    ) async throws -> ProcessResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = executable
                process.arguments = arguments
                if let environment { process.environment = environment }
                if let workingDirectory { process.currentDirectoryURL = workingDirectory }

                let inPipe = Pipe()
                let outPipe = Pipe()
                let errPipe = Pipe()
                process.standardInput = inPipe
                process.standardOutput = outPipe
                process.standardError = errPipe

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }

                // stdin: se escribe y se cierra (SIGPIPE está ignorado en AppDelegate).
                if let stdin {
                    try? inPipe.fileHandleForWriting.write(contentsOf: Data(stdin.utf8))
                }
                try? inPipe.fileHandleForWriting.close()

                // stdout y stderr se leen en paralelo para que ninguna tubería se llene y bloquee al proceso.
                let outData = Box(Data())
                let errData = Box(Data())
                let group = DispatchGroup()
                group.enter()
                DispatchQueue.global().async {
                    outData.value = outPipe.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }
                group.enter()
                DispatchQueue.global().async {
                    errData.value = errPipe.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }

                // Tiempo máximo: si se cumple, se pide al proceso que termine (SIGTERM) y, si no
                // obedece en 2 s, se le obliga (SIGKILL).
                let timedOut = Box(false)
                let pid = process.processIdentifier
                let killer = DispatchWorkItem {
                    if process.isRunning {
                        timedOut.value = true
                        kill(pid, SIGTERM)
                        DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                            if process.isRunning { kill(pid, SIGKILL) }
                        }
                    }
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)

                process.waitUntilExit()
                killer.cancel()
                // Si un proceso hijo se queda con la tubería abierta, no esperamos eternamente.
                _ = group.wait(timeout: .now() + 3)

                continuation.resume(returning: ProcessResult(
                    exitCode: process.terminationStatus,
                    stdout: String(decoding: outData.value, as: UTF8.self),
                    stderr: String(decoding: errData.value, as: UTF8.self),
                    timedOut: timedOut.value
                ))
            }
        }
    }
}
