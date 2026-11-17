# StageFit

A small, native macOS menu-bar utility that fits the focused window beside Stage Manager's recent-app thumbnails — without installing a full window manager.

**Requirements:** macOS 13 or later, Apple Command Line Tools (`xcode-select --install`). No third-party packages or services.

## Install / upgrade

1. Quit the currently running StageFit from its menu.
2. From the extracted project directory, run:

   ```sh
   make check test build
   ditto build/StageFit.app /Applications/StageFit.app
   open /Applications/StageFit.app
   ```

3. In **System Settings → Privacy & Security → Accessibility**, allow StageFit. If a prior version was already authorized but macOS refuses access, remove and re-add the app's entry.
4. To start automatically when signing in, enable **Launch at Login** in the StageFit menu. If requested, approve it under **System Settings → General → Login Items & Extensions**.

**Upgrade compatibility:** the bundle identifier (`dev.stagefit.macos`) and preference keys are unchanged from 1.3. The locally signed app may require Accessibility reapproval after upgrading. Install into `/Applications` *before* enabling Launch at Login; login registration is for the installed app, not a temporary copy.

## Menu and controls

| Item / gesture | Default | Behavior |
|---|---|---|
| **Fit / Restore Front Window** | Available | Fit the focused window, or restore its previous frame if unchanged |
| **Control + Option + Command + F** | Enabled | Global fit/restore shortcut |
| **Fit on Title Bar Double-Click** | On (new installs) | Toggles fit/restore on recognized standard title bars |
| **Replace Green Button Click** | Off | Optional fit/restore toggle; modifier-click remains native |
| **Stage Manager Space** | 190 pt | Select reserved strip width (150–260 pt) |
| **Launch at Login** | Off until enabled | macOS native login-item registration (approval may be required) |
| **Accessibility Settings…** | Available | Opens macOS permission settings |
| **About StageFit** | Available | Standard macOS About panel; version and Copyright © 2026 Erez Korn |
| **Quit StageFit** | Available | Exits utility |

**Fit/restore toggle:** The first activation saves the focused window's original position and size, then fits it beside Stage Manager. Activate again to restore the original frame. If the window has been manually moved or resized since StageFit last fitted it, its saved restore state is discarded; the next activation creates a new fit from the user-adjusted frame. Each window is tracked independently. Saved restore states are in-memory only and reset when StageFit quits. The same behavior applies to the shortcut, recognized title-bar double-clicks, and the optional green-button replacement.

StageFit reserves an estimated Stage Manager strip rather than querying a documented exact workspace size. On custom title bars, macOS may handle double-click natively. The utility never needs network access and does not store window titles or mouse events.

## Repository structure

```text
StageFit/
├── Sources/StageFit/           # Native AppKit utility + window handling, toggle snapshot
├── Resources/Info.plist        # Bundle metadata and copyright
├── Scripts/                    # Build, test, check, distributable ZIP
├── Tests/main.swift            # Deterministic geometry regression tests
├── .github/workflows/ci.yml    # macOS CI
├── Makefile                    # Local commands
├── .gitignore / .editorconfig
├── AGENTS.md                   # Coding-agent guidance
├── LICENSE                     # MIT License
└── CHANGELOG.md
```

## Development

```sh
make check      # Swift parse, shell syntax and Info.plist validation
make test       # Pure geometry tests (runs on macOS or Linux)
make build      # Create build/StageFit.app (macOS only)
make dist       # Build and package dist/StageFit-<version>-macOS.zip
make install    # Build and copy to /Applications (quit running copy first)
make clean      # Remove generated build/dist directories
```

The project intentionally builds an application bundle directly with `swiftc` rather than introducing Xcode project metadata or SwiftPM packaging, which alone would not produce the signed `.app` bundle needed by login-item registration. `Scripts/build.sh` targets macOS 13 and ad-hoc signs the app for local use. To sign with a stable identity:

```sh
STAGEFIT_SIGNING_IDENTITY="Developer ID Application: Example" make build
```

Provide your own signing identity; none is embedded in the repository. Ad-hoc signing is suitable for local use, but publicly distributing a binary normally calls for a Developer ID identity, hardened runtime and notarization. The project does not include those distribution credentials or steps.

## Validation and limitations

CI builds and tests on a macOS runner. Geometry tests are portable, but live Accessibility, mouse-event interception, display arrangements, the About panel and Login Items still require hands-on testing on macOS. Tests must not claim that parse-only checking validates framework APIs.

## Privacy and rights

StageFit does not phone home, collect telemetry, or save window contents. The event tap inspects pointer coordinates transiently only to identify supported title-bar/button clicks. No personal paths, credentials, API keys, or signing identities are included in the source tree. The only personal name intentionally included is the requested copyright attribution.

Copyright © 2026 Erez Korn.

Licensed under the [MIT License](LICENSE). You may use, modify, distribute, and sell copies of StageFit, provided the copyright and license notice are included. The software is provided without warranty.
