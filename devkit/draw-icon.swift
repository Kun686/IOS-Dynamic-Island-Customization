import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// A horizontal island and a single notification dot. All sizes use the same geometry.
func draw(size: Int, to path: String, type: UTType) throws {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                        bytesPerRow: size * 4, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    func color(_ red: Int, _ green: Int, _ blue: Int) -> CGColor {
        CGColor(srgbRed: CGFloat(red)/255, green: CGFloat(green)/255, blue: CGFloat(blue)/255, alpha: 1)
    }
    ctx.setFillColor(color(247, 245, 238))
    ctx.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
    ctx.setFillColor(color(28, 34, 32))
    ctx.addPath(CGPath(roundedRect: CGRect(x: 165, y: 403, width: 490, height: 218),
                       cornerWidth: 109, cornerHeight: 109, transform: nil))
    ctx.fillPath()
    ctx.setFillColor(color(219, 78, 48))
    ctx.fillEllipse(in: CGRect(x: 698, y: 427, width: 170, height: 170))
    let url = URL(fileURLWithPath: path)
    guard let image = ctx.makeImage(), let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)
    else { throw CocoaError(.fileWriteUnknown) }
    CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.98] as CFDictionary)
    guard CGImageDestinationFinalize(dest) else { throw CocoaError(.fileWriteUnknown) }
}
try draw(size: 1024, to: "Resources/icon.png", type: .png)
try draw(size: 1024, to: "supports/Assets.xcassets/AppIcon.appiconset/AppIcon.jpg", type: .jpeg)
