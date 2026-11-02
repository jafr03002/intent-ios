// swift-tools-version: 6.0

import PackageDescription

// Built two ways from the same sources:
// - xtool (WSL) for installs on a real iPhone: reads this file + xtool.yml.
// - Xcode on the GitHub macOS runner for the simulator: reads project.yml (XcodeGen).
// Keep the IntentKit product list here in sync with project.yml.
let package = Package(
    name: "Intent",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        // An xtool project contains exactly one library product: the app.
        .library(name: "Intent", targets: ["Intent"]),
    ],
    dependencies: [
        .package(path: "Packages/IntentKit"),
    ],
    targets: [
        .target(
            name: "Intent",
            dependencies: [
                .product(name: "IntentCore", package: "IntentKit"),
                .product(name: "IntentDesign", package: "IntentKit"),
                .product(name: "IntentAPI", package: "IntentKit"),
                .product(name: "IntentAuth", package: "IntentKit"),
            ]
        ),
    ]
)
