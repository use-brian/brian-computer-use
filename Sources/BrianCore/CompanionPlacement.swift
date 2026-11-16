import Foundation

public enum CompanionPlacement {
    /// Reject missing/off-display geometry instead of clamping it to a random edge.
    public static func visibleTarget(_ target: CGRect, screen: CGRect) -> CGRect? {
        guard [target.origin.x, target.origin.y, target.width, target.height,
               screen.origin.x, screen.origin.y, screen.width, screen.height].allSatisfy({ $0.isFinite }),
              target.width > 0, target.height > 0, screen.width > 0, screen.height > 0 else { return nil }
        let visible = target.intersection(screen)
        guard !visible.isNull, !visible.isEmpty,
              visible.width * visible.height < screen.width * screen.height * 0.65 else { return nil }
        return visible
    }

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
    /// Return to the side nearest the user's resting position, preserving height.
    public static func atSide(_ home: CGRect, size: CGSize, screen: CGRect) -> CGRect {
        let inset: CGFloat = 20
        let x = home.midX < screen.midX ? screen.minX + inset : screen.maxX - size.width - inset
        return clamp(CGRect(x: x, y: home.minY, width: size.width, height: size.height), to: screen)
    }
    public static func clamp(_ frame: CGRect, to screen: CGRect) -> CGRect {
        CGRect(x: min(max(frame.minX, screen.minX), max(screen.minX, screen.maxX-frame.width)),
               y: min(max(frame.minY, screen.minY), max(screen.minY, screen.maxY-frame.height)),
               width: frame.width, height: frame.height)
    }
}
