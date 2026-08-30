#!/bin/bash
# 몰입 — 빌드, 번들 조립, 애드혹 서명.
# Xcode 없이 Command Line Tools만으로 동작한다.
set -euo pipefail
cd "$(dirname "$0")"

BUNDLE_ID="local.molip.app"
EXEC="Molip"
APP="build/Molip.app"
TARGET="arm64-apple-macosx14.0"

echo "==> 정리"
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "==> 컴파일"
swiftc -O -parse-as-library \
    -target "$TARGET" \
    -framework Carbon \
    -o "$APP/Contents/MacOS/$EXEC" \
    Sources/*.swift

echo "==> 아이콘"
python3 tools/make_icon.py "$APP/Contents/Resources/AppIcon.icns"

echo "==> Info.plist"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>$EXEC</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleName</key><string>몰입</string>
    <key>CFBundleDisplayName</key><string>몰입</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHumanReadableCopyright</key><string>개인용</string>
</dict>
</plist>
PLIST

echo "==> 서명"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP" && echo "서명 검증 통과"

echo
echo "빌드 완료: $APP"
echo "설치하려면:  ./install.sh"
