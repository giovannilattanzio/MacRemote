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
#   3. Nothing: signed ad hoc. Other Macs block the first open; see README.md.
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
[[ -n "$identity" ]] || identity=-

echo "building universal release…"
swift build -c release --arch arm64 --arch x86_64 --package-path "$here" --scratch-path "$scratch" 2>&1 \
  | grep -E "error|warning:|Build complete" || true
bin="$scratch/apple/Products/Release/$name"
[[ -x "$bin" ]] || { echo "build failed"; exit 1; }

version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$here/Info.plist.in")
app="$dist/$name.app"
rm -rf "$dist"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/$name"
sed -e "s/__BUILD__/$(date +%Y%m%d%H%M)/" "$here/Info.plist.in" > "$app/Contents/Info.plist"
[[ -f "$here/Resources/Assets.car" ]] || "$here/tools/make_icon.sh"
cp -X "$here/Resources/Assets.car" "$here/Resources/AppIcon.icns" "$app/Contents/Resources/"
xattr -cr "$app"

if [[ "$identity" == "-" ]]; then
  codesign --force --sign - "$app"
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
elif [[ "$identity" != "-" ]]; then
  echo "signed with $identity, not notarized: set NOTARY_PROFILE to notarize"
else
  echo "signed ad hoc: other Macs need Open Anyway once (README.md)"
fi
lipo -archs "$app/Contents/MacOS/$name" | sed 's/^/architectures: /'
echo "ready: $zip"
