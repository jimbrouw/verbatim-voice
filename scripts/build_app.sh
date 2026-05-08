#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Verbatim"
APP_DIR="$ROOT_DIR/dist/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

cd "$ROOT_DIR"

swift build -c release

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR/bin"

cp "$ROOT_DIR/.build/release/Verbatim" "$MACOS_DIR/Verbatim"
chmod +x "$MACOS_DIR/Verbatim"

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>Verbatim</string>
  <key>CFBundleIconFile</key>
  <string>Verbatim</string>
  <key>CFBundleIdentifier</key>
  <string>app.verbatim.voice</string>
  <key>CFBundleName</key>
  <string>Verbatim</string>
  <key>CFBundleDisplayName</key>
  <string>Verbatim</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSMicrophoneUsageDescription</key>
  <string>Verbatim needs access to your microphone to transcribe your voice into text.</string>
</dict>
</plist>
PLIST

cp "$ROOT_DIR/mlx_server.py" "$RESOURCES_DIR/mlx_server.py"
cp "$ROOT_DIR/requirements.txt" "$RESOURCES_DIR/requirements.txt"
cp "$ROOT_DIR/assets/generated/Verbatim.icns" "$RESOURCES_DIR/Verbatim.icns"

if [[ -x "$ROOT_DIR/.build/helper-dist/VerbatimMLXHelper" ]]; then
  cp "$ROOT_DIR/.build/helper-dist/VerbatimMLXHelper" "$RESOURCES_DIR/VerbatimMLXHelper"
  chmod +x "$RESOURCES_DIR/VerbatimMLXHelper"
elif [[ -d "$ROOT_DIR/venv" ]]; then
  rsync -a --delete \
    --exclude '__pycache__' \
    --exclude '*.pyc' \
    "$ROOT_DIR/venv" "$RESOURCES_DIR/"
else
  echo "No helper executable or venv found. Run scripts/setup_dev.sh first."
  exit 1
fi

if command -v ffmpeg >/dev/null 2>&1; then
  cp "$(command -v ffmpeg)" "$RESOURCES_DIR/bin/ffmpeg"
  chmod +x "$RESOURCES_DIR/bin/ffmpeg"
fi

codesign --force --deep --sign - "$APP_DIR"

echo "Built $APP_DIR"
echo "Note: this local bundle uses the current helper packaging. For wider sharing, prefer a signed/notarized build with a standalone helper executable."
