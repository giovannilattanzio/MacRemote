#!/bin/zsh
# Snapshots of every page in light and dark, with seed data, on a fresh test store.
# Usage: tools/snap.sh            all pages
#        APP_SNAPSHOT_PAGES=remote,settings tools/snap.sh
set -u
app=/Applications/MacRemote.app/Contents/MacOS/MacRemote
store=test
shots=/tmp/MacRemote-shots
# A crashed run leaves saved window state, and the next launch would wait on a "reopen windows?" alert.
rm -rf ~/Library/Saved\ Application\ State/com.gilattanzio.macremote.savedState
# Seed data only fills an empty store, so start from nothing.

rm -rf $shots
APP_STORE=$store APP_SEED=1 APP_SNAPSHOT=$shots $app
