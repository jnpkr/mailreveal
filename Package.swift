// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MailReveal",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "MailReveal", targets: ["MailReveal"]),
    ],
    targets: [
        .executableTarget(name: "MailReveal"),
        .testTarget(
            name: "MailRevealTests",
            dependencies: ["MailReveal"]
        ),
    ]
)
