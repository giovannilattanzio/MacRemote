#!/bin/zsh
# Builds a copy of MacRemote to install on other Macs: dist/MacRemote-<version>.zip
# A universal app (Apple silicon and Intel) that does not touch /Applications here.
#
# Signing, best first:
#   1. A "Developer ID Application" certificate (Apple Developer Program) plus
#      NOTARY_PROFILE=<name> from `xcrun notarytool store-credentials <name>`:
#      signed, notarized, and stapled. Opens on any Mac with no warning.
#   2. A Developer ID certificate without NOTARY_PROFILE: signed but not notarized.
#      Other Macs still block the first open.
#   3. The self-signed "MacRemote Signing" certificate (what GitHub Actions uses):
#      other Macs block the first open, but every version counts as the same app,
#      so Input Monitoring and Accessibility stay granted across updates.
#   4. Nothing: signed ad hoc. Other Macs block the first open, and every update
#      needs the permissions granted again; see README.md.
#
# VERSION=0.2 sets the version (the release workflow passes the tag); otherwise
# the one in Info.plist.in.
#
# Usage: tools/release.sh
#        SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" NOTARY_PROFILE=macremote tools/release.sh
set -euo pipefail
here=${0:A:h:h}
name="MacRemote"
scratch="$HOME/Library/Developer/$name/release-build"
dist="$here/dist"

identity="${SIGN_IDENTITY:-}"
if [[ -z "$identity" ]]; then
  identity=$(security find-identity -v -p codesigning 2>/dev/null | grep -m1 -o '"Developer ID Application: [^"]*"' | tr -d '"' || true)
fi
if [[ -z "$identity" ]]; then
  # Self-signed certificates are not trusted, so find-identity lists them without -v.
  identity=$(security find-identity -p codesigning 2>/dev/null | grep -m1 -o '"MacRemote Signing"' | tr -d '"' || true)
fi
[[ -n "$identity" ]] || identity=-

echo "building universal release…"
build=(swift build -c release --arch arm64 --arch x86_64 --package-path "$here" --scratch-path "$scratch")
log="$scratch-log.txt"
mkdir -p "${scratch:h}"
code=0
"${build[@]}" > "$log" 2>&1 || code=$?
grep -E "error|warning:|Build complete" "$log" || true
# Ask SwiftPM where the universal build went: newer versions use a different folder.
bin="$("${build[@]}" --show-bin-path 2>/dev/null)/$name"
if [[ $code -ne 0 || ! -x "$bin" ]]; then
  echo "build failed (exit $code, looked for $bin); full output:"
  cat "$log"
  exit 1
fi

version="${VERSION:-$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$here/Info.plist.in")}"
app="$dist/$name.app"
rm -rf "$dist"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/$name"
sed -e "s/__BUILD__/$(date +%Y%m%d%H%M)/" "$here/Info.plist.in" > "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$app/Contents/Info.plist"
[[ -f "$here/Resources/Assets.car" ]] || "$here/tools/make_icon.sh"
cp -X "$here/Resources/Assets.car" "$here/Resources/AppIcon.icns" "$app/Contents/Resources/"
xattr -cr "$app"

if [[ "$identity" == "-" ]]; then
  codesign --force --sign - "$app"
elif [[ "$identity" != "Developer ID Application:"* ]]; then
  # Self-signed: Apple's timestamp server and notarization do not apply.
  codesign --force --sign "$identity" "$app"
else
  # Notarization needs the hardened runtime and a secure timestamp.
  codesign --force --options runtime --timestamp --sign "$identity" "$app"
fi
codesign --verify --strict "$app"

zip="$dist/$name-$version.zip"
ditto -c -k --keepParent "$app" "$zip"

if [[ "$identity" != "-" && -n "${NOTARY_PROFILE:-}" ]]; then
  echo "notarizing (a few minutes)…"
  xcrun notarytool submit "$zip" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$app"
  rm "$zip"
  ditto -c -k --keepParent "$app" "$zip"
  spctl --assess --type execute --verbose "$app"
  echo "notarized: opens on any Mac"
elif [[ "$identity" == "Developer ID Application:"* ]]; then
  echo "signed with $identity, not notarized: set NOTARY_PROFILE to notarize"
elif [[ "$identity" != "-" ]]; then
  echo "signed with $identity: other Macs need Open Anyway once, permissions survive updates"
else
  echo "signed ad hoc: other Macs need Open Anyway once (README.md)"
fi
lipo -archs "$app/Contents/MacOS/$name" | sed 's/^/architectures: /'
echo "ready: $zip"
