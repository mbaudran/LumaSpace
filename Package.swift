// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "LumaSpace",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "LumaCore"),
        .target(name: "CGVirtualDisplayShim"),
        .executableTarget(name: "LumaChecks", dependencies: ["LumaCore"]),
        .executableTarget(
            name: "LumaSpace",
            dependencies: ["LumaCore", "CGVirtualDisplayShim"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("IOKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("CoreGraphics"),
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]
        ),
    ]
)
