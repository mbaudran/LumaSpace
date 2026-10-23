import Foundation

/// The VITURE library to install from an unpacked SDK: `aarch64/libglasses.dylib` when present,
/// else any `libglasses.dylib` that isn't inside an app bundle (the SDK's demo app carries a copy).
public func sdkLibraryPath(in files: [String]) -> String? {
    let libs = files.filter { ($0 as NSString).lastPathComponent == "libglasses.dylib" && !$0.contains(".app/") }
    return libs.first { $0.contains("/aarch64/") } ?? libs.first
}
