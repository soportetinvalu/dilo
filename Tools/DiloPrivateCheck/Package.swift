// swift-tools-version: 5.9
import PackageDescription

// Paquete separado SOLO para la prueba privada cifrada. No forma parte de la app
// ni de Package.swift raíz; no admite fixtures públicas ni rutas de texto plano.
let package = Package(
    name: "DiloPrivateCheck",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.17.7"),
    ],
    targets: [
        .executableTarget(
            name: "DiloPrivateCheck",
            dependencies: [.product(name: "FluidAudio", package: "FluidAudio")],
            path: "Sources"
        ),
    ]
)
