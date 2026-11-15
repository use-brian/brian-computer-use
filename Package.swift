// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BrianComputerUse",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Brian", targets: ["BrianApp"])],
    targets: [
        .target(name: "BrianCore"),
        .executableTarget(name: "BrianApp", dependencies: ["BrianCore"]),
        .testTarget(name: "BrianCoreTests", dependencies: ["BrianCore"]),
    ]
)
