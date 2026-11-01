// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Vigie",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Vigie",
            path: "Sources/Vigie",
            linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("ServiceManagement")]
        )
    ]
)
