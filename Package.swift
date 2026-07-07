// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ObadhIOSSupport",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "ObadhKeyboardCore", targets: ["ObadhKeyboardCore"])
    ],
    targets: [
        .target(
            name: "ObadhKeyboardCore",
            path: "Shared/Sources",
            exclude: [
                "Design",
                "Keyboard/Emoji/EmojiPanelView.swift",
                "Keyboard/Emoji/EmojiVariantPopoverView.swift",
                "Keyboard/KeyboardDebugChannel.swift",
                "Keyboard/KeyboardFeedbackController.swift",
                "Keyboard/KeyboardKeyButton.swift",
                "Keyboard/KeyboardKeyPreviewCallout.swift",
                "Keyboard/KeyboardRowView.swift",
                "Keyboard/KeyboardTouchSurfaceView.swift",
                "Keyboard/SuggestionBarView.swift",
                "Engine/ObadhBridgeClient.swift"
            ]
        ),
        .testTarget(
            name: "ObadhKeyboardCoreTests",
            dependencies: ["ObadhKeyboardCore"]
        )
    ]
)
