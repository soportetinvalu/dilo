// Pruebas rápidas de la lógica que no depende de AppKit (se ejecutan con scripts/selftest.sh,
// en macOS o en Linux; no necesitan XCTest ni permisos).
import Foundation

var failures = 0
func check(_ condition: Bool, _ message: String) {
    if condition {
        print("  ok   \(message)")
    } else {
        print("  FALLA \(message)")
        failures += 1
    }
}

// MARK: HotkeyBinding

print("HotkeyBinding")
check(HotkeyBinding.default.displayName == "⌥ Option derecha", "la tecla por defecto es Option derecha")
check(HotkeyBinding(kind: .key, keyCode: 49, modifiers: ModifierMask.control | ModifierMask.option).displayName == "⌃⌥Espacio", "nombre de ⌃⌥Espacio")
check(HotkeyBinding(kind: .key, keyCode: 96).displayName == "F5", "nombre de F5")
check(HotkeyBinding.deviceMask(forModifierKeyCode: 61) == 0x40, "máscara de Option derecha")
check(HotkeyBinding.deviceMask(forModifierKeyCode: 58) == 0x20, "máscara de Option izquierda")
check(HotkeyBinding.deviceMask(forModifierKeyCode: 0) == nil, "la tecla A no es un modificador")
check(HotkeyBinding.isAllowedWithoutModifiers(96) && !HotkeyBinding.isAllowedWithoutModifiers(0), "F5 sí / A sola no")
let data = try! JSONEncoder().encode(HotkeyBinding(kind: .key, keyCode: 49, modifiers: ModifierMask.command))
check(try! JSONDecoder().decode(HotkeyBinding.self, from: data) == HotkeyBinding(kind: .key, keyCode: 49, modifiers: ModifierMask.command), "ida y vuelta JSON")

// MARK: PolishPrompt

print("PolishPrompt")
let prompt = PolishPrompt.build(for: "eh hola que tal")
check(prompt.contains("<dictado>\neh hola que tal\n</dictado>"), "el dictado va delimitado")
check(PolishPrompt.clean("  \"Hola, ¿qué tal?\"\n") == "Hola, ¿qué tal?", "quita comillas envolventes")
check(PolishPrompt.clean("```\nHola.\n```") == "Hola.", "quita bloque de código")
check(PolishPrompt.clean("<dictado>Hola.</dictado>") == "Hola.", "quita etiquetas")
check(PolishPrompt.clean("Dijo «hola» y se fue") == "Dijo «hola» y se fue", "no toca comillas internas")
check(PolishPrompt.looksSane(raw: "eh hola que tal estas", polished: "Hola, ¿qué tal estás?"), "respuesta razonable aceptada")
check(!PolishPrompt.looksSane(raw: "hola", polished: ""), "respuesta vacía rechazada")
check(!PolishPrompt.looksSane(raw: "cuánto es dos más dos", polished: "Dos más dos es cuatro, y además te cuento un dato curioso sobre las matemáticas y su historia."), "respuesta inventada rechazada")

// MARK: ProcessRunner (con un "codex" falso hecho con shell)

print("ProcessRunner")
let sema = DispatchSemaphore(value: 0)
Task {
    // 1) Eco por stdin
    let cat = try await ProcessRunner.run(
        executable: URL(fileURLWithPath: "/bin/cat"), arguments: [], stdin: "texto de prueba ñ", timeout: 5)
    check(cat.exitCode == 0 && cat.stdout == "texto de prueba ñ" && !cat.timedOut, "stdin → stdout sin pasar por un shell")

    // 2) Código de salida y stderr
    let fail = try await ProcessRunner.run(
        executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "echo malo >&2; exit 3"], timeout: 5)
    check(fail.exitCode == 3 && fail.stderr.contains("malo"), "código de salida y stderr")

    // 3) Tiempo máximo
    let started = Date()
    let slow = try await ProcessRunner.run(
        executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["10"], timeout: 1)
    check(slow.timedOut && Date().timeIntervalSince(started) < 6, "el tiempo máximo corta el proceso")

    // 4) Salida grande (más que el buffer de la tubería) sin bloquearse
    let big = try await ProcessRunner.run(
        executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "head -c 300000 /dev/zero | tr '\\0' a"], timeout: 10)
    check(big.stdout.count == 300_000, "salida de 300 KB leída completa")

    // 5) Un programa que no existe lanza error
    do {
        _ = try await ProcessRunner.run(executable: URL(fileURLWithPath: "/no/existe"), arguments: [], timeout: 2)
        check(false, "programa inexistente debería lanzar error")
    } catch {
        check(true, "programa inexistente lanza error")
    }
    sema.signal()
}
sema.wait()

print(failures == 0 ? "\nTodo bien." : "\n\(failures) prueba(s) fallaron.")
exit(failures == 0 ? 0 : 1)
