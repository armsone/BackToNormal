#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
ROOT_DIR=${SCRIPT_DIR:h}
INFO_PLIST="$ROOT_DIR/Resources/Info.plist"
ICON_SOURCE="$ROOT_DIR/Resources/AppIcon.png"
BACKGROUND_SOURCE="$ROOT_DIR/Resources/DMGBackground.png"
DIST_DIR="$ROOT_DIR/dist"
APP_NAME=BTN
EXECUTABLE_NAME=BTN
APP_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")
APP_PATH="$DIST_DIR/$APP_NAME.app"
DMG_PATH="$DIST_DIR/$APP_NAME-$APP_VERSION.dmg"
CHECKSUM_PATH="$DMG_PATH.sha256"
CODESIGN_IDENTITY=${CODESIGN_IDENTITY:--}
NOTARY_PROFILE=${NOTARY_PROFILE:-}
NOTARIZE=false

if [[ "${1:-}" == "--notarize" ]]; then
  NOTARIZE=true
elif [[ $# -gt 0 ]]; then
  printf 'Usage: %s [--notarize]\n' "${0:t}" >&2
  exit 64
fi

if [[ "$NOTARIZE" == true ]]; then
  if [[ "$CODESIGN_IDENTITY" != "Developer ID Application:"* ]]; then
    printf 'error: notarization requires a Developer ID Application identity.\n' >&2
    exit 64
  fi
  if [[ -z "$NOTARY_PROFILE" ]]; then
    printf 'error: notarization requires NOTARY_PROFILE.\n' >&2
    exit 64
  fi
fi

for source in "$INFO_PLIST" "$ICON_SOURCE" "$BACKGROUND_SOURCE"; do
  if [[ ! -f "$source" ]]; then
    printf 'error: missing packaging resource: %s\n' "$source" >&2
    exit 66
  fi
done

mkdir -p "$DIST_DIR" "$ROOT_DIR/.build/btn-release-cache" "$ROOT_DIR/.build/btn-release-config" "$ROOT_DIR/.build/btn-release-security"
WORK_DIR=$(mktemp -d "$DIST_DIR/.package.XXXXXX")
RW_DMG="$WORK_DIR/$APP_NAME-rw.dmg"
MOUNT_DEVICE=

cleanup() {
  if [[ -n "$MOUNT_DEVICE" ]]; then
    hdiutil detach "$MOUNT_DEVICE" -force >/dev/null 2>&1 || true
  fi
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

build_arch() {
  local arch="$1"
  local triple="$2"
  local scratch="$ROOT_DIR/.build/btn-release-$arch"
  local module_cache="$scratch/module-cache"

  CLANG_MODULE_CACHE_PATH="$module_cache" SWIFTPM_MODULECACHE_OVERRIDE="$module_cache" \
    swift build \
      --package-path "$ROOT_DIR" \
      --cache-path "$ROOT_DIR/.build/btn-release-cache" \
      --config-path "$ROOT_DIR/.build/btn-release-config" \
      --security-path "$ROOT_DIR/.build/btn-release-security" \
      --scratch-path "$scratch" \
      --disable-sandbox \
      --triple "$triple" \
      -c release \
      --product "$EXECUTABLE_NAME"

  CLANG_MODULE_CACHE_PATH="$module_cache" SWIFTPM_MODULECACHE_OVERRIDE="$module_cache" \
    swift build \
      --package-path "$ROOT_DIR" \
      --cache-path "$ROOT_DIR/.build/btn-release-cache" \
      --config-path "$ROOT_DIR/.build/btn-release-config" \
      --security-path "$ROOT_DIR/.build/btn-release-security" \
      --scratch-path "$scratch" \
      --disable-sandbox \
      --triple "$triple" \
      -c release \
      --show-bin-path
}

printf 'Building universal release executable...\n'
ARM64_BIN_DIR=$(build_arch arm64 arm64-apple-macosx13.0 | tail -1)
X86_64_BIN_DIR=$(build_arch x86_64 x86_64-apple-macosx13.0 | tail -1)

rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
lipo -create \
  "$ARM64_BIN_DIR/$EXECUTABLE_NAME" \
  "$X86_64_BIN_DIR/$EXECUTABLE_NAME" \
  -output "$APP_PATH/Contents/MacOS/$EXECUTABLE_NAME"
chmod 755 "$APP_PATH/Contents/MacOS/$EXECUTABLE_NAME"
ditto "$INFO_PLIST" "$APP_PATH/Contents/Info.plist"
plutil -lint "$APP_PATH/Contents/Info.plist"

ICONSET="$WORK_DIR/AppIcon.iconset"
mkdir -p "$ICONSET"
sips -z 16 16 "$ICON_SOURCE" --out "$ICONSET/icon_16x16.png" >/dev/null
sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET/icon_32x32.png" >/dev/null
sips -z 64 64 "$ICON_SOURCE" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$ICON_SOURCE" --out "$ICONSET/icon_128x128.png" >/dev/null
sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET/icon_256x256.png" >/dev/null
sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$ICON_SOURCE" --out "$ICONSET/icon_512x512@2x.png" >/dev/null
iconutil -c icns "$ICONSET" -o "$APP_PATH/Contents/Resources/AppIcon.icns"

SIGN_ARGS=(--force --options runtime --sign "$CODESIGN_IDENTITY")
if [[ "$NOTARIZE" == true ]]; then
  SIGN_ARGS+=(--timestamp)
fi
codesign "${SIGN_ARGS[@]}" "$APP_PATH"
codesign --verify --deep --strict --verbose=4 "$APP_PATH"

if [[ "$NOTARIZE" == true ]]; then
  NOTARY_ZIP="$WORK_DIR/$APP_NAME-notary.zip"
  ditto -c -k --keepParent "$APP_PATH" "$NOTARY_ZIP"
  xcrun notarytool submit "$NOTARY_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP_PATH"
  xcrun stapler validate "$APP_PATH"
  spctl --assess --type execute --verbose=4 "$APP_PATH"
fi

printf 'Creating styled DMG...\n'
hdiutil create -size 80m -fs HFS+ -volname "$APP_NAME" -type UDIF "$RW_DMG" >/dev/null
ATTACH_PLIST="$WORK_DIR/attach.plist"
hdiutil attach "$RW_DMG" -readwrite -noverify -noautoopen -plist > "$ATTACH_PLIST"
MOUNT_PATH=
for index in {0..12}; do
  candidate=$(/usr/libexec/PlistBuddy -c "Print :system-entities:$index:mount-point" "$ATTACH_PLIST" 2>/dev/null || true)
  if [[ -n "$candidate" ]]; then
    MOUNT_PATH="$candidate"
    MOUNT_DEVICE=$(/usr/libexec/PlistBuddy -c "Print :system-entities:$index:dev-entry" "$ATTACH_PLIST")
    break
  fi
done
if [[ -z "$MOUNT_DEVICE" || -z "$MOUNT_PATH" ]]; then
  printf 'error: could not mount temporary DMG.\n' >&2
  exit 1
fi
MOUNT_NAME=${MOUNT_PATH:t}

ditto "$APP_PATH" "$MOUNT_PATH/$APP_NAME.app"
ln -s /Applications "$MOUNT_PATH/Applications"
mkdir -p "$MOUNT_PATH/.background"
sips -z 500 800 "$BACKGROUND_SOURCE" --out "$MOUNT_PATH/.background/background.png" >/dev/null

osascript \
  -e 'tell application "Finder"' \
  -e "tell disk \"$MOUNT_NAME\"" \
  -e 'open' \
  -e 'set current view of container window to icon view' \
  -e 'set toolbar visible of container window to false' \
  -e 'set statusbar visible of container window to false' \
  -e 'set bounds of container window to {120, 120, 920, 620}' \
  -e 'set viewOptions to the icon view options of container window' \
  -e 'set arrangement of viewOptions to not arranged' \
  -e 'set icon size of viewOptions to 128' \
  -e 'set text size of viewOptions to 14' \
  -e 'set background picture of viewOptions to file ".background:background.png"' \
  -e "set position of item \"$APP_NAME.app\" of container window to {220, 260}" \
  -e 'set position of item "Applications" of container window to {580, 260}' \
  -e 'close container window' \
  -e 'open' \
  -e 'update without registering applications' \
  -e 'delay 2' \
  -e 'end tell' \
  -e 'end tell'

sync
hdiutil detach "$MOUNT_DEVICE" >/dev/null
MOUNT_DEVICE=
rm -f "$DMG_PATH"
hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH" >/dev/null
hdiutil verify "$DMG_PATH"

if [[ "$NOTARIZE" == true ]]; then
  codesign --force --sign "$CODESIGN_IDENTITY" --timestamp "$DMG_PATH"
  codesign --verify --strict --verbose=4 "$DMG_PATH"
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"
  spctl --assess --type open --context context:primary-signature --verbose=4 "$DMG_PATH"
fi

(cd "$DIST_DIR" && shasum -a 256 "${DMG_PATH:t}" > "${CHECKSUM_PATH:t}")
printf 'Created app: %s\n' "$APP_PATH"
printf 'Created DMG: %s\n' "$DMG_PATH"
printf 'Created checksum: %s\n' "$CHECKSUM_PATH"
