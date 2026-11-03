import Foundation
import CoreGraphics

public enum SelectionGeometry {
    public enum Handle: CaseIterable {
        case topLeft, topRight, bottomLeft, bottomRight, left, right, top, bottom

        public func point(on rect: CGRect) -> CGPoint {
            CGPoint(x: movesLeft ? rect.minX : movesRight ? rect.maxX : rect.midX,
                    y: movesTop ? rect.minY : movesBottom ? rect.maxY : rect.midY)
        }
        var movesLeft: Bool { self == .left || self == .topLeft || self == .bottomLeft }
        var movesRight: Bool { self == .right || self == .topRight || self == .bottomRight }
        var movesTop: Bool { self == .top || self == .topLeft || self == .topRight }
        var movesBottom: Bool { self == .bottom || self == .bottomLeft || self == .bottomRight }

        public func hitRect(on rect: CGRect, tolerance: CGFloat = 6) -> CGRect {
            let point = point(on: rect)
            switch self {
            case .left, .right:
                return CGRect(x: point.x-tolerance, y: rect.minY+tolerance, width: tolerance*2, height: max(0, rect.height-tolerance*2))
            case .top, .bottom:
                return CGRect(x: rect.minX+tolerance, y: point.y-tolerance, width: max(0, rect.width-tolerance*2), height: tolerance*2)
            default:
                return CGRect(x: point.x-tolerance, y: point.y-tolerance, width: tolerance*2, height: tolerance*2)
            }
        }
    }

    public static func handle(at point: CGPoint, on rect: CGRect) -> Handle? {
        Handle.allCases.first { $0.hitRect(on: rect).contains(point) }
    }

    /// Keep the opposite edge fixed and prevent flipping or collapsing the crop.
    public static func resized(_ rect: CGRect, handle: Handle, delta: CGPoint, in bounds: CGRect) -> CGRect {
        let minimum: CGFloat = 3
        var left = rect.minX, right = rect.maxX, top = rect.minY, bottom = rect.maxY
        if handle.movesLeft { left = max(bounds.minX, min(left+delta.x, right-minimum)) }
        if handle.movesRight { right = min(bounds.maxX, max(right+delta.x, left+minimum)) }
        if handle.movesTop { top = max(bounds.minY, min(top+delta.y, bottom-minimum)) }
        if handle.movesBottom { bottom = min(bounds.maxY, max(bottom+delta.y, top+minimum)) }
        return CGRect(x: left, y: top, width: right-left, height: bottom-top)
    }

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
