#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Macster"
VERSION="${VERSION:-0.1.2}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICONSET_DIR="$BUILD_DIR/$APP_NAME.iconset"
LOGO_PATH="$ROOT_DIR/assets/macster.png"

if [[ ! -f "$LOGO_PATH" ]]; then
  echo "Missing logo: $LOGO_PATH" >&2
  exit 1
fi

rm -rf "$BUILD_DIR" "$DIST_DIR"
mkdir -p "$BUILD_DIR" "$DIST_DIR" "$MACOS_DIR" "$RESOURCES_DIR" "$ICONSET_DIR"

make_icon() {
  local size="$1"
  local scale="$2"
  local pixels="$((size * scale))"
  local suffix=""

  if [[ "$scale" == "2" ]]; then
    suffix="@2x"
  fi

  /usr/bin/sips -z "$pixels" "$pixels" "$LOGO_PATH" --out "$ICONSET_DIR/icon_${size}x${size}${suffix}.png" >/dev/null
}

make_icon 16 1
make_icon 16 2
make_icon 32 1
make_icon 32 2
make_icon 128 1
make_icon 128 2
make_icon 256 1
make_icon 256 2
make_icon 512 1
make_icon 512 2

/usr/bin/iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/$APP_NAME.icns"

swift build -c release --package-path "$ROOT_DIR" --product "$APP_NAME"
swift build -c release --package-path "$ROOT_DIR" --product MacsterCtl

cp "$ROOT_DIR/.build/release/$APP_NAME" "$MACOS_DIR/$APP_NAME"
cp "$ROOT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$LOGO_PATH" "$RESOURCES_DIR/macster.png"
cp "$ROOT_DIR/.build/release/MacsterCtl" "$RESOURCES_DIR/macsterctl"
chmod 755 "$RESOURCES_DIR/macsterctl"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER:-1}" "$CONTENTS_DIR/Info.plist"

/usr/bin/codesign --force --deep --sign - "$APP_BUNDLE" >/dev/null

ditto -c -k --keepParent "$APP_BUNDLE" "$DIST_DIR/$APP_NAME-$VERSION.zip"

DMG_ROOT="$BUILD_DIR/dmg-root"
mkdir -p "$DMG_ROOT"
cp -R "$APP_BUNDLE" "$DMG_ROOT/"
ln -s /Applications "$DMG_ROOT/Applications"

hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$DMG_ROOT" \
  -ov \
  -format UDZO \
  "$DIST_DIR/$APP_NAME-$VERSION.dmg" >/dev/null

(
  cd "$DIST_DIR"
  shasum -a 256 "$APP_NAME-$VERSION.dmg" "$APP_NAME-$VERSION.zip" > checksums.txt
)

echo "Built $APP_BUNDLE"
echo "Built $DIST_DIR/$APP_NAME-$VERSION.dmg"
echo "Built $DIST_DIR/$APP_NAME-$VERSION.zip"
