import AppKit
import ApplicationServices

/// Reads and updates windows using macOS Accessibility APIs.
final class WindowFitter {
    private let onError: (String) -> Void

    // A record is kept only while the window remains at the frame StageFit set.
    // AXUIElement equality identifies a window across separately obtained AX handles.
    // Bound the number of retained handles so closed windows do not accumulate forever.
    private struct FittedWindow {
        let element: AXUIElement
        let snapshot: WindowToggleSnapshot
    }
    private var fittedWindows: [FittedWindow] = []
    private let maxRememberedWindows = 64

    init(onError: @escaping (String) -> Void) {
        self.onError = onError
    }

    func fit(_ window: AXUIElement, reservedStripWidth: CGFloat) {
        guard let oldFrame = windowFrame(window) else {
            onError("This window cannot be resized via Accessibility.")
            return
        }

        // Only restore if the window is still precisely where StageFit left it.
        // A manual resize or move invalidates the pending restore, and the new
        // user-chosen frame becomes the origin for the next fit/restore cycle.
        if let index = fittedWindows.firstIndex(where: { CFEqual($0.element, window) }) {
            let previous = fittedWindows.remove(at: index)
            if let restoreFrame = previous.snapshot.restoreFrame(for: oldFrame) {
                if !applyFrame(restoreFrame, to: window) {
                    onError("This app does not allow StageFit to restore its window.")
                }
                return
            }
        }

        let screens = NSScreen.screens
        guard let primary = screens.first else { return }
        let primaryTop = primary.frame.maxY
        let midpoint = CGPoint(x: oldFrame.midX, y: oldFrame.midY)

        // Prefer the screen containing the window's center; otherwise the
        // screen with the greatest overlap, preserving prior behavior.
        let screen = screens.first(where: {
            WindowLayout.toAXCoordinates($0.frame, primaryScreenTop: primaryTop).contains(midpoint)
        }) ?? screens.max(by: {
            WindowLayout.overlapArea(
                WindowLayout.toAXCoordinates($0.frame, primaryScreenTop: primaryTop), oldFrame
            ) < WindowLayout.overlapArea(
                WindowLayout.toAXCoordinates($1.frame, primaryScreenTop: primaryTop), oldFrame
            )
        }) ?? primary

        let dockOnLeft = UserDefaults(suiteName: "com.apple.dock")?
            .string(forKey: "orientation") == "left"

        guard let target = WindowLayout.fittedFrame(
            visibleScreenFrame: screen.visibleFrame,
            primaryScreenTop: primaryTop,
            reservedStripWidth: reservedStripWidth,
            dockOnLeft: dockOnLeft
        ) else {
            onError("Not enough desktop space. Reduce the reserved width in the StageFit menu.")
            return
        }

        if !applyFrame(target, to: window) {
            // An application can reject one AX operation after accepting another.
            _ = applyFrame(oldFrame, to: window)
            onError("This app does not allow StageFit to resize its window.")
            return
        }

        guard let appliedFrame = windowFrame(window) else {
            onError("StageFit could not read the resized window's frame.")
            return
        }
        // Record the actual frame, not the requested target: some applications
        // enforce minimum sizes or adjust their own window geometry.
        fittedWindows.append(FittedWindow(
            element: window,
            snapshot: WindowToggleSnapshot(originalFrame: oldFrame, fittedFrame: appliedFrame)
        ))
        if fittedWindows.count > maxRememberedWindows {
            fittedWindows.removeFirst(fittedWindows.count - maxRememberedWindows)
        }
    }

    /// Some apps shift their origin while resizing; anchor position twice.
    private func applyFrame(_ frame: CGRect, to window: AXUIElement) -> Bool {
        let moved = setPosition(window, frame.origin)
        let resized = setSize(window, frame.size)
        let reanchored = setPosition(window, frame.origin)
        return moved == .success && resized == .success && reanchored == .success
    }

    func focusedWindow(for app: AXUIElement) -> AXUIElement? {
        for key in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(app, key as CFString, &value) == .success,
               let value, CFGetTypeID(value) == AXUIElementGetTypeID() {
                return (value as! AXUIElement)
            }
        }
        return nil
    }

    private func windowFrame(_ window: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else { return nil }

        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &point),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        else { return nil }
        return CGRect(origin: point, size: size)
    }

    private func setPosition(_ window: AXUIElement, _ point: CGPoint) -> AXError {
        var value = point
        guard let axValue = AXValueCreate(.cgPoint, &value) else { return .failure }
        return AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, axValue)
    }

    private func setSize(_ window: AXUIElement, _ size: CGSize) -> AXError {
        var value = size
        guard let axValue = AXValueCreate(.cgSize, &value) else { return .failure }
        return AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, axValue)
    }
}
