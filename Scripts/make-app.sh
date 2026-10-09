#!/bin/bash
# Pakuje binarkę Swift do pełnego pakietu .app (niezbędne dla paska menu).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT/.build/SDCardOrganizer.app"
CONTENTS="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS/MacOS"

echo "Budowanie..."
swift build -c release

echo "Tworzenie pakietu .app..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$CONTENTS/Resources"

cp "$ROOT/.build/release/SDCardOrganizer" "$MACOS_DIR/SDCardOrganizer"

cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>SD Card Organizer</string>
    <key>CFBundleDisplayName</key>
    <string>SD Card Organizer</string>
    <key>CFBundleIdentifier</key>
    <string>com.hiapps.sdcardorganizer</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>SDCardOrganizer</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

# Podpis ad hoc, aby system zezwolił na uruchomienie lokalnej binarki.
codesign --force --deep --sign - "$APP_DIR" 2>/dev/null || echo "Ostrzeżenie: nie udało się podpisać (codesign)."

echo "Gotowe: $APP_DIR"
echo "Uruchomienie: open $APP_DIR"
