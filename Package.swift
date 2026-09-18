// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "container-ui",
    platforms: [.macOS("26.0")],   // Liquid Glass (glassEffect, GlassEffectContainer)
    products: [
        .executable(name: "ContainerUI", targets: ["ContainerUI"]),
        .executable(name: "ctui", targets: ["ctui"]),
        .library(name: "ContainerKit", targets: ["ContainerKit"]),
    ],
    targets: [
        // Shared, UI-agnostic engine: process wrapper + Codable models.
        .target(name: "ContainerKit"),

        // Gorgeous SwiftUI window + menu-bar app.
        .executableTarget(
            name: "ContainerUI",
            dependencies: ["ContainerKit"]
        ),

        // Terminal companion (TUI).
        .executableTarget(
            name: "ctui",
            dependencies: ["ContainerKit"]
        ),
    ]
)
