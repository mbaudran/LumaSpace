import Foundation
import LumaCore

func sdkSetupChecks() {
    check("picks the arm64 library from the SDK zip, not the demo app's copy") {
        let files = [
            "/x/demo/glasses-demo.app/Contents/Frameworks/libglasses.dylib",
            "/x/aarch64/libcarina_vio.dylib",
            "/x/aarch64/libglasses.dylib",
            "/x/include/viture_glasses.h",
        ]
        expectEqual(sdkLibraryPath(in: files), "/x/aarch64/libglasses.dylib")
    }
    check("falls back to any libglasses outside an app bundle") {
        expectEqual(sdkLibraryPath(in: ["/x/lib/libglasses.dylib", "/y/A.app/Contents/Frameworks/libglasses.dylib"]),
                    "/x/lib/libglasses.dylib")
    }
    check("no library means no SDK") {
        expectEqual(sdkLibraryPath(in: ["/x/readme.txt", "/x/A.app/Contents/Frameworks/libglasses.dylib"]), nil)
    }
}
