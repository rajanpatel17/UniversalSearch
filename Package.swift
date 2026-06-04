// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "UniversalSearchSDK",
    defaultLocalization: "en",
    platforms: [.iOS(.v16), .macOS(.v12)],
    products: [
        .library(name: "UniversalSearchSDK", targets: ["UniversalSearchSDK"]),
    ],
    dependencies: [
        .package(url: "https://github.com/livekit/client-sdk-swift.git", exact: "2.14.1"),
        .package(url: "https://github.com/SDWebImage/SDWebImage.git", from: "5.19.0"),
    ],
    targets: [
        .target(
            name: "UniversalSearchSDK",
            dependencies: [
                .product(name: "LiveKit", package: "client-sdk-swift"),
                .product(name: "SDWebImage", package: "SDWebImage"),
            ],
            path: "Sources/UniversalSearchSDK",
            exclude: [
                "UniversalSearchSDK.h",
            ],
            resources: [
                .process("Media.xcassets"),
                .process("AICall/AICallView/AICallView.xib"),
                .process("TermsNConditions/TermsAndConditionView.xib"),
                .process("Utility/FailureMessage/InstaQrAlertViewControllerViewController.xib"),
            ]
        ),
    ]
)
