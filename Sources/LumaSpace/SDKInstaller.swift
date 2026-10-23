import Foundation
import LumaCore

/// Installs the VITURE libraries from the SDK the user downloaded. Release builds don't include
/// the SDK (it's VITURE's to distribute), so this is how a downloaded LumaSpace gets it.
enum SDKInstaller {
    enum Failure: LocalizedError {
        case unzip, noLibrary, resign
        var errorDescription: String? {
            switch self {
            case .unzip: "That zip couldn't be opened."
            case .resign: "The SDK libraries couldn't be signed for this Mac."
            case .noLibrary: "No libglasses.dylib found. Pick the \"VITURE XR Glasses SDK for macOS\" zip from viture.com/developer."
            }
        }
    }

    /// Accepts the SDK zip, its unzipped folder, or libglasses.dylib itself.
    static func install(from source: URL) throws {
        let fm = FileManager.default
        var root = source
        var temp: URL?
        defer { if let temp { try? fm.removeItem(at: temp) } }
        if source.pathExtension.lowercased() == "zip" {
            let dir = fm.temporaryDirectory.appendingPathComponent("lumaspace-sdk-\(UUID().uuidString)")
            let ditto = Process()
            ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            ditto.arguments = ["-x", "-k", source.path, dir.path]
            try ditto.run()
            ditto.waitUntilExit()
            guard ditto.terminationStatus == 0 else { throw Failure.unzip }
            root = dir
            temp = dir
        }
        var files = [root.path]
        if let e = fm.enumerator(at: root, includingPropertiesForKeys: nil) {
            files += e.compactMap { ($0 as? URL)?.path }
        }
        guard let lib = sdkLibraryPath(in: files) else { throw Failure.noLibrary }

        // Copy libglasses and the libraries next to it (libcarina_vio).
        let libDir = (lib as NSString).deletingLastPathComponent
        let dylibs = try fm.contentsOfDirectory(atPath: libDir).filter { $0.hasSuffix(".dylib") }
        try fm.createDirectory(at: VitureLibrary.installDir, withIntermediateDirectories: true)
        for name in dylibs {
            let dest = VitureLibrary.installDir.appendingPathComponent(name)
            try? fm.removeItem(at: dest)
            try fm.copyItem(atPath: (libDir as NSString).appendingPathComponent(name), toPath: dest.path)
            // A browser download is quarantined, and macOS kills an app that loads a quarantined library.
            removexattr(dest.path, "com.apple.quarantine", 0)
            // The SDK's libraries ship with a broken signature, which also gets the app killed; re-sign them.
            try resign(dest)
        }
    }

    private static func resign(_ file: URL) throws {
        let codesign = Process()
        codesign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        codesign.arguments = ["--force", "--sign", "-", file.path]
        codesign.standardError = FileHandle.nullDevice
        try codesign.run()
        codesign.waitUntilExit()
        guard codesign.terminationStatus == 0 else { throw Failure.resign }
    }
}
