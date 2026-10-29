#!/usr/bin/env bash
# Builds AnswerSearch.app into dist/.
#
#   scripts/build_app.sh                         # ad-hoc signed, runs on this Mac
#   VERSION=1.2.0 scripts/build_app.sh           # set the version shown in Settings
#   APP_IDENTITY="Developer ID Application: Your Name (TEAMID)" scripts/build_app.sh
#
# Requires macOS 26+ and Xcode 26+ (Swift 6). The LocalLM Lab SDK binaries are downloaded and
# checksum-verified by SwiftPM on the first build.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="AnswerSearch"
VERSION="${VERSION:-0.1.0}"
APP_IDENTITY="${APP_IDENTITY:--}"
APP_DIR="$ROOT/dist/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"

cd "$ROOT"
echo "Building $APP_NAME $VERSION (release)..."
swift build -c release --arch arm64
BIN_DIR="$(swift build -c release --arch arm64 --show-bin-path)"

echo "Assembling $APP_DIR..."
rm -rf "$APP_DIR"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Frameworks" "$CONTENTS/Resources"

cp Resources/Info.plist "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$CONTENTS/Info.plist"
cp Resources/AnswerSearch.icns Resources/answersearch_menu.png "$CONTENTS/Resources/"

cp "$BIN_DIR/$APP_NAME" "$CONTENTS/MacOS/$APP_NAME"
for framework in "$BIN_DIR"/LocalLMLabSDK*.framework; do
  cp -R "$framework" "$CONTENTS/Frameworks/"
done
install_name_tool -add_rpath "@executable_path/../Frameworks" "$CONTENTS/MacOS/$APP_NAME"

echo "Signing (identity: $APP_IDENTITY)..."
SIGN_FLAGS=(--force --timestamp=none)
if [[ "$APP_IDENTITY" != "-" ]]; then
  SIGN_FLAGS=(--force --timestamp --options runtime)
fi
for framework in "$CONTENTS"/Frameworks/*.framework; do
  codesign "${SIGN_FLAGS[@]}" --sign "$APP_IDENTITY" "$framework"
done
codesign "${SIGN_FLAGS[@]}" --sign "$APP_IDENTITY" "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"

echo "Built $APP_DIR"
echo "Run it with: open \"$APP_DIR\""
