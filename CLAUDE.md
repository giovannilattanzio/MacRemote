# MacRemote

A native macOS app in SwiftUI that lets a Bluetooth remote control the Mac,
starting with Amazon Fire TV (Alexa Voice) remotes. It lives in the window
and the menu bar; settings and button choices are in UserDefaults.

How it works: `Remote/HIDMonitor.swift` finds HID devices (IOHIDManager),
opens Fire TV remotes (vendor 0x1949 or name match) exclusively when it can (keyboard-class remotes usually cannot be seized, so they stay shared with macOS),
and reports (usage page, usage, pressed). `Remote/RemoteEngine.swift` looks
the button up in the `Profile` for the current mode (Navigation or Pointer)
and runs it once, repeats it, or keeps moving the pointer while held.
`Remote/EventSynth.swift` posts the CGEvents. Permissions: Input Monitoring
(read the remote) and Accessibility (post events). Buttons the app does not
know are learned by usage and show in the Buttons page.

## Layout

- `Sources/MacRemote/` the app. `Main.swift` has the app delegate and menus, `Windows.swift` the windows and menu bar item, `Models.swift` where settings live.
- `Sources/MacRemoteKit/` rules and data logic with no SwiftUI. Tests in `Tests/MacRemoteKitTests/`.
- `Package.swift` a Swift package. There is no Xcode project.
- `build.sh` builds, signs, and installs `/Applications/MacRemote.app`.
- `tools/release.sh` builds a universal copy for other Macs in `dist/` (Developer ID and notarization when available, ad hoc otherwise). Install steps are in `README.md`.
- `Icon/AppIcon.icon` the app icon, an Icon Composer file (JSON plus SVG layers). `build.sh` compiles it with `tools/make_icon.sh`; `tools/icon_review.sh` renders every look into one PNG.
- `docs/` the brief, the screen index, and the user stories, when they exist.

## Build and check

- Build and install: `./build.sh`. Add `--open` to restart the app with the new build. The build shows warnings; fix them.
- Unit tests: `swift test --scratch-path ~/Library/Developer/MacRemote/test-build`.
- Self-test (the app's real functions on a /tmp store): `tools/selftest.sh`. Exit 0 when every check passes. Add a check for every story with logic in `SelfTest.swift`.
- After every UI change, take snapshots with sample data and look at them: `tools/snap.sh`.
  It writes `/tmp/MacRemote-shots/<page>-light.png` and `-dark.png` for every sidebar page, and `settings-light.png` and `settings-dark.png`, then quits. `APP_SNAPSHOT_PAGES=remote,settings tools/snap.sh` limits the pages.
- Snapshots, seed data, and the self-test refuse to run without `APP_STORE`. With it set, settings go to a throwaway defaults domain and no real remote is opened.
- The self-test drives the real engine with simulated presses into a recorder; nothing is posted to the Mac.
- Ad hoc builds lose Input Monitoring and Accessibility after every rebuild: remove MacRemote from both lists in Privacy & Security and add it again.
- Then check the grid: `tools/grid-lint.sh` prints PASS.
- A change is done when the build has no errors or warnings, the grid check passes, and you looked at the light and dark snapshots. Snapshots run on this Mac's macOS only: the macOS 12 guarantee comes from the compiler and the rules above.

## Design rules

- **The app must run on macOS 12.7 and later.** `Package.swift` targets macOS 12, so the compiler rejects newer APIs. Wrap anything newer in `if #available(macOS 13, *)` (or 14, 26) with a macOS 12 fallback, as `SettingsView.swift` (login item) and `ModeHUD.swift` (Liquid Glass) do. Never raise the target.
- Not available on macOS 12, do not use: `@Observable`/`@Bindable` (use `ObservableObject`/`@Published`), SwiftUI `Window`/`MenuBarExtra`/`openWindow`/`openSettings`, `NavigationSplitView`, `.formStyle(.grouped)`, `LabeledContent`, `ContentUnavailableView`, `Task.sleep(for:)` (use `nanoseconds:`), two-argument `onChange`, `SMAppService`.
- The shell is AppKit (`Main.swift`, `Windows.swift`): the main window with an NSSplitViewController sidebar, the Settings window, the menu bar item, and the main menu. Pages are SwiftUI hosted in it.
- Pages use the parts in `UI/Components.swift` (`Page`, `Card`, `CardDivider`, `Row`, `EmptyState`), so they look the same on every macOS version. Symbols go through `Symbol.named(_:)`, which falls back for symbols newer than macOS 12.
- SwiftUI `Table` cells do not inherit environment objects: pass objects into cell views directly.
- Spacing, radii, and widths come from `UI/Grid.swift` (`Space`, `Radius`, `Width`), on a 4 pt grid. Colors: `.primary`, `.secondary`, `.tint`, and system NSColors. The accent is the Mac's own.
- Every action has a menu bar item and a keyboard shortcut (`Main.swift`).
- Settings is called Preferences before macOS 13 (`AppDelegate.settingsTitle`).

## Skills

The bama plugin has a skill for each step (`mac-design`, `swift-swiftui`,
`os-integrations`, `build-and-verify`, `test-mac-app`, and more). Their
advice assumes macOS 26: where it uses a newer API, the macOS 12 rule above wins.

## Git

- Commit after each working change, with a message that says what the user can now do.
