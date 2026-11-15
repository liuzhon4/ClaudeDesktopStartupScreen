#!/bin/zsh
# 打开 ClauEd 原生设置窗口：只编辑自己的 config.json，不启动 Claude、不播放开屏。
set -u

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/ClauEd.app"

if [ ! -x "$APP/Contents/MacOS/ClauEd" ]; then
  APP="/Applications/ClauEd.app"
fi
if [ ! -x "$APP/Contents/MacOS/ClauEd" ]; then
  echo "❌ 未找到 ClauEd.app。请先运行 ./build.sh，或把它安装到 /Applications。"
  exit 1
fi

exec /usr/bin/open "$APP" --args --settings
