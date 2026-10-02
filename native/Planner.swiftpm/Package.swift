// swift-tools-version: 5.8

// Swift Playgrounds app project (open this folder on an iPad in the Swift Playgrounds app).

import PackageDescription
import AppleProductTypes

let package = Package(
    name: "Planner",
    platforms: [
        .iOS("16.0")
    ],
    products: [
        .iOSApplication(
            name: "Planner",
            targets: ["AppModule"],
            bundleIdentifier: "com.joshualicona.weeklyplanner",
            teamIdentifier: "",
            displayVersion: "1.0",
            bundleVersion: "1",
            appIcon: .placeholder(icon: .calendar),
            accentColor: .presetColor(.blue),
            supportedDeviceFamilies: [
                .pad
            ],
            supportedInterfaceOrientations: [
                .portrait,
                .landscapeRight,
                .landscapeLeft,
                .portraitUpsideDown(.when(deviceFamilies: [.pad]))
            ]
        )
    ],
    targets: [
        .executableTarget(
            name: "AppModule",
            path: "."
        )
    ]
)
