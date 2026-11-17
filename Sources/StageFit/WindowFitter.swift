import AppKit
import ApplicationServices

/// Reads and updates windows using macOS Accessibility APIs.
final class WindowFitter {
    private let onError: (String) -> Void

    init(onError: @escaping (String) -> Void) {
        self.onError = onError
    }

    func fit(_ window: AXUIElement, reservedStripWidth: CGFloat) {
        guard let oldFrame = windowFrame(window) else {
            onError("This window cannot be resized via Accessibility.")
            return
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

        // Some applications shift their origin when resized: anchor twice.
        let moved = setPosition(window, target.origin)
        let resized = setSize(window, target.size)
        let reanchored = setPosition(window, target.origin)
        if moved != .success || resized != .success || reanchored != .success {
            onError("This app does not allow StageFit to resize its window.")
        }
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
