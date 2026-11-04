# MacRemote

A native macOS app in SwiftUI that lets a Bluetooth remote control the Mac,
starting with Amazon Fire TV (Alexa Voice) remotes. It lives in the window
and the menu bar; settings and button choices are in UserDefaults.

How it works: `Remote/HIDMonitor.swift` finds HID devices (IOHIDManager),
opens Fire TV remotes (vendor 0x1949 or name match) exclusively when it can,
and reports (usage page, usage, pressed). `Remote/RemoteEngine.swift` looks
the button up in the `Profile` for the current mode (Navigation or Pointer)
and runs it once, repeats it, or keeps moving the pointer while held.
`Remote/EventSynth.swift` posts the CGEvents. Permissions: Input Monitoring
(read the remote) and Accessibility (post events). Buttons the app does not
know are learned by usage and show in the Buttons page.

## Layout

- `Sources/MacRemote/` the app. `App.swift` has the window, menu bar item, menus, and where settings live.
- `Sources/MacRemoteKit/` rules and data logic with no SwiftUI. Tests in `Tests/MacRemoteKitTests/`.
- `Package.swift` a Swift package. There is no Xcode project.
- `build.sh` builds, signs, and installs `/Applications/MacRemote.app`.
- `Icon/AppIcon.icon` the app icon, an Icon Composer file (JSON plus SVG layers). `build.sh` compiles it with `tools/make_icon.sh`; `tools/icon_review.sh` renders every look into one PNG.
- `docs/` the brief, the screen index, and the user stories, when they exist.

## Build and check

- Build and install: `./build.sh`. Add `--open` to restart the app with the new build. The build shows warnings; fix them.
- Unit tests: `swift test --scratch-path ~/Library/Developer/MacRemote/test-build`.
- Self-test (the app's real functions on a /tmp store): `tools/selftest.sh`. Exit 0 when every check passes. Add a check for every story with logic in `SelfTest.swift`.
- After every UI change, take snapshots with sample data and look at them: `tools/snap.sh`.
  It writes `/tmp/MacRemote-shots/<page>-light.png` and `-dark.png` for every sidebar page, and `settings-<tab>-light.png` and `-dark.png` for every Settings tab, then quits. `APP_SNAPSHOT_PAGES=remote,settings tools/snap.sh` limits the pages.
  For a panel, sheet, or popover, add a capture to `Snapshot.swift` like the Settings loop.
- Snapshots, seed data, and the self-test refuse to run without `APP_STORE`. With it set, settings go to a throwaway defaults domain and no real remote is opened.
- The self-test drives the real engine with simulated presses into a recorder; nothing is posted to the Mac.
- Ad hoc builds lose Input Monitoring and Accessibility after every rebuild: remove MacRemote from both lists in Privacy & Security and add it again.
- Then check the grid: `tools/grid-lint.sh` and `swift tools/check-layout.swift /tmp/MacRemote-shots/*-layout.json`. Both print PASS.
- A change is done when the build has no errors, the grid checks pass, and you looked at the light and dark snapshots.

## Design rules

- Use Apple's controls and system styles. Only the accent color is custom: `UI/Theme.swift` (`ThemeStore.defaultID`). People change it, and light or dark mode, in Settings > Appearance.
- Views use `.tint`, `Palette.accent`, `Palette.accentText` (accent-colored text), and `Palette.onAccent` (text on an accent fill). Never hard-code colors, radii, or durations in views.
- Compare accents: add `APP_ACCENT=<id>` to the snapshot command.
- Spacing comes from `Space` in `UI/Grid.swift`, on a 4 pt grid. Mark custom pages and cards with `.gridArea` and `.gridProbe`.
- Windows open calm: `.noInitialFocus()` on every window and sheet (no focus ring or selected text on open), `.fitsContent()` on sheets and Settings tabs (no scroll bar with nothing to scroll). System scroll bars. Both in `UI/WindowBehavior.swift`.
- Settings: one tab per topic in `SettingsView.swift`, one grouped Form per tab. Add a case to `SettingsTab` for a new tab.
- Window chrome (title bar, toolbar, sidebar, menus, sheets) stays system. Buttons use system styles, like `.borderedProminent`.
- Colors: `.primary`, `.secondary`, `.tint`, and system colors. Never fixed grays or white for text.
- Every action has a menu bar item and a keyboard shortcut.
- `Label` for icon and text pairs. SF Symbols for icons.
- `ContentUnavailableView` for empty states.
- Liquid Glass belongs to floating controls only, never to content.

## Skills

The bama plugin has a skill for each step: `mac-design` (design rules),
`design-system` (accent and tokens), `layout-grid`, `ux-design`,
`swift-swiftui`, `os-integrations`, `performance`, `build-and-verify`,
`test-mac-app`, `app-icon`, `user-stories`, and `improve-loop`. Use them.

## Git

- Commit after each working change, with a message that says what the user can now do.
