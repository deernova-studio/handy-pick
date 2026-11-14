import AppKit

public struct Annotation {
    public enum Kind { case line, ellipse, text, rectangle, arrow }
    public var kind: Kind
    public var start: CGPoint
    public var end: CGPoint
    public var text: String
    public var color: NSColor
    public init(kind: Kind, start: CGPoint, end: CGPoint, text: String = "", color: NSColor = .systemRed) {
        self.kind = kind; self.start = start; self.end = end; self.text = text; self.color = color
    }
    public func draw() {
        color.setStroke()
        let path: NSBezierPath
        switch kind {
        case .line:
            path = NSBezierPath(); path.move(to: start); path.line(to: end)
        case .arrow:
            let dx = end.x-start.x, dy = end.y-start.y
            let length = hypot(dx, dy)
            guard length >= 2 else { return }
            let ux = dx/length, uy = dy/length
            let head = min(14, length * 0.4)
            path = NSBezierPath(); path.move(to: start); path.line(to: end)
            path.move(to: CGPoint(x: end.x-ux*head-uy*head*0.5, y: end.y-uy*head+ux*head*0.5))
            path.line(to: end)
            path.line(to: CGPoint(x: end.x-ux*head+uy*head*0.5, y: end.y-uy*head-ux*head*0.5))
        case .rectangle:
            path = NSBezierPath(rect: CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                                             width: abs(end.x-start.x), height: abs(end.y-start.y)))
        case .ellipse:
            path = NSBezierPath(ovalIn: CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x-start.x), height: abs(end.y-start.y)))
        case .text:
            (text as NSString).draw(at: start, withAttributes: [.font: NSFont.systemFont(ofSize: 20, weight: .semibold), .foregroundColor: color])
            return
        }
        path.lineWidth = 3; path.lineCapStyle = .round; path.lineJoinStyle = .round; path.stroke()
    }
}

public enum AnnotationRenderer {
    /// Coordinates match the top-left logical coordinate system used by the selection overlay.
    public static func render(image: CGImage, selection: CGRect, logicalSize: CGSize, annotations: [Annotation]) -> CGImage? {
        guard let pixels = SelectionGeometry.pixels(for: selection, logicalSize: logicalSize, pixelSize: CGSize(width: image.width, height: image.height)),
              let crop = image.cropping(to: pixels) else { return nil }
        if annotations.isEmpty { return crop }
        guard let context = CGContext(data: nil, width: crop.width, height: crop.height, bitsPerComponent: 8,
                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(crop, in: CGRect(x: 0, y: 0, width: crop.width, height: crop.height))
        let sx = CGFloat(image.width) / logicalSize.width, sy = CGFloat(image.height) / logicalSize.height
        context.translateBy(x: 0, y: CGFloat(crop.height)); context.scaleBy(x: sx, y: -sy)
        context.translateBy(x: -pixels.minX / sx, y: -pixels.minY / sy)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        annotations.forEach { $0.draw() }
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }
}
