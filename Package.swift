// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "YaseenScreendraw",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "YaseenScreendraw", targets: ["YaseenScreendraw"]),
    ],
    targets: [
        // All the code lives in the library, so the tests can import it.
        .target(name: "ScreendrawKit"),
        .executableTarget(name: "YaseenScreendraw", dependencies: ["ScreendrawKit"]),
        .testTarget(name: "ScreendrawKitTests", dependencies: ["ScreendrawKit"]),
    ],
    // Swift 5 mode: CI uses an older compiler than the Mac of Yaseen.
    swiftLanguageModes: [.v5]
)
