// Turns app/Resources/AppIcon-source.png into app/Resources/AppIcon.icns: tighter crop, macOS rounded shape and margins.
// Run from the repo root: swift scripts/make-icon.swift
import AppKit

let sourceURL = URL(fileURLWithPath: "app/Resources/AppIcon-source.png")
let outputURL = URL(fileURLWithPath: "app/Resources/AppIcon.icns")
guard let provider = CGDataProvider(url: sourceURL as CFURL),
      let source = CGImage(pngDataProviderSource: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
else { fatalError("cannot read \(sourceURL.path)") }

// The artwork sits in the middle with a wide dark border; keep 70% of it so the crystal reads at Dock size.
let side = Int(Double(min(source.width, source.height)) * 0.70)
// The artwork also sits a bit low in the source, so the crop moves down to give the floor glow room above the edge.
let crop = CGRect(x: (source.width - side) / 2, y: (source.height - side) / 2 + source.height * 16 / 1000, width: side, height: side)
guard let art = source.cropping(to: crop) else { fatalError("cannot crop") }

func render(_ size: Int) -> Data {
    let s = CGFloat(size)
    let body = s * 824 / 1024                      // Apple's icon grid: 824 body in a 1024 canvas.
    let rect = CGRect(x: (s - body) / 2, y: (s - body) / 2, width: body, height: body)
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: body * 0.225, cornerHeight: body * 0.225, transform: nil))
    ctx.clip()
    ctx.draw(art, in: rect)
    return NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
}

let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("Quicksave-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try render(base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", outputURL.path]
try iconutil.run()
iconutil.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }
print(outputURL.path)
