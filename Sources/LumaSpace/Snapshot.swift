import AppKit
@preconcurrency import Metal
import MetalKit

/// Debug aid: `LUMA_SNAPSHOT=/path.png` writes the 30th rendered frame to a PNG and quits.
@MainActor
enum Snapshot {
    static func installIfRequested(renderer: Renderer, view: MTKView) {
        guard let path = ProcessInfo.processInfo.environment["LUMA_SNAPSHOT"] else { return }
        view.framebufferOnly = false
        var frames = 0
        renderer.onFrame = { texture, cmd in
            frames += 1
            guard frames == 30 else { return }
            let w = texture.width, h = texture.height
            cmd.addCompletedHandler { _ in
                var bytes = [UInt8](repeating: 0, count: w * h * 4)
                texture.getBytes(&bytes, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
                let ctx = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
                if let img = ctx?.makeImage(),
                   let data = NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:]) {
                    try? data.write(to: URL(fileURLWithPath: path))
                }
                DispatchQueue.main.async { NSApp.terminate(nil) }
            }
        }
    }
}
