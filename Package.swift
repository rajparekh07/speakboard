// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Speakboard",
    products: [
        .library(name: "SpeakboardCore", targets: ["SpeakboardCore"])
    ],
    targets: [
        .target(name: "SpeakboardCore"),
        // Test support: counts heap allocations, for the tests that prove a path allocates nothing.
        // Linked into the tests only, never into the core or its product.
        .target(name: "AllocationCounter", path: "Tests/AllocationCounter"),
        .testTarget(name: "SpeakboardCoreTests", dependencies: ["SpeakboardCore", "AllocationCounter"]),
    ]
)
