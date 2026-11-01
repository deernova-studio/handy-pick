import AppKit

// Package the selected artwork without distorting its original aspect ratio.
let source = NSImage(contentsOfFile: "Resources/BrandMark.png")!
let size = NSSize(width: 1024, height: 1024)
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
bitmap.size = size
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSColor.white.setFill()
NSRect(origin: .zero, size: size).fill()
let scale = min(size.width / source.size.width, size.height / source.size.height)
let fitted = NSSize(width: source.size.width * scale, height: source.size.height * scale)
source.draw(in: NSRect(x: (size.width-fitted.width)/2, y: (size.height-fitted.height)/2,
                      width: fitted.width, height: fitted.height))
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "Resources/AppIcon.png"))
