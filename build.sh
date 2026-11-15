#!/bin/zsh
# 构建 ClauEd.app（ad-hoc 签名，本地运行）
set -euo pipefail
cd "$(dirname "$0")"

APP="ClauEd.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "== embed audio =="
python3 tools/embed_audio.py assets fork/assets.js

echo "== compile swift =="
# 显式声明部署目标：不指定时产物 minos 会跟着构建机的系统版本走，
# 和 Info.plist 里的 LSMinimumSystemVersion 13.0 对不上
ARCH="$(uname -m)"
TARGET="$ARCH-apple-macos13.0"
swiftc -O -target "$TARGET" src/main.swift src/settings.swift -o "$APP/Contents/MacOS/ClauEd" -framework Cocoa -framework WebKit
WATCHER_APP="$APP/Contents/Resources/ClauEdWatcher.app"
mkdir -p "$WATCHER_APP/Contents/MacOS"
swiftc -O -target "$TARGET" src/watcher.swift -o "$WATCHER_APP/Contents/MacOS/ClauEdWatcher" -framework Cocoa
cp resources/watcher-Info.plist "$WATCHER_APP/Contents/Info.plist"

echo "== copy resources =="
cp fork/splash.html "$APP/Contents/Resources/"
cp fork/splash.css  "$APP/Contents/Resources/"
cp fork/splash.js   "$APP/Contents/Resources/"
cp fork/assets.js   "$APP/Contents/Resources/"
cp resources/AppIcon.icns "$APP/Contents/Resources/"
cp resources/Info.plist   "$APP/Contents/Info.plist"

echo "== sign (ad-hoc) =="
codesign --force --sign - "$WATCHER_APP"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"

echo "✅ built: $(pwd)/$APP"
echo "   首次运行：open \"$APP\"（默认 splashOnActivate=true：Claude 已运行也会先播开屏再激活）"
