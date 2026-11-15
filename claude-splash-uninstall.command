#!/bin/zsh
# ClauEd 卸载：在 off 的基础上删配置、把启动器移入废纸篓。
# 官方 Claude 未受任何影响。
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
"$SCRIPT_DIR/claude-splash-off.command"

echo "== 6/6 移除启动器与配置 =="
APP="$SCRIPT_DIR/ClauEd.app"
INSTALLED_APP="/Applications/ClauEd.app"
CFG_DIR="$HOME/Library/Application Support/ClaudeSplash"

# off 已 bootout；这里再确认一次，防止 KeepAlive 对着将被删除的路径反复重启
if launchctl print "gui/$(id -u)/local.claued.watch" >/dev/null 2>&1; then
  launchctl bootout "gui/$(id -u)/local.claued.watch" 2>/dev/null
  pkill -f "ClauEdWatcher.app/Contents/MacOS/ClauEdWatcher" 2>/dev/null
  echo "监听器进程已彻底停止"
fi

for A in "$APP" "$INSTALLED_APP"; do
  if [ -d "$A" ]; then
    mv "$A" "$HOME/.Trash/" && echo "已移入废纸篓：$A"
  fi
done
rm -rf "$CFG_DIR" && echo "配置目录已删除（含 DISABLED 标记与启动监听脚本）"
echo "完成。官方 Claude 不受影响。"
