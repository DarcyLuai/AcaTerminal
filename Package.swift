// swift-tools-version: 5.8
import PackageDescription
let package = Package(
    name: "AcaTerminal",
    defaultLocalization: "en",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [.library(name: "AcaCore", targets: ["AcaCore"]),
               .library(name: "AcaStorage", targets: ["AcaStorage"]),
               .library(name: "AcaConnectors", targets: ["AcaConnectors"]),
               .executable(name: "AcaTerminal", targets: ["AcaTerminal"])],
    targets: [.target(name: "AcaCore"),
              .systemLibrary(name: "CSQLite"),
              .target(name: "AcaStorage", dependencies: ["AcaCore", "CSQLite"]),
              .target(name: "AcaConnectors", dependencies: ["AcaCore"]),
              .executableTarget(name: "AcaTerminal", dependencies: ["AcaCore", "AcaStorage", "AcaConnectors"], resources: [.process("Resources")]),
              .executableTarget(name: "AcaChecks", dependencies: ["AcaCore", "AcaStorage", "AcaConnectors", "CSQLite"], path: "Tests/AcaChecks")])
