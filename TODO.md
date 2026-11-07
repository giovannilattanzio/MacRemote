# TODO

Things to improve in MacRemote.

- [x] **GitHub Action for releases**: pushing a `v*` tag builds the universal app with `tools/release.sh`, signs it with the self-signed "MacRemote Signing" certificate from the repository secrets, and attaches the zip to a GitHub release. Developer ID and notarization can come later by changing the secrets.
- [x] **On-screen keyboard for text fields** (opens when the remote moves focus into a text field or clicks one; Show Keyboard action and ⇧⌘K open it by hand): when a text field gets focus (clicked or selected with the remote), show a keyboard you can type on with the remote.
- [x] **Keep permissions across builds** (releases and `build.sh` sign with the "MacRemote Signing" certificate; local builds need it imported into the login keychain once, see README.md): stop losing Input Monitoring and Accessibility after every rebuild or update. Ad hoc signing gives each build a new identity, so sign every build with the same certificate (a self-signed local one for development, Developer ID for releases) so macOS keeps the permissions.
