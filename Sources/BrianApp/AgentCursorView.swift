import SwiftUI

/// Presentation only: never moves or captures the user's hardware pointer.
struct AgentCursorView: View {
    var flipX = false
    var flipY = false
    var pulseAt = Date.distantPast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { timeline in
            AgentCursorArtwork(flipX: flipX, flipY: flipY,
                pulse: reduceMotion ? 1 : min(1, max(0, timeline.date.timeIntervalSince(pulseAt) / 0.48)))
        }
        .frame(width: 56, height: 56)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Kept independent of app state so the actual cursor can be rendered for visual QA.
struct AgentCursorArtwork: View {
    var flipX = false
    var flipY = false
    var pulse: Double = 1
    private let pink = Color(red: 0.94, green: 0.27, blue: 0.64)

    var body: some View {
        Canvas { context, size in
            context.translateBy(x: size.width / 2, y: size.height / 2)
            if pulse < 1 {
                let radius = 3 + pulse * 13
                context.stroke(Path(ellipseIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2)),
                               with: .color(pink.opacity((1 - pulse) * 0.65)), lineWidth: 1.2)
            }
            context.scaleBy(x: flipX ? -1 : 1, y: flipY ? -1 : 1)
            var arrow = Path()
            arrow.move(to: .zero)
            for point in [CGPoint(x: 2.6, y: 13), CGPoint(x: 5.3, y: 9.4), CGPoint(x: 8.7, y: 15),
                          CGPoint(x: 11.2, y: 13.5), CGPoint(x: 7.8, y: 8), CGPoint(x: 12.5, y: 8.2)] {
                arrow.addLine(to: point)
            }
            arrow.closeSubpath()
            context.drawLayer { glow in
                glow.addFilter(.shadow(color: pink.opacity(0.35), radius: 3, x: 0, y: 1))
                glow.fill(arrow, with: .linearGradient(Gradient(colors: [.white, pink]),
                    startPoint: .zero, endPoint: CGPoint(x: 8, y: 12)))
                glow.stroke(arrow, with: .color(.white.opacity(0.85)), style: StrokeStyle(lineWidth: 0.7, lineJoin: .round))
            }
            let badge = CGRect(x: 9, y: 12, width: 16, height: 16)
            context.drawLayer { badgeContext in
                badgeContext.addFilter(.shadow(color: pink.opacity(0.22), radius: 2, x: 0, y: 1))
                badgeContext.fill(Path(ellipseIn: badge), with: .color(pink))
                badgeContext.stroke(Path(ellipseIn: badge), with: .color(.white.opacity(0.75)), lineWidth: 0.65)
            }
            // Brian's silhouette in the badge; the reference's scale and color,
            // with our own companion identity rather than another product's logo.
            var glyph = Path()
            let rows = [2...4, 1...5, 0...6, 0...6, 1...5, 2...2]
            for (row, columns) in rows.enumerated() {
                glyph.addRect(CGRect(x: 12.7 + CGFloat(columns.lowerBound) * 1.2,
                    y: 16 + CGFloat(row) * 1.2, width: CGFloat(columns.count) * 1.2, height: 1.2))
            }
            glyph.addRect(CGRect(x: 17.5, y: 22, width: 1.2, height: 1.2))
            context.fill(glyph, with: .color(.white))
            for x in [15.1, 17.5] {
                context.fill(Path(CGRect(x: x, y: 18.5, width: 0.9, height: 0.9)), with: .color(pink))
            }
        }
        .frame(width: 56, height: 56)
    }
}
