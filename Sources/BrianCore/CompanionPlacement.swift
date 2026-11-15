import Foundation

public enum CompanionPlacement {
    public static func beside(_ target: CGRect, size: CGSize, screen: CGRect) -> CGRect {
        let gap: CGFloat = 10
        let origins = [CGPoint(x: target.minX-size.width-gap, y: target.midY-size.height/2),
                       CGPoint(x: target.maxX+gap, y: target.midY-size.height/2),
                       CGPoint(x: target.midX-size.width/2, y: target.maxY+gap),
                       CGPoint(x: target.midX-size.width/2, y: target.minY-size.height-gap)]
        let candidates = origins.map { clamp(CGRect(origin: $0, size: size), to: screen) }
        return candidates.min { a, b in
            let ai = a.intersection(target), bi = b.intersection(target)
            let overlapA = ai.isNull ? 0 : ai.width * ai.height
            let overlapB = bi.isNull ? 0 : bi.width * bi.height
            return overlapA < overlapB
        } ?? clamp(CGRect(origin: target.origin, size: size), to: screen)
    }
    public static func byBar(_ bar: CGRect, size: CGSize, screen: CGRect) -> CGRect {
        let above = CGRect(x: bar.minX+8, y: bar.maxY+10, width: size.width, height: size.height)
        if screen.contains(above) { return above }
        return clamp(CGRect(x: bar.minX+8, y: bar.minY-size.height-10, width: size.width, height: size.height), to: screen)
    }
    public static func clamp(_ frame: CGRect, to screen: CGRect) -> CGRect {
        CGRect(x: min(max(frame.minX, screen.minX), max(screen.minX, screen.maxX-frame.width)),
               y: min(max(frame.minY, screen.minY), max(screen.minY, screen.maxY-frame.height)),
               width: frame.width, height: frame.height)
    }
}
