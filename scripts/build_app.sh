#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Voice&"
APP_DIR="$ROOT_DIR/dist/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

cd "$ROOT_DIR"

echo "🔨 Building Voice& release binary..."
swift build -c release

echo "📦 Assembling $APP_NAME.app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR/bin"

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
  <string>0.2.0</string>
  <key>CFBundleVersion</key>
  <string>2</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSMicrophoneUsageDescription</key>
  <string>Voice&amp; needs access to your microphone to transcribe your voice into text locally.</string>
</dict>
</plist>
PLIST

cp "$ROOT_DIR/mlx_server.py" "$RESOURCES_DIR/mlx_server.py"
cp "$ROOT_DIR/requirements.txt" "$RESOURCES_DIR/requirements.txt"

if [[ -f "$ROOT_DIR/assets/generated/Verbatim.icns" ]]; then
  cp "$ROOT_DIR/assets/generated/Verbatim.icns" "$RESOURCES_DIR/Voice&.icns"
fi

if [[ -x "$ROOT_DIR/.build/helper-dist/VoiceMLXHelper" ]]; then
  cp "$ROOT_DIR/.build/helper-dist/VoiceMLXHelper" "$RESOURCES_DIR/VoiceMLXHelper"
  chmod +x "$RESOURCES_DIR/VoiceMLXHelper"
elif [[ -d "$ROOT_DIR/venv" ]]; then
  echo "Bundling Python venv into Resources..."
  rsync -a --delete \
    --exclude '__pycache__' \
    --exclude '*.pyc' \
    "$ROOT_DIR/venv" "$RESOURCES_DIR/"
fi

if command -v ffmpeg >/dev/null 2>&1; then
  cp "$(command -v ffmpeg)" "$RESOURCES_DIR/bin/ffmpeg"
  chmod +x "$RESOURCES_DIR/bin/ffmpeg"
fi

echo "🔏 Ad-hoc code signing..."
codesign --force --deep --sign - "$APP_DIR"

ZIP_NAME="VoiceAnd-v0.2.0-macOS-arm64.zip"
echo "🗜️ Packaging $ZIP_NAME..."
ditto -c -k --keepParent "$APP_DIR" "$ROOT_DIR/dist/$ZIP_NAME"

echo ""
echo "✅ Build complete!"
echo "   Application: $APP_DIR"
echo "   Release Zip: $ROOT_DIR/dist/$ZIP_NAME"
