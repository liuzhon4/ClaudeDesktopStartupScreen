#!/bin/zsh
# 制作完整 ad-hoc Release：应用 + 启动/设置脚本 + 许可与首次打开说明。
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-}"
if [[ ! "$VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
  echo "用法：$0 <x.y.z>"
  exit 2
fi

PLIST_VERSION=$(plutil -extract CFBundleShortVersionString raw resources/Info.plist)
if [ "$PLIST_VERSION" != "$VERSION" ]; then
  echo "版本不一致：resources/Info.plist 是 $PLIST_VERSION，参数是 $VERSION"
  exit 2
fi

for f in assets/line-{1,2,3,4,5,6}.mp3 assets/sfx-tick.mp3 assets/sfx-ticks-run.mp3; do
  if [ ! -f "$f" ]; then
    echo "缺少 Release 音频：$f"
    exit 1
  fi
done

./build.sh

ARCH="$(uname -m)"
STAGE="dist/ClauEd-$VERSION"
ZIP="dist/ClauEd-$VERSION-macOS-$ARCH.zip"
rm -rf "$STAGE"
mkdir -p "$STAGE"

cp -R ClauEd.app "$STAGE/"
cp README.md AGENTS.md CHANGELOG.md LICENSE NOTICE "$STAGE/"
mkdir -p "$STAGE/docs" "$STAGE/extras"
cp extras/AppIcon-preview.png "$STAGE/extras/"
cp docs/*.md "$STAGE/docs/"
cp claude-splash-settings.command claude-splash-watch-on.command \
   claude-splash-off.command claude-splash-uninstall.command "$STAGE/"

cat > "$STAGE/FIRST-OPEN.txt" <<'EOF'
ClauEd 首次打开
==============

1. 把 ClauEd.app 拖入“应用程序”(/Applications)。
2. 当前版本是 ad-hoc 签名，未经 Apple Developer ID 公证。
   首次请在 Finder 中右键 ClauEd.app →“打开”→ 再点“打开”。
3. 以后双击 ClauEd 即可播放开屏并进入官方 Claude。

设置：双击 claude-splash-settings.command，或按住 Option 启动 ClauEd。
Dock 只保留官方 Claude：运行 claude-splash-watch-on.command。
安全关闭：运行 claude-splash-off.command。
卸载：运行 claude-splash-uninstall.command。

本项目是非官方独立作品，与 Anthropic 无隶属或背书关系。
EOF

codesign --verify --deep --strict "$STAGE/ClauEd.app"
if find "$STAGE" -name '.DS_Store' -o -name '*.mov' -o -name 'settings.local.json' | grep -q .; then
  echo "Release 中包含不应发布的本地文件"
  exit 1
fi

rm -f "$ZIP" "$ZIP.sha256"
ditto -c -k --norsrc "$STAGE" "$ZIP"
if unzip -Z1 "$ZIP" | grep -E '(^|/)__MACOSX/|\.DS_Store$' >/dev/null; then
  echo "Release ZIP 中包含 macOS 元数据杂项"
  exit 1
fi
(
  cd "$(dirname "$ZIP")"
  shasum -a 256 "$(basename "$ZIP")" > "$(basename "$ZIP").sha256"
)

echo "✅ Release: $ZIP"
echo "✅ SHA-256: $ZIP.sha256"
echo "⚠️  ad-hoc / $ARCH / 未经 Apple 公证；首次打开说明已放入包内。"
