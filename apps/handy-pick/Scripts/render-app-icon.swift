import AppKit

// Legacy .icns consumers display these pixels directly. Bake the rounded tile
// and transparent optical margin into every size instead of relying on an OS mask.
let source = NSImage(contentsOfFile: "Resources/BrandMark.png")!
let size = NSSize(width: 1024, height: 1024)
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
bitmap.size = size
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSGraphicsContext.current?.imageInterpolation = .high
let canvas = NSRect(origin: .zero, size: size)
NSColor.clear.setFill()
canvas.fill(using: .copy)
let tile = canvas.insetBy(dx: 100, dy: 100)
let outline = NSBezierPath(roundedRect: tile, xRadius: 184, yRadius: 184)
outline.addClip()
NSColor.white.setFill()
tile.fill()
let scale = min(tile.width / source.size.width, tile.height / source.size.height)
let fitted = NSSize(width: source.size.width * scale, height: source.size.height * scale)
source.draw(in: NSRect(x: (size.width-fitted.width)/2, y: (size.height-fitted.height)/2,
                      width: fitted.width, height: fitted.height))
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "Resources/AppIcon.png"))
