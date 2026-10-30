import Foundation
import CoreGraphics

public enum SelectionGeometry {
    public static func selection(from a: CGPoint, to b: CGPoint, in bounds: CGRect) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x-b.x), height: abs(a.y-b.y))
            .intersection(bounds)
    }

    /// Input uses top-left, point coordinates; output uses screenshot pixels.
    public static func pixels(for rect: CGRect, logicalSize: CGSize, pixelSize: CGSize) -> CGRect? {
        guard logicalSize.width > 0, logicalSize.height > 0,
              pixelSize.width > 0, pixelSize.height > 0 else { return nil }
        let clipped = rect.intersection(CGRect(origin: .zero, size: logicalSize))
        guard !clipped.isNull, clipped.width >= 3, clipped.height >= 3 else { return nil }
        let sx = pixelSize.width / logicalSize.width, sy = pixelSize.height / logicalSize.height
        let x = floor(clipped.minX * sx), y = floor(clipped.minY * sy)
        return CGRect(x: x, y: y, width: ceil(clipped.maxX * sx)-x, height: ceil(clipped.maxY * sy)-y)
            .intersection(CGRect(origin: .zero, size: pixelSize))
    }
}
