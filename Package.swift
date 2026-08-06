// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VercelBar",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "VercelBarKit", targets: ["VercelBarKit"]),
        .executable(name: "vercelbar", targets: ["VercelBar"]),
        .executable(name: "vercelbar-tests", targets: ["vercelbar-tests"]),
    ],
    targets: [
        // Rdzeń: modele, klient API, logika stanów i powiadomień. AppKit tylko dla kolorów i ikony — bez widoków.
        .target(name: "VercelBarKit", swiftSettings: [.swiftLanguageMode(.v5)]),

        // Aplikacja paska menu (SwiftUI).
        .executableTarget(
            name: "VercelBar",
            dependencies: ["VercelBarKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),

        // Testy rdzenia jako wykonywalny runner (działa bez XCTest).
        .executableTarget(
            name: "vercelbar-tests",
            dependencies: ["VercelBarKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
