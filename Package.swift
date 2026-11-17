// swift-tools-version: 6.0
import PackageDescription

/// 这个工程有两种使用方式，方便边用边学 Swift：
/// 1. 用 Xcode 打开 Package.swift，选择 Picmerge Scheme 直接 Run；
/// 2. 执行 Scripts/build-app.sh，一键生成带图标、可双击运行的 .app。
let package = Package(
    name: "Picmerge",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Picmerge", targets: ["Picmerge"])
    ],
    targets: [
        .executableTarget(
            name: "Picmerge",
            path: "Sources/Picmerge",
            // Resources 里放 Assets.xcassets，Xcode 会自动把它编译成应用图标。
            resources: [.process("Resources")]
        )
    ]
)
