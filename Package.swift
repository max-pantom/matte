// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Matte",
    platforms: [.macOS("14.0")],
    products: [
        .library(name: "MatteCore", targets: ["MatteCore"]),
        .executable(name: "Matte", targets: ["Matte"]),
        .executable(name: "matte-cli", targets: ["matte-cli"]),
    ],
    targets: [
        .target(name: "MatteCore"),
        .executableTarget(
            name: "Matte",
            dependencies: ["MatteCore"],
            resources: [.copy("Resources")]
        ),
        .executableTarget(name: "matte-cli", dependencies: ["MatteCore"]),
    ]
)
