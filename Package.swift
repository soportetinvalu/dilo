// swift-tools-version: 5.9
import PackageDescription

// Dilo — dictado por voz local para macOS (Apple Silicon).
// Un solo ejecutable de Swift Package; scripts/build.sh lo empaqueta como .app.
let package = Package(
    name: "DictadoMac",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Motor de voz → texto (Parakeet TDT 0.6B v3 sobre Core ML).
        // Versión fijada: la API se leyó del código de esta versión exacta.
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.17.7"),
    ],
    targets: [
        .executableTarget(
            name: "DictadoMac",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio"),
            ],
            path: "Sources/DictadoMac"
        ),
        .executableTarget(
            name: "DiloModelCheck",
            dependencies: [.product(name: "FluidAudio", package: "FluidAudio")],
            path: "Tools/DiloModelCheck"
        ),
    ]
)
