#!/usr/bin/env bash
# Builds dist/Macster.app (universal: Apple silicon and Intel), plus a DMG, a ZIP, and checksums.
#
#   ./scripts/build-release.sh                 # version from VERSION
#   VERSION=1.2.3 ./scripts/build-release.sh   # override
#   ARCHS=arm64 ./scripts/build-release.sh     # faster local build for this Mac only
set -euo pipefail

APP_NAME="Macster"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${VERSION:-$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
ARCHS="${ARCHS:-arm64 x86_64}"
MINIMUM_MACOS="14.0"

BUILD_DIR="$ROOT_DIR/build"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICONSET_DIR="$BUILD_DIR/$APP_NAME.iconset"
LOGO_PATH="$ROOT_DIR/assets/macster.png"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Invalid version: $VERSION" >&2
  exit 1
fi
if [[ ! -f "$LOGO_PATH" ]]; then
  echo "Missing logo: $LOGO_PATH" >&2
  exit 1
fi

rm -rf "$BUILD_DIR" "$DIST_DIR"
mkdir -p "$ICONSET_DIR" "$MACOS_DIR" "$RESOURCES_DIR"

# App icon.
for size in 16 32 128 256 512; do
  /usr/bin/sips -z "$size" "$size" "$LOGO_PATH" --out "$ICONSET_DIR/icon_${size}x${size}.png" >/dev/null
  /usr/bin/sips -z "$((size * 2))" "$((size * 2))" "$LOGO_PATH" --out "$ICONSET_DIR/icon_${size}x${size}@2x.png" >/dev/null
done
/usr/bin/iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/$APP_NAME.icns"

# The app and its watchdog: one slice per architecture, merged into universal binaries.
for product in Macster macster-watchdog; do
  slices=()
  for arch in $ARCHS; do
    triple="$arch-apple-macosx$MINIMUM_MACOS"
    swift build -c release --package-path "$ROOT_DIR" --triple "$triple" --product "$product"
    slices+=("$(swift build -c release --package-path "$ROOT_DIR" --triple "$triple" --show-bin-path)/$product")
  done
  /usr/bin/lipo -create "${slices[@]}" -output "$MACOS_DIR/$product"
done

cp "$ROOT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Set :LSMinimumSystemVersion $MINIMUM_MACOS" "$CONTENTS_DIR/Info.plist"
printf 'APPL????' > "$CONTENTS_DIR/PkgInfo"

# Ad-hoc signature with the hardened runtime. Nested code is signed before the bundle that contains it.
/usr/bin/codesign --force --sign - --options runtime --timestamp=none \
  --identifier io.github.macster.watchdog "$MACOS_DIR/macster-watchdog"
/usr/bin/codesign --force --sign - --options runtime --timestamp=none "$APP_BUNDLE"
/usr/bin/codesign --verify --strict --deep "$APP_BUNDLE"

ditto -c -k --keepParent "$APP_BUNDLE" "$DIST_DIR/$APP_NAME-$VERSION.zip"

DMG_ROOT="$BUILD_DIR/dmg-root"
mkdir -p "$DMG_ROOT"
cp -R "$APP_BUNDLE" "$DMG_ROOT/"
ln -s /Applications "$DMG_ROOT/Applications"
# hdiutil sometimes fails with "Resource busy" on CI machines, so give it a few tries.
for attempt in 1 2 3; do
  if hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_ROOT" -ov -format UDZO "$DIST_DIR/$APP_NAME-$VERSION.dmg" >/dev/null; then
    break
  elif [[ "$attempt" == 3 ]]; then
    echo "Couldn't create the DMG" >&2
    exit 1
  fi
  sleep 5
done

(
  cd "$DIST_DIR"
  shasum -a 256 "$APP_NAME-$VERSION.dmg" "$APP_NAME-$VERSION.zip" > checksums.txt
)

echo "Built $APP_BUNDLE ($(/usr/bin/lipo -archs "$MACOS_DIR/$APP_NAME"))"
echo "Built $DIST_DIR/$APP_NAME-$VERSION.dmg"
echo "Built $DIST_DIR/$APP_NAME-$VERSION.zip"
