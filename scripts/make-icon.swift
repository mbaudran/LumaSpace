// Draws LumaSpace's icon: a white line drawing of glasses on black.
// `scripts/make-icon.sh` turns it into Resources/AppIcon.icns.
// Usage: swift scripts/make-icon.swift <out.png>
import AppKit
import CoreGraphics

let size = 1024.0
let out = CommandLine.arguments.dropFirst().first ?? "icon.png"
let space = CGColorSpace(name: CGColorSpace.displayP3)!
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
// Top-left origin, y down, like a design tool.
ctx.translateBy(x: 0, y: size)
ctx.scaleBy(x: 1, y: -1)

func rgb(_ hex: UInt32, _ a: Double = 1) -> CGColor {
    CGColor(colorSpace: space, components: [Double(hex >> 16 & 0xff) / 255, Double(hex >> 8 & 0xff) / 255,
                                            Double(hex & 0xff) / 255, a])!
}
func gradient(_ stops: [(Double, CGColor)]) -> CGGradient {
    CGGradient(colorsSpace: space, colors: stops.map { $0.1 } as CFArray, locations: stops.map { CGFloat($0.0) })!
}

// The tile: Apple's 824 pt body on a 1024 canvas, with a soft drop shadow.
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let body = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: rgb(0x000000, 0.45))
ctx.addPath(body); ctx.setFillColor(rgb(0x000000)); ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(body); ctx.clip()
ctx.drawLinearGradient(gradient([(0, rgb(0x262626)), (1, rgb(0x000000))]),
                       start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])

let white = rgb(0xffffff)
let lensW = 290.0, lensH = 230.0, gap = 84.0, line = 34.0
let top = 512 - lensH / 2 + 10
let left = CGRect(x: 512 - gap / 2 - lensW, y: top, width: lensW, height: lensH)
let right = CGRect(x: 512 + gap / 2, y: top, width: lensW, height: lensH)

// The glasses: two rounded lenses and an arched bridge, one line weight.
ctx.setStrokeColor(white); ctx.setLineWidth(line); ctx.setLineCap(.round); ctx.setLineJoin(.round)
for r in [left, right] {
    ctx.addPath(CGPath(roundedRect: r, cornerWidth: 96, cornerHeight: 96, transform: nil))
}
ctx.move(to: CGPoint(x: left.maxX, y: top + 52))
ctx.addQuadCurve(to: CGPoint(x: right.minX, y: top + 52), control: CGPoint(x: 512, y: top + 6))
ctx.strokePath()

ctx.restoreGState()

let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
