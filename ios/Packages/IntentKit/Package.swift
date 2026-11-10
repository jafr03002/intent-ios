// swift-tools-version: 6.0

import PackageDescription

// Intent's modules. The app target (ios/Package.swift for xtool, ios/project.yml for
// Xcode on CI) is a thin shell that depends on these products.
//
// - IntentCore:   pure logic ported from artifacts/traintent/src/lib. Foundation only,
//                 no SwiftUI/UIKit, so `swift test` runs on Linux (WSL) and macOS.
// - IntentDesign: Sessions design system (tokens, Inter font, components).
// - IntentAPI:    typed client for the Express API, generated from lib/api-spec/openapi.yaml.
// - IntentAuth:   Clerk sign-in + session token provider for IntentAPI.
let package = Package(
    name: "IntentKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "IntentCore", targets: ["IntentCore"]),
        .library(name: "IntentDesign", targets: ["IntentDesign"]),
        .library(name: "IntentAPI", targets: ["IntentAPI"]),
        .library(name: "IntentAuth", targets: ["IntentAuth"]),
    ],
    dependencies: [
        // [api] runtime for the generated client (code generated ahead of time by
        // ios/scripts/generate-api.sh with swift-openapi-generator 1.14.3; no build plugin)
        .package(url: "https://github.com/apple/swift-openapi-runtime", from: "1.13.3"),
        .package(url: "https://github.com/apple/swift-openapi-urlsession", from: "1.4.0"),
        .package(url: "https://github.com/apple/swift-http-types", from: "1.8.0"),
        // [auth] Clerk iOS SDK (ClerkKit + prebuilt ClerkKitUI). Needs Swift 6.2+ / Xcode 26+.
        .package(url: "https://github.com/clerk/clerk-ios", .upToNextMinor(from: "1.6.2")),
    ],
    targets: [
        // [core]
        .target(name: "IntentCore"),
        // Fixtures/ holds the golden JSON from ios/scripts/core-fixtures (the web TS run for real).
        .testTarget(name: "IntentCoreTests", dependencies: ["IntentCore"], resources: [.copy("Fixtures")]),

        // [design]
        .target(name: "IntentDesign", resources: [.process("Resources")]),

        // [api]
        .target(
            name: "IntentAPI",
            dependencies: [
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession"),
                .product(name: "HTTPTypes", package: "swift-http-types"),
            ],
            // Mock backend data for FixtureTransport (-IntentMock); see ios/scripts/mock-fixtures.
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "IntentAPITests",
            dependencies: [
                "IntentAPI",
                .product(name: "HTTPTypes", package: "swift-http-types"),
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
            ]
        ),

        // [auth]
        // Clerk is linked on Apple platforms only, so `swift test` still builds the
        // whole package on Linux (WSL); there IntentAuth compiles without Clerk and
        // only its Clerk-free logic is tested.
        .target(
            name: "IntentAuth",
            dependencies: [
                .product(name: "ClerkKit", package: "clerk-ios",
                         condition: .when(platforms: [.iOS, .macOS])),
                .product(name: "ClerkKitUI", package: "clerk-ios",
                         condition: .when(platforms: [.iOS, .macOS])),
            ]
        ),
        .testTarget(name: "IntentAuthTests", dependencies: ["IntentAuth"]),
    ]
)
