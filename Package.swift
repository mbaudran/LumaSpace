// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "LumaSpace",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "LumaCore"),
        .executableTarget(name: "LumaChecks", dependencies: ["LumaCore"]),
        .executableTarget(
            name: "LumaSpace",
            dependencies: ["LumaCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("IOKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreVideo"),
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]
        ),
    ]
)
