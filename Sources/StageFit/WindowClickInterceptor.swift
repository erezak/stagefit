import AppKit
import ApplicationServices

/// Intercepts only two deliberately selected window gestures:
///   1. The second click of a double-click on a standard title bar.
///   2. (Optional) An unmodified click on the green traffic-light button.
/// All other mouse gestures pass through unchanged. This does not inject code
/// into other apps and never records pointer events or their locations.
final class WindowClickInterceptor {
    private struct PendingClick {
        let window: AXUIElement
        let location: CGPoint
    }

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var pendingClick: PendingClick?
    private let systemElement = AXUIElementCreateSystemWide()
    private let onFit: (AXUIElement) -> Void

    private(set) var titleBarEnabled = false
    private(set) var greenButtonEnabled = false

    init(onFit: @escaping (AXUIElement) -> Void) {
        self.onFit = onFit
        // A sluggish target application should not stall the event tap indefinitely.
        AXUIElementSetMessagingTimeout(systemElement, 0.2)
    }

    var isRunning: Bool { tap != nil }

    /// Starts/stops one shared event tap as needed. Returns false when macOS
    /// refuses permission or the event tap cannot be installed.
    @discardableResult
    func configure(titleBar: Bool, greenButton: Bool) -> Bool {
        if !titleBar && !greenButton {
            titleBarEnabled = false
            greenButtonEnabled = false
            stop()
            return true
        }

        guard start() else { return false }
        titleBarEnabled = titleBar
        greenButtonEnabled = greenButton
        return true
    }

    private func start() -> Bool {
        if isRunning { return true }
        guard AXIsProcessTrusted() else { return false }

        let mask = (CGEventMask(1) << CGEventType.leftMouseDown.rawValue)
                 | (CGEventMask(1) << CGEventType.leftMouseUp.rawValue)
                 | (CGEventMask(1) << CGEventType.leftMouseDragged.rawValue)

        guard let newTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo -> Unmanaged<CGEvent>? in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                return Unmanaged<WindowClickInterceptor>
                    .fromOpaque(userInfo).takeUnretainedValue()
                    .handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ), let newSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0)
        else { return false }

        tap = newTap
        source = newSource
        CFRunLoopAddSource(CFRunLoopGetMain(), newSource, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)
        return true
    }

    func stop() {
        pendingClick = nil
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        source = nil
        tap = nil
    }

    deinit { stop() }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            pendingClick = nil
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        if type == .leftMouseDragged {
            // Never forward drag events with no corresponding mouse-down.
            return pendingClick == nil ? Unmanaged.passUnretained(event) : nil
        }

        if type == .leftMouseUp {
            guard let pending = pendingClick else { return Unmanaged.passUnretained(event) }
            pendingClick = nil
            // A deliberate double-click should barely move the pointer.
            if hypot(event.location.x - pending.location.x,
                     event.location.y - pending.location.y) <= 12 {
                let window = pending.window
                let action = onFit
                DispatchQueue.main.async { action(window) }
            }
            return nil // Don't deliver an orphaned up for our suppressed down.
        }

        guard type == .leftMouseDown else { return Unmanaged.passUnretained(event) }
        pendingClick = nil

        // Keep modified gestures exactly as macOS implements them.
        if !event.flags.intersection([.maskAlternate, .maskCommand, .maskControl, .maskShift]).isEmpty {
            return Unmanaged.passUnretained(event)
        }

        let isSecondClick = event.getIntegerValueField(.mouseEventClickState) == 2
        guard greenButtonEnabled || (titleBarEnabled && isSecondClick) else {
            return Unmanaged.passUnretained(event)
        }

        let location = event.location
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(
            systemElement, Float(location.x), Float(location.y), &hit
        ) == .success, let hit else { return Unmanaged.passUnretained(event) }

        guard let target = classify(hit: hit, at: location, secondClick: isSecondClick) else {
            return Unmanaged.passUnretained(event)
        }

        pendingClick = target
        return nil // Suppress the native green click / native title-bar double-click.
    }

    private func classify(hit: AXUIElement, at point: CGPoint,
                          secondClick: Bool) -> PendingClick? {
        var node = hit
        var roles: [String] = []
        var zoomButton = false
        var window: AXUIElement?

        // Walk the hit-tested element's ancestor chain, but stop at the
        // window boundary. AXWindow is not always the direct hit target.
        for _ in 0..<12 {
            let role = axString(node, kAXRoleAttribute as CFString) ?? ""
            let subrole = axString(node, kAXSubroleAttribute as CFString) ?? ""
            roles.append(role)

            if subrole == kAXZoomButtonSubrole || subrole == "AXFullScreenButton" {
                zoomButton = true
            }
            if role == kAXWindowRole {
                window = node
                break
            }
            if window == nil,
               let owningWindow = axElement(node, kAXWindowAttribute as CFString) {
                window = owningWindow
            }
            guard let parent = axElement(node, kAXParentAttribute as CFString) else { break }
            node = parent
        }

        guard let window else { return nil }

        if greenButtonEnabled && zoomButton {
            return PendingClick(window: window, location: point)
        }

        guard titleBarEnabled && secondClick && !zoomButton else { return nil }
        guard isTitleBarHit(window: window, roles: roles, at: point) else { return nil }
        return PendingClick(window: window, location: point)
    }

    private func isTitleBarHit(window: AXUIElement, roles: [String],
                               at point: CGPoint) -> Bool {
        // Only normal windows with actual traffic-light controls. This avoids
        // catching double-clicks in floating palettes, menus and overlays.
        guard let close = axElement(window, kAXCloseButtonAttribute as CFString),
              let frame = axFrame(window),
              frame.contains(point) else { return false }

        // Do not interfere with toolbar widgets, tabs, document text, etc.
        let interactive: Set<String> = [
            "AXButton", "AXCheckBox", "AXRadioButton", "AXPopUpButton",
            "AXMenuButton", "AXComboBox", "AXTextField", "AXTextArea",
            "AXSearchField", "AXTextEntryArea", "AXLink", "AXSlider",
            "AXToolbar", "AXTab", "AXTabGroup", "AXScrollArea",
            "AXWebArea", "AXTable", "AXOutline", "AXMenu", "AXImage"
        ]
        guard !roles.contains(where: { interactive.contains($0) }) else { return false }

        // Explicitly exposed title bars can be taller in some applications.
        if roles.contains("AXTitleBar") { return true }

        // Accessibility doesn't expose an AXTitleBar in every app. For a
        // standard window, infer the narrow draggable band from its close
        // button's location, not a broad 'top of window' guess.
        var titleBarHeight: CGFloat = 38
        if let closeFrame = axFrame(close) {
            titleBarHeight = max(32, min(54, closeFrame.maxY - frame.minY + 12))
        }
        guard point.y < frame.minY + titleBarHeight else { return false }

        // Empty title-bar background typically hit-tests as the window/group,
        // and the title itself as static text. Don't steal double-clicks from
        // unfamiliar AX widgets near the window top.
        let candidates: Set<String> = ["AXWindow", "AXGroup", "AXStaticText", "AXUnknown"]
        return roles.contains(where: { candidates.contains($0) })
    }

    private func axString(_ element: AXUIElement, _ key: CFString) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key, &value) == .success else { return nil }
        return value as? String
    }

    private func axElement(_ element: AXUIElement, _ key: CFString) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private func axFrame(_ element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString,
                                            &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString,
                                            &sizeValue) == .success,
              let positionValue, let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        else { return nil }
        return CGRect(origin: position, size: size)
    }
}
