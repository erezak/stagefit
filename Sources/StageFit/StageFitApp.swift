import AppKit
import ApplicationServices
import Carbon.HIToolbox
import ServiceManagement

// StageFit: Fit the focused window into the desktop area
// while reserving space for Stage Manager recent-app thumbnails.
final class StageFit: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let widthKey = "stageStripWidth"
    private let replaceGreenKey = "replaceGreenButton"
    private let replaceTitleBarKey = "fitOnTitleBarDoubleClick"
    private let edgeGap: CGFloat = 8

    private var statusItem: NSStatusItem!
    private var widthMenuItems: [NSMenuItem] = []
    private var replaceGreenMenuItem: NSMenuItem?
    private var replaceTitleBarMenuItem: NSMenuItem?
    private var launchAtLoginMenuItem: NSMenuItem?
    private var loginApprovalMenuItem: NSMenuItem?
    private lazy var windowClickInterceptor = WindowClickInterceptor { [weak self] window in
        self?.fitWindow(window)
    }
    private var hotKey: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?
    private var lastExternalPID: pid_t?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        if let app = NSWorkspace.shared.frontmostApplication,
           app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            lastExternalPID = app.processIdentifier
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(applicationActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )

        makeStatusMenu()
        registerHotKey()
        promptForAccessibilityIfNeeded()
        // New installs default title-bar double-click to StageFit, but retain
        // explicit user choices in subsequent versions.
        let titleBarEnabled = UserDefaults.standard.object(forKey: replaceTitleBarKey) == nil
            ? true : UserDefaults.standard.bool(forKey: replaceTitleBarKey)
        let greenEnabled = UserDefaults.standard.bool(forKey: replaceGreenKey)
        if AXIsProcessTrusted() && windowClickInterceptor.configure(
            titleBar: titleBarEnabled, greenButton: greenEnabled
        ) {
            replaceTitleBarMenuItem?.state = titleBarEnabled ? .on : .off
            replaceGreenMenuItem?.state = greenEnabled ? .on : .off
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        windowClickInterceptor.stop()
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let hotKeyHandler { RemoveEventHandler(hotKeyHandler) }
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func applicationActivated(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else { return }
        lastExternalPID = app.processIdentifier
    }

    private var stripWidth: CGFloat {
        let stored = UserDefaults.standard.integer(forKey: widthKey)
        return CGFloat(stored > 0 ? stored : 190)
    }

    private func makeStatusMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "rectangle.inset.filled.on.rectangle",
                                   accessibilityDescription: "StageFit")
            if button.image == nil { button.title = "SF" }
            button.toolTip = "StageFit: Fit beside Stage Manager"
        }

        let menu = NSMenu()
        menu.delegate = self
        let fit = NSMenuItem(title: "Fit Front Window", action: #selector(fitFrontWindow), keyEquivalent: "")
        fit.target = self
        menu.addItem(fit)
        menu.addItem(NSMenuItem(title: "Shortcut: ⌃⌥⌘F", action: nil, keyEquivalent: ""))
        let replaceTitleBar = NSMenuItem(
            title: "Fit on Title Bar Double-Click",
            action: #selector(toggleTitleBar(_:)), keyEquivalent: ""
        )
        replaceTitleBar.target = self
        replaceTitleBar.state = .off
        replaceTitleBar.toolTip = "Double-click a standard title bar to fit beside Stage Manager."
        replaceTitleBarMenuItem = replaceTitleBar
        menu.addItem(replaceTitleBar)

        let replaceGreen = NSMenuItem(
            title: "Replace Green Button Click",
            action: #selector(toggleGreenButton(_:)), keyEquivalent: ""
        )
        replaceGreen.target = self
        replaceGreen.state = .off
        replaceGreen.toolTip = "A normal click fits the window; hold a modifier for native behavior."
        replaceGreenMenuItem = replaceGreen
        menu.addItem(replaceGreen)
        menu.addItem(.separator())

        let widths = NSMenu(title: "Reserved Stage Manager Width")
        for width in [150, 170, 190, 210, 230, 260] {
            let item = NSMenuItem(title: "\(width) pt", action: #selector(changeWidth(_:)), keyEquivalent: "")
            item.target = self
            item.tag = width
            item.state = Int(stripWidth) == width ? .on : .off
            widths.addItem(item)
            widthMenuItems.append(item)
        }
        let widthHeader = NSMenuItem(title: "Stage Manager Space", action: nil, keyEquivalent: "")
        widthHeader.submenu = widths
        menu.addItem(widthHeader)
        menu.addItem(.separator())

        let launchAtLogin = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin(_:)), keyEquivalent: ""
        )
        launchAtLogin.target = self
        launchAtLogin.toolTip = "Start StageFit automatically when you sign in to macOS."
        launchAtLoginMenuItem = launchAtLogin
        menu.addItem(launchAtLogin)

        let loginApproval = NSMenuItem(
            title: "Approve in Login Items Settings…",
            action: #selector(openLoginItemsSettings), keyEquivalent: ""
        )
        loginApproval.target = self
        loginApproval.isHidden = true
        loginApprovalMenuItem = loginApproval
        menu.addItem(loginApproval)
        menu.addItem(.separator())

        let prefs = NSMenuItem(title: "Accessibility Settings…", action: #selector(openAccessibilitySettings), keyEquivalent: "")
        prefs.target = self
        menu.addItem(prefs)
        menu.addItem(.separator())

        let about = NSMenuItem(title: "About StageFit", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit StageFit", action: #selector(quitApp), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu
        refreshLaunchAtLoginMenu()
    }

    // The user can also change Login Items in System Settings, so read its
    // current system status every time the StageFit menu is opened.
    func menuWillOpen(_ menu: NSMenu) {
        refreshLaunchAtLoginMenu()
    }

    private func refreshLaunchAtLoginMenu() {
        switch SMAppService.mainApp.status {
        case .enabled:
            launchAtLoginMenuItem?.title = "Launch at Login"
            launchAtLoginMenuItem?.state = .on
            loginApprovalMenuItem?.isHidden = true
        case .requiresApproval:
            launchAtLoginMenuItem?.title = "Launch at Login (Approval Needed)"
            launchAtLoginMenuItem?.state = .mixed
            loginApprovalMenuItem?.isHidden = false
        case .notRegistered, .notFound:
            launchAtLoginMenuItem?.title = "Launch at Login"
            launchAtLoginMenuItem?.state = .off
            loginApprovalMenuItem?.isHidden = true
        @unknown default:
            launchAtLoginMenuItem?.title = "Launch at Login"
            launchAtLoginMenuItem?.state = .off
            loginApprovalMenuItem?.isHidden = true
        }
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        let service = SMAppService.mainApp
        do {
            switch service.status {
            case .enabled:
                try service.unregister()
            case .requiresApproval:
                // Registered but blocked by the OS: clicking the mixed-state
                // item cancels the request. Use the separate approval menu item
                // to open Login Items Settings instead.
                try service.unregister()
            case .notRegistered, .notFound:
                try service.register()
            @unknown default:
                showError("macOS reported an unrecognized Login Items status.")
                return
            }
        } catch {
            refreshLaunchAtLoginMenu()
            showError("Could not change Launch at Login: \(error.localizedDescription)\n\nInstall StageFit in /Applications, and check System Settings → General → Login Items & Extensions.")
            return
        }

        refreshLaunchAtLoginMenu()
        if service.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    @objc private func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    @objc private func toggleTitleBar(_ sender: NSMenuItem) {
        let enable = sender.state == .off
        changeClickPreferences(titleBar: enable,
                               greenButton: windowClickInterceptor.greenButtonEnabled)
    }

    @objc private func toggleGreenButton(_ sender: NSMenuItem) {
        let enable = sender.state == .off
        changeClickPreferences(titleBar: windowClickInterceptor.titleBarEnabled,
                               greenButton: enable)
    }

    private func changeClickPreferences(titleBar: Bool, greenButton: Bool) {
        if (titleBar || greenButton) && !AXIsProcessTrusted() {
            promptForAccessibilityIfNeeded()
            showError("Allow StageFit in Accessibility settings, then enable this option again.")
            return
        }
        guard windowClickInterceptor.configure(titleBar: titleBar, greenButton: greenButton) else {
            showError("Could not intercept window clicks. Check Accessibility permission, then restart StageFit and retry.")
            return
        }
        UserDefaults.standard.set(titleBar, forKey: replaceTitleBarKey)
        UserDefaults.standard.set(greenButton, forKey: replaceGreenKey)
        replaceTitleBarMenuItem?.state = titleBar ? .on : .off
        replaceGreenMenuItem?.state = greenButton ? .on : .off
    }

    @objc private func changeWidth(_ sender: NSMenuItem) {
        UserDefaults.standard.set(sender.tag, forKey: widthKey)
        for item in widthMenuItems { item.state = item.tag == sender.tag ? .on : .off }
    }

    @objc private func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func quitApp() { NSApp.terminate(nil) }

    private func promptForAccessibilityIfNeeded() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    private func registerHotKey() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let userData = Unmanaged.passUnretained(self).toOpaque()
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData -> OSStatus in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                Unmanaged<StageFit>.fromOpaque(userData).takeUnretainedValue().fitFrontWindow()
                return noErr
            },
            1, &eventType, userData, &hotKeyHandler
        )
        guard handlerStatus == noErr else {
            NSLog("StageFit: hotkey event handler failed (%d)", handlerStatus)
            return
        }

        let identifier = EventHotKeyID(signature: OSType(0x53544654), id: 1) // STFT
        let status = RegisterEventHotKey(
            UInt32(kVK_ANSI_F), UInt32(controlKey | optionKey | cmdKey),
            identifier, GetApplicationEventTarget(), 0, &hotKey
        )
        if status != noErr {
            NSLog("StageFit: unable to register ⌃⌥⌘F (status %d). Shortcut may be taken.", status)
        }
    }

    @objc private func fitFrontWindow() {
        guard AXIsProcessTrusted() else {
            promptForAccessibilityIfNeeded()
            showError("Allow StageFit in System Settings → Privacy & Security → Accessibility, then try again.")
            return
        }

        let selfPID = ProcessInfo.processInfo.processIdentifier
        let pid: pid_t?
        if let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != selfPID {
            pid = front.processIdentifier
        } else {
            pid = lastExternalPID
        }
        guard let pid else { return }

        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, 1.5)
        guard let window = windowFitter.focusedWindow(for: appElement) else {
            showError("The frontmost app does not expose a resizable window.")
            return
        }
        fitWindow(window)
    }

    private lazy var windowFitter = WindowFitter { [weak self] message in
        self?.showError(message)
    }

    private func fitWindow(_ window: AXUIElement) {
        windowFitter.fit(window, reservedStripWidth: stripWidth)
    }

    private func showError(_ message: String) {
        NSLog("StageFit: %@", message)
        let alert = NSAlert()
        alert.messageText = "StageFit"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

