import AppKit
// 用法: contact.swift out.png cropHeightPx columns scale file...
// 取每张截图顶部 cropHeightPx 像素，带文件名标签拼成一张
let a = CommandLine.arguments
let out = a[1], cropH = CGFloat(Double(a[2])!), cols = Int(a[3])!, scale = CGFloat(Double(a[4])!)
let files = Array(a[5...])
let imgs = files.compactMap { NSImage(contentsOfFile: $0)?.cgImage(forProposedRect: nil, context: nil, hints: nil) }
guard let first = imgs.first else { exit(1) }
let cw = CGFloat(first.width) * scale, ch = cropH * scale, label: CGFloat = 22
let rows = Int(ceil(Double(imgs.count) / Double(cols)))
let W = Int(cw * CGFloat(cols)), H = Int((ch + label) * CGFloat(rows))
let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.setFillColor(NSColor.white.cgColor); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
for (i, img) in imgs.enumerated() {
    let col = i / rows, row = i % rows
    let x = CGFloat(col) * cw, yTop = CGFloat(row) * (ch + label)
    let crop = img.cropping(to: CGRect(x: 0, y: 0, width: CGFloat(img.width), height: cropH))!
    ctx.draw(crop, in: CGRect(x: x, y: CGFloat(H) - yTop - label - ch, width: cw, height: ch))
    let name = (files[i] as NSString).lastPathComponent
    (name as NSString).draw(at: CGPoint(x: x + 6, y: CGFloat(H) - yTop - label + 3),
                            withAttributes: [.font: NSFont.boldSystemFont(ofSize: 14), .foregroundColor: NSColor.red])
}
let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
