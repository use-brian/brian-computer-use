import Foundation

/// Compares top-left-origin 128×128 RGBA samples. Window identity, title, frame,
/// and age must also be checked by the desktop adapter before calling this.
public enum VisualFrameComparison {
    public static func isUnchanged(before: [UInt8], after: [UInt8], point: VisualPoint, chromeFraction: Double) -> Bool {
        guard before.count == 128 * 128 * 4, after.count == before.count else { return false }
        var changed = 0
        for i in stride(from: 0, to: before.count, by: 4) {
            let delta = (0..<3).map { abs(Int(before[i+$0]) - Int(after[i+$0])) }.max() ?? 0
            if delta > 35 {
                let x = Double((i / 4) % 128) / 128, y = Double((i / 4) / 128) / 128
                if abs(x - point.x) < 0.035 && abs(y - point.y) < 0.035 { return false }
                if y >= min(0.12, max(0, chromeFraction)) { changed += 1 }
            }
        }
        return changed < 164
    }
}
