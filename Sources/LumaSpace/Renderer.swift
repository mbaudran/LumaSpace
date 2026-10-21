import AppKit
import LumaCore
import Metal
import MetalKit
import simd

/// Luma: 1920×1080, 52° diagonal field of view.
let lumaDiagonalFOV = 52.0 * Double.pi / 180

/// Vertical FOV (radians) for a view of the given aspect with the Luma's diagonal FOV.
func verticalFOV(aspect: Double) -> Double {
    let diag = tan(lumaDiagonalFOV / 2)
    return 2 * atan(diag / (aspect * aspect + 1).squareRoot())
}

private struct PanelUniforms {
    var mvp: simd_float4x4
    var aspect: Float
    var selected: Float
    var dim: Float
    var pad: Float = 0
}

extension Quat {
    var matrix: simd_float4x4 {
        simd_float4x4(simd_quatf(ix: Float(x), iy: Float(y), iz: Float(z), r: Float(w)).normalized)
    }
}

private func perspective(fovY: Float, aspect: Float, near: Float, far: Float) -> simd_float4x4 {
    let ys = 1 / tan(fovY / 2), xs = ys / aspect, zs = far / (near - far)
    return simd_float4x4(columns: (SIMD4(xs, 0, 0, 0), SIMD4(0, ys, 0, 0),
                                   SIMD4(0, 0, zs, -1), SIMD4(0, 0, zs * near, 0)))
}

private func translation(_ v: Vec3) -> simd_float4x4 {
    var m = matrix_identity_float4x4
    m.columns.3 = SIMD4(Float(v.x), Float(v.y), Float(v.z), 1)
    return m
}

private func scale(_ x: Double, _ y: Double) -> simd_float4x4 {
    simd_float4x4(diagonal: SIMD4(Float(x), Float(y), 1, 1))
}

@MainActor
final class Renderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    var scene: SpatialScene
    var headOrientation: () -> Quat = { .identity }
    var textureFor: (UUID) -> MTLTexture? = { _ in nil }
    var onFrame: ((MTLTexture, MTLCommandBuffer) -> Void)?
    /// A small ring at the centre of view while grabbing (⌃⌥ held).
    var showReticle = false
    private var labelCache: [String: MTLTexture] = [:]
    private lazy var reticle: MTLTexture? = makeReticle()

    init?(view: MTKView, scene: SpatialScene) {
        guard let device = view.device ?? MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else { return nil }
        do {
            let lib = try device.makeLibrary(source: shaderSource, options: nil)
            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = lib.makeFunction(name: "panelVertex")
            desc.fragmentFunction = lib.makeFunction(name: "panelFragment")
            let ca = desc.colorAttachments[0]!
            ca.pixelFormat = view.colorPixelFormat
            ca.isBlendingEnabled = true
            ca.sourceRGBBlendFactor = .sourceAlpha
            ca.destinationRGBBlendFactor = .oneMinusSourceAlpha
            ca.sourceAlphaBlendFactor = .one
            ca.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            pipeline = try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            NSLog("LumaSpace: shader setup failed: \(error)")
            return nil
        }
        self.device = device
        self.queue = queue
        self.scene = scene
        super.init()
        view.device = device
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)  // black = transparent on the glasses
        view.delegate = self
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func viewProjection(aspect: Double) -> simd_float4x4 {
        let proj = perspective(fovY: Float(verticalFOV(aspect: aspect)), aspect: Float(aspect), near: 0.05, far: 50)
        return proj * headOrientation().conjugate.matrix
    }

    func draw(in view: MTKView) {
        guard let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
              let cmd = queue.makeCommandBuffer(),
              let enc = cmd.makeRenderCommandEncoder(descriptor: pass) else { return }
        let size = view.drawableSize
        let vp = viewProjection(aspect: size.height > 0 ? Double(size.width / size.height) : 16.0 / 9)
        enc.setRenderPipelineState(pipeline)
        for p in scene.panels.sorted(by: { $0.distance > $1.distance }) {
            let model = translation(p.worldCenter())
                * Quat(yaw: p.yaw * .pi / 180, pitch: p.pitch * .pi / 180, roll: 0).matrix
                * scale(p.width, p.height)
            var u = PanelUniforms(mvp: vp * model, aspect: Float(p.aspect),
                                  selected: scene.selectedID == p.id ? 1 : 0,
                                  dim: p.available ? 0 : 0.35)
            let tex = (p.available ? textureFor(p.id) : nil) ?? label(for: p)
            enc.setVertexBytes(&u, length: MemoryLayout<PanelUniforms>.stride, index: 0)
            enc.setFragmentBytes(&u, length: MemoryLayout<PanelUniforms>.stride, index: 0)
            enc.setFragmentTexture(tex, index: 0)
            enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }
        if showReticle, let tex = reticle {
            let h = headOrientation()
            let model = translation(h.rotate(Vec3(x: 0, y: 0, z: -1))) * h.matrix * scale(0.03, 0.03)
            var u = PanelUniforms(mvp: vp * model, aspect: 1, selected: 0, dim: 0)
            enc.setVertexBytes(&u, length: MemoryLayout<PanelUniforms>.stride, index: 0)
            enc.setFragmentBytes(&u, length: MemoryLayout<PanelUniforms>.stride, index: 0)
            enc.setFragmentTexture(tex, index: 0)
            enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }
        enc.endEncoding()
        onFrame?(drawable.texture, cmd)
        cmd.present(drawable)
        cmd.commit()
    }

    private func makeReticle() -> MTLTexture? {
        let n = 64
        guard let ctx = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                      | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
        ctx.setStrokeColor(CGColor(red: 0.35, green: 0.65, blue: 1, alpha: 1))
        ctx.setLineWidth(6)
        ctx.strokeEllipse(in: CGRect(x: 8, y: 8, width: n - 16, height: n - 16))
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: n, height: n, mipmapped: false)
        guard let tex = device.makeTexture(descriptor: desc), let data = ctx.data else { return nil }
        tex.replace(region: MTLRegionMake2D(0, 0, n, n), mipmapLevel: 0, withBytes: data, bytesPerRow: n * 4)
        return tex
    }

    /// Placeholder card: the source name, or "Source unavailable" when it's gone.
    private func label(for p: Panel) -> MTLTexture? {
        let title = p.available ? p.source.label : "Source unavailable"
        let subtitle = p.available ? "" : p.source.label
        let key = "\(title)|\(subtitle)|\(Int(p.aspect * 100))"
        if let t = labelCache[key] { return t }
        let h = 540, w = max(1, Int(Double(h) * p.aspect))
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                      | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
        ctx.setFillColor(CGColor(red: 0.11, green: 0.11, blue: 0.14, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let big: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 44, weight: .semibold),
                                                  .foregroundColor: NSColor(white: 0.92, alpha: 1), .paragraphStyle: style]
        let small: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 26),
                                                    .foregroundColor: NSColor(white: 0.6, alpha: 1), .paragraphStyle: style]
        NSAttributedString(string: title, attributes: big)
            .draw(in: CGRect(x: 20, y: CGFloat(h) / 2 - 10, width: CGFloat(w - 40), height: 60))
        NSAttributedString(string: subtitle, attributes: small)
            .draw(in: CGRect(x: 20, y: CGFloat(h) / 2 - 60, width: CGFloat(w - 40), height: 40))
        NSGraphicsContext.restoreGraphicsState()
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
        guard let tex = device.makeTexture(descriptor: desc), let data = ctx.data else { return nil }
        tex.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0, withBytes: data, bytesPerRow: w * 4)
        labelCache[key] = tex
        return tex
    }
}
