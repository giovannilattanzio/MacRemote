# MacRemote

Control a Mac with a Bluetooth remote, starting with Amazon Fire TV remotes.
Requires macOS 12.7 (Monterey) or later. Runs on Apple silicon and Intel Macs.

## Make a copy for other Macs

```bash
tools/release.sh
```

It writes `dist/MacRemote-<version>.zip`. Copy the zip to the other Mac by
AirDrop, USB drive, or a shared folder.

How smoothly it opens there depends on how it was signed (the script picks the best it finds):

| Signed with | First open on another Mac |
|---|---|
| Developer ID + notarized | Opens with no warning |
| Developer ID, not notarized | Blocked once, then Open Anyway |
| Ad hoc (no certificate, the default here) | Blocked once, then Open Anyway |

To notarize you need the Apple Developer Program (paid). Once you have a
"Developer ID Application" certificate in the keychain:

```bash
xcrun notarytool store-credentials macremote --apple-id <you@example.com> --team-id <TEAMID>
NOTARY_PROFILE=macremote tools/release.sh
```

## Install on another Mac

1. Unzip, and drag **MacRemote** into **Applications**.
2. Open it. If macOS says it cannot verify the app, click **Done**, then open
   **System Settings > Privacy & Security** (on macOS 12: **System Preferences > Security & Privacy > General**), and click **Open Anyway**
   next to MacRemote. Confirm with your password. This is needed once.
3. In MacRemote, click **Allow…** for **Input Monitoring** and **Accessibility**,
   and switch MacRemote on in both lists.
4. Pair the remote: unplug its Fire TV, hold **Home** on the remote for about
   10 seconds, then click **Connect** in Bluetooth settings.
   If the Keyboard Setup Assistant opens, close it.

Permissions stay granted on that Mac as long as you keep the same copy. Installing a
new ad hoc build means granting them again (remove the old MacRemote entries
with **–** first).
