# TODO

Things to improve in MacRemote.

- [ ] **GitHub Action for releases**: build the universal app with `tools/release.sh` on a tag push and attach it to a GitHub release (Developer ID signing and notarization when the secrets are set, ad hoc otherwise).
- [ ] **On-screen keyboard for text fields**: when a text field gets focus (clicked or selected with the remote), show a keyboard you can type on with the remote.
- [ ] **Keep permissions across builds**: stop losing Input Monitoring and Accessibility after every rebuild or update. Ad hoc signing gives each build a new identity, so sign every build with the same certificate (a self-signed local one for development, Developer ID for releases) so macOS keeps the permissions.
