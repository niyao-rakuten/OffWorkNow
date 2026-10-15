// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "OffWorkNow", platforms: [.macOS(.v13), .iOS(.v16)], products: [
    .library(name: "WorkdayCore", targets: ["WorkdayCore"]),
    .executable(name: "openrouter-debug", targets: ["OpenRouterDebug"])
], targets: [.target(name: "WorkdayCore", resources: [.process("Localization")]),
             .executableTarget(name: "OpenRouterDebug", dependencies: ["WorkdayCore"]),
             .testTarget(name: "WorkdayCoreTests", dependencies: ["WorkdayCore"])])
