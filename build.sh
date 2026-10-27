#!/bin/bash
# Сборка PinFit.app без Xcode: swiftc + ручная сборка бандла + ad-hoc подпись.
set -euo pipefail
cd "$(dirname "$0")"

APP="dist/PinFit.app"
rm -rf build "$APP"
mkdir -p build "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "→ компиляция"
swiftc -O -parse-as-library Sources/*.swift -o "$APP/Contents/MacOS/PinFit"

echo "→ ресурсы (Real-ESRGAN)"
./scripts/fetch-realesrgan.sh
cp -R Resources/realesrgan "$APP/Contents/Resources/realesrgan"

echo "→ иконка"
swiftc tools/make_icon.swift -o build/make_icon
build/make_icon build/icon_1024.png
ICONSET=build/AppIcon.iconset
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
    sips -z $s $s build/icon_1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s * 2)) $((s * 2)) build/icon_1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>PinFit</string>
    <key>CFBundleDisplayName</key><string>PinFit</string>
    <key>CFBundleIdentifier</key><string>local.pinfit</string>
    <key>CFBundleExecutable</key><string>PinFit</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP"
echo "✔ $APP"
ditto -c -k --keepParent "$APP" dist/PinFit.zip
