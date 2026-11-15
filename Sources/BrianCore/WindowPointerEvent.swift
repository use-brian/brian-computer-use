import AppKit

/// PID-directed AppKit mouse events need a window number and window-relative
/// coordinates. Posting a bare global CG mouse location can hit unrelated UI.
public enum WindowPointerEvent {
    public static func click(point: CGPoint, windowFrame: CGRect, windowNumber: Int, down: Bool) -> CGEvent? {
        guard windowFrame.contains(point), windowNumber > 0 else { return nil }
        let local = CGPoint(x: point.x - windowFrame.minX, y: windowFrame.maxY - point.y)
        guard let event = NSEvent.mouseEvent(with: down ? .leftMouseDown : .leftMouseUp,
            location: local, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: down ? 1 : 0)?.cgEvent else { return nil }
        event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(windowNumber))
        event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(windowNumber))
        return event
    }
}
