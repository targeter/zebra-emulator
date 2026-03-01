#!/usr/bin/env bash

set -euo pipefail

APP_NAME="ZebraBrowserPrintEmulator"
APP_DISPLAY_NAME="Zebra Browser Print Emulator"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_DISPLAY_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
ZIP_PATH="$DIST_DIR/$APP_DISPLAY_NAME.zip"

rm -rf "$APP_DIR" "$ZIP_PATH"
mkdir -p "$MACOS_DIR"

swift build -c release --product "$APP_NAME" --package-path "$ROOT_DIR"
BIN_DIR="$(swift build -c release --show-bin-path --package-path "$ROOT_DIR")"

cp "$BIN_DIR/$APP_NAME" "$MACOS_DIR/$APP_NAME"
cp "$ROOT_DIR/Packaging/Info.plist" "$CONTENTS_DIR/Info.plist"
chmod +x "$MACOS_DIR/$APP_NAME"

if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
  codesign --force --deep --sign "$CODESIGN_IDENTITY" "$APP_DIR"
fi

ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"

printf "Built app bundle: %s\n" "$APP_DIR"
printf "Built zip archive: %s\n" "$ZIP_PATH"
