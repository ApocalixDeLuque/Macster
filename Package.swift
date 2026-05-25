// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Macster",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Macster", targets: ["Macster"])
    ],
    targets: [
        .executableTarget(
            name: "Macster",
            path: "Sources/Macster"
        )
    ]
)
