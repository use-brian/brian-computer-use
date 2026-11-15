import AppKit
import ScreenCaptureKit
import BrianCore

/// Single-window, in-memory captures. No full-desktop capture and no image files.
@MainActor final class WindowVision {
    struct Capture {
        let snapshot: VisualSnapshot
        let windowID: CGWindowID
        let pid: pid_t
        let frame: CGRect
        let title: String?
        let created: Date
        let image: CGImage
    }
    private(set) var capture: Capture?
    func clear() { capture = nil }

    func observe(pid: pid_t, expectedFrame: CGRect?) async throws -> VisualSnapshot {
        guard CGPreflightScreenCaptureAccess() else { throw AgentError.screenRecording }
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        let candidates = content.windows.filter { $0.owningApplication?.processID == pid && $0.windowLayer == 0 && $0.frame.width > 40 && $0.frame.height > 40 }
        let window: SCWindow?
        if let expectedFrame {
            window = candidates.first { Self.sameFrame($0.frame, expectedFrame) }
        } else {
            let ordered = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
            let frontID = ordered.first { ($0[kCGWindowOwnerPID as String] as? Int) == Int(pid) && ($0[kCGWindowLayer as String] as? Int) == 0 }?[kCGWindowNumber as String] as? UInt32
            window = candidates.first { $0.windowID == frontID }
        }
        guard let window else { throw AgentError.runtime("No unambiguous visible window is available for vision. Bring the intended window forward and retry.") }
        let image = try await take(window)
        let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        guard let data, data.count <= 3_000_000 else { throw AgentError.runtime("The window image exceeded the local vision limit.") }
        let snapshot = VisualSnapshot(id: UUID().uuidString, png: data.base64EncodedString())
        capture = Capture(snapshot: snapshot, windowID: window.windowID, pid: pid, frame: window.frame, title: window.title, created: Date(), image: image)
        return snapshot
    }

    func validatedPoint(_ action: PlannerAction, pid: pid_t, checkFrontWindow: Bool) async throws -> CGPoint {
        guard let capture, capture.pid == pid, action.target == capture.snapshot.id,
              Date().timeIntervalSince(capture.created) < 180 else { throw stale("The screenshot expired or belongs to a different action.") }
        let point = try VisualPoint(action.value ?? "")
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        // WindowServer also lists private title-bar/capture surfaces. Only
        // compare windows that ScreenCaptureKit can actually capture for this app.
        let candidateIDs = Set(content.windows.filter {
            $0.owningApplication?.processID == pid && $0.windowLayer == 0 && $0.frame.width > 40 && $0.frame.height > 40
        }.map(\.windowID))
        let ordered = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let frontID = ordered.compactMap { row -> UInt32? in
            guard (row[kCGWindowOwnerPID as String] as? Int) == Int(pid),
                  let number = row[kCGWindowNumber as String] as? NSNumber,
                  candidateIDs.contains(number.uint32Value) else { return nil }
            return number.uint32Value
        }.first
        if checkFrontWindow, frontID != capture.windowID { throw stale("A different capturable window is now in front of the captured window.") }
        guard let window = content.windows.first(where: { $0.windowID == capture.windowID && $0.owningApplication?.processID == pid }),
              Self.sameFrame(window.frame, capture.frame), window.title == capture.title else { throw stale("The captured window moved, resized, changed documents, or closed.") }
        // Confirmation and inference can take time. Re-capture before dispatch so
        // a moved control or a different page cannot inherit old coordinates.
        let fresh = try await take(window)
        guard Self.unchanged(capture.image, fresh, point: point, chrome: min(0.12, 40 / capture.frame.height)) else { throw stale("The visible content changed after the screenshot.") }
        return CGPoint(x: capture.frame.minX + capture.frame.width * point.x,
                       y: capture.frame.minY + capture.frame.height * point.y)
    }

    private func take(_ window: SCWindow) async throws -> CGImage {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        let scale = min(1.5, 1280 / max(window.frame.width, window.frame.height))
        config.width = max(1, Int(window.frame.width * scale))
        config.height = max(1, Int(window.frame.height * scale))
        config.scalesToFit = true; config.preservesAspectRatio = true
        config.showsCursor = false; config.ignoreShadowsSingleWindow = true
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }
    private static func sameFrame(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX-b.minX) < 1 && abs(a.minY-b.minY) < 1 && abs(a.width-b.width) < 1 && abs(a.height-b.height) < 1
    }
    private static func unchanged(_ before: CGImage, _ after: CGImage, point: VisualPoint, chrome: Double) -> Bool {
        guard before.width == after.width, before.height == after.height else { return false }
        func samples(_ image: CGImage) -> [UInt8] {
            var bytes = [UInt8](repeating: 0, count: 128 * 128 * 4)
            bytes.withUnsafeMutableBytes { buffer in
                let context = CGContext(data: buffer.baseAddress, width: 128, height: 128, bitsPerComponent: 8,
                    bytesPerRow: 128 * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                context.draw(image, in: CGRect(x: 0, y: 0, width: 128, height: 128))
            }
            return bytes
        }
        return VisualFrameComparison.isUnchanged(before: samples(before), after: samples(after),
                                                 point: point, chromeFraction: chrome)
    }

    private func stale(_ reason: String) -> AgentError { .runtime(reason + " Stopped before clicking; retry to inspect it again.") }
}
