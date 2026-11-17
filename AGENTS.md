# AGENTS.md — StageFit contributor instructions

## Goal and constraints
StageFit is a deliberately small, native macOS menu-bar utility. It has one job: fit a focused window into the desktop area beside Stage Manager. Keep it lightweight, dependency-free, and predictable. No Electron, installer, daemon, network requests, telemetry, or unnecessary UI.

## Repository map
- `Sources/StageFit/main.swift` — process entry point.
- `Sources/StageFit/StageFitApp.swift` — menu bar, preferences, shortcut, login-item controls.
- `Sources/StageFit/WindowClickInterceptor.swift` — optional mouse-event interception.
- `Sources/StageFit/WindowFitter.swift` — Accessibility reads/writes and screen selection.
- `Sources/StageFit/WindowLayout.swift` — pure, testable geometry.
- `Resources/Info.plist` — bundle identity, version and copyright.
- `Scripts/` — build, validation, tests and release ZIP.

## Compatibility requirements
- macOS 13.0+; Swift 5 language mode, native system frameworks only.
- Preserve `CFBundleIdentifier = dev.stagefit.macos` for existing installations and login items.
- Preserve UserDefaults keys: `stageStripWidth`, `replaceGreenButton`, `fitOnTitleBarDoubleClick`.
- Title-bar double-click defaults ON for fresh installs; green-button interception defaults OFF; Launch at Login is opt-in.
- Keep the global shortcut Control + Option + Command + F.
- The About panel must remain accessible from the menu and show the current version and `Copyright © 2026 Erez Korn.`
- Clicking the native green button with a modifier must retain its native action.
- Never start collecting or logging mouse positions, window titles, URLs, user names, document text, or other private information.
- Avoid hard-coded personal paths, credentials, signing identities, team IDs or machine identifiers.

## Work and validation
1. Make the smallest cohesive change, especially around Accessibility and Core Graphics event taps.
2. When geometry changes, add or update `Tests/main.swift` checks (these can run on Linux).
3. Run `make check` and `make test` on any supported Swift toolchain.
4. Run `make build` and `codesign --verify --verbose build/StageFit.app` on a Mac.
5. On macOS, manually exercise: shortcut, double-click, optional green click, left/right Dock, different screen layouts, Settings persistence, Login Items approval, About panel, and Accessibility prompts.
6. Never claim macOS runtime validation based on Swift parse-only checks on Linux.

## Releases
- Bump `CFBundleShortVersionString` and `CFBundleVersion` in `Resources/Info.plist` together.
- Update `CHANGELOG.md` with user-visible changes.
- Use `make dist` on macOS to build and ZIP the app.
- Keep the project under the MIT License. Preserve `LICENSE` and required copyright notices in distributions.
