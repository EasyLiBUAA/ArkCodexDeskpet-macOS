// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ArkCodexDeskpet",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "ArkCodexDeskpet", targets: ["ArkCodexDeskpet"])],
    targets: [
        .executableTarget(
            name: "ArkCodexDeskpet",
            resources: [.copy("pets")]
        )
    ]
)
