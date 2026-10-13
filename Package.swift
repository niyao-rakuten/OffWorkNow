// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "OffWorkNow", platforms: [.macOS(.v13), .iOS(.v16)], products: [
    .library(name: "WorkdayCore", targets: ["WorkdayCore"])
], targets: [.target(name: "WorkdayCore", resources: [.process("Localization")]), .testTarget(name: "WorkdayCoreTests", dependencies: ["WorkdayCore"])])
