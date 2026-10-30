import Foundation
import LumaCore
import Metal

/// `LumaSpace --cinema-bench`: renders the cinema off screen at the glasses' 3D size (3840×1200),
/// with the animated test picture, and prints the GPU time per frame at each ambience level.
/// At 90 Hz a frame has 11.1 ms.
@MainActor
enum CinemaBench {
    static let width = 3840, height = 1200, frames = 200

    static func run() -> Int32 {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
              let cinema = CinemaRenderer(device: device, colorPixelFormat: .bgra8Unorm) else {
            print("error: Metal or the cinema shaders aren't available")
            return 1
        }
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        d.usage = .renderTarget
        d.storageMode = .private
        guard let target = device.makeTexture(descriptor: d) else { return 1 }
        cinema.testClip = true
        print("gpu: \(device.name), \(width)x\(height) side by side")
        // The first level is run twice: the GPU needs a moment to clock up.
        for (i, a) in ([Ambience.full] + Ambience.allCases).enumerated() {
            cinema.settings.ambience = a
            // Keep the GPU busy like a real 90 Hz loop: queue every frame, then read the timings.
            var buffers: [MTLCommandBuffer] = []
            for _ in 0..<frames {
                guard let cmd = queue.makeCommandBuffer() else { return 1 }
                let pass = MTLRenderPassDescriptor()
                pass.colorAttachments[0].texture = target
                pass.colorAttachments[0].loadAction = .dontCare
                pass.colorAttachments[0].storeAction = .store
                cinema.encode(into: pass, drawableSize: CGSize(width: width, height: height), head: .identity, commandBuffer: cmd)
                cmd.commit()
                buffers.append(cmd)
            }
            buffers.last?.waitUntilCompleted()
            // Frames overlap on the GPU, so per-frame spans mislead; time the whole run instead.
            let measured = buffers.dropFirst(20)
            guard let first = measured.first, let last = measured.last else { return 1 }
            let ms = (last.gpuEndTime - first.gpuStartTime) * 1000 / Double(measured.count)
            if i == 0 { continue }
            print("ambience \(a.rawValue): \(String(format: "%.2f", ms)) ms per frame")
        }
        return 0
    }
}
