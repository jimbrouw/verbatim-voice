#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Voice&"
APP_DIR="$ROOT_DIR/dist/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

cd "$ROOT_DIR"

echo "🔨 Building Voice& v3 release binary (In-process CoreML Parakeet ANE)..."
swift build -c release

echo "📦 Assembling $APP_NAME.app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$ROOT_DIR/.build/release/Verbatim" "$MACOS_DIR/Voice&"
chmod +x "$MACOS_DIR/Voice&"

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>Voice&amp;</string>
  <key>CFBundleIconFile</key>
  <string>Voice&amp;</string>
  <key>CFBundleIdentifier</key>
  <string>app.voiceand.voice</string>
  <key>CFBundleName</key>
  <string>Voice&amp;</string>
  <key>CFBundleDisplayName</key>
  <string>Voice&amp;</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>3.0.0</string>
  <key>CFBundleVersion</key>
  <string>300</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSMicrophoneUsageDescription</key>
  <string>Voice&amp; needs access to your microphone to transcribe your voice into text locally on the Apple Neural Engine.</string>
  <key>NSScreenCaptureUsageDescription</key>
  <string>Voice&amp; needs screen recording access to understand visible technical keywords on your screen for enhanced transcription accuracy.</string>
  <key>NSAppleEventsUsageDescription</key>
  <string>Voice&amp; uses Apple Events to inject transcribed text into your active cursor position.</string>
</dict>
</plist>
PLIST

if [[ -f "$ROOT_DIR/assets/generated/Verbatim.icns" ]]; then
  cp "$ROOT_DIR/assets/generated/Verbatim.icns" "$RESOURCES_DIR/Voice&.icns"
fi

# Sign with a stable certificate so macOS TCC permissions (Accessibility, Microphone,
# Screen Recording) survive rebuilds. Ad-hoc signatures pin the grant to the binary's
# cdhash, which changes on every build and silently revokes Accessibility.
# Override with: SIGN_IDENTITY="<name or SHA-1>" ./scripts/build_app.sh
SIGN_IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | grep -m1 'Apple Development' | awk '{print $2}')}"
if [[ -n "$SIGN_IDENTITY" ]]; then
  echo "🔏 Code signing with stable identity $SIGN_IDENTITY..."
  codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_DIR"
else
  echo "⚠️  No signing identity found — falling back to ad-hoc (Accessibility must be re-granted after every build)"
  codesign --force --deep --sign - "$APP_DIR"
fi
codesign -d -r- "$APP_DIR" 2>&1 | grep designated || true

ZIP_NAME="VoiceAnd-v3.0.0-macOS-arm64.zip"
echo "🗜️ Packaging $ZIP_NAME..."
ditto -c -k --keepParent "$APP_DIR" "$ROOT_DIR/dist/$ZIP_NAME"

echo ""
echo "✅ Voice& v3 Build Complete!"
echo "   Application: $APP_DIR"
echo "   Release Zip: $ROOT_DIR/dist/$ZIP_NAME"
