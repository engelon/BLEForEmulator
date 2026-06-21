// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BLEForEmulator",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "BLEForEmulator", targets: ["BLEForEmulatorMac"])
    ],
    targets: [
        .executableTarget(
            name: "BLEForEmulatorMac",
            path: "Sources/BLEForEmulatorMac"
            // Info.plist is picked up automatically by Xcode when opening Package.swift
            // as long as it lives alongside the source files in this directory
        )
    ]
)
