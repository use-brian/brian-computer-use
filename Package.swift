// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BrianComputerUse",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Brian", targets: ["BrianApp"]),
        .executable(name: "brian-runtime-host", targets: ["BrianRuntimeHost"]),
    ],
    targets: [
        .target(name: "BrianCore"),
        .executableTarget(name: "BrianApp", dependencies: ["BrianCore"]),
        .executableTarget(name: "BrianRuntimeHost"),
        .testTarget(name: "BrianCoreTests", dependencies: ["BrianCore"]),
    ]
)
