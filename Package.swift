// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ZebraBrowserPrintEmulator",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "ZebraBrowserPrintEmulator", targets: ["ZebraBrowserPrintEmulator"])
    ],
    targets: [
        .executableTarget(
            name: "ZebraBrowserPrintEmulator",
            path: "Sources/ZebraBrowserPrintEmulator",
            exclude: ["AGENTS.md"]
        )
    ]
)
