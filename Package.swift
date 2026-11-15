// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Speakboard",
    products: [
        .library(name: "SpeakboardCore", targets: ["SpeakboardCore"])
    ],
    targets: [
        .target(name: "SpeakboardCore"),
        .testTarget(name: "SpeakboardCoreTests", dependencies: ["SpeakboardCore"]),
    ]
)
