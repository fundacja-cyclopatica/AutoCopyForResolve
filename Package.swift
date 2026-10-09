// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SDCardOrganizer",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "SDCardOrganizerCore", targets: ["SDCardOrganizerCore"]),
        .executable(name: "SDCardOrganizer", targets: ["SDCardOrganizer"]),
        .executable(name: "SDCardOrganizerSelftest", targets: ["SDCardOrganizerSelftest"])
    ],
    targets: [
        .target(
            name: "SDCardOrganizerCore"
        ),
        .executableTarget(
            name: "SDCardOrganizer",
            dependencies: ["SDCardOrganizerCore"]
        ),
        .executableTarget(
            name: "SDCardOrganizerSelftest",
            dependencies: ["SDCardOrganizerCore"]
        ),
        .testTarget(
            name: "SDCardOrganizerCoreTests",
            dependencies: ["SDCardOrganizerCore"]
        )
    ]
)
