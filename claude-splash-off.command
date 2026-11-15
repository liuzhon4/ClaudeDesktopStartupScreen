#!/bin/zsh
# ClauEd 安全关闭：停启动器与监听器、关自启、放 DISABLED 标记、清环境变量、验证 Claude。
# 只动我们自己的东西；绝不触碰 /Applications/Claude.app 或 Claude 数据目录。
set -u

APP_PROC="ClauEd.app/Contents/MacOS/ClauEd"
WATCH_PROC="ClauEdWatcher.app/Contents/MacOS/ClauEdWatcher"
CFG_DIR="$HOME/Library/Application Support/ClaudeSplash"
PLIST="$HOME/Library/LaunchAgents/local.claued.splash.plist"
WATCH_PLIST="$HOME/Library/LaunchAgents/local.claued.watch.plist"
BUNDLE_ID="com.anthropic.claudefordesktop"

echo "== 1/5 停止启动器与监听器 =="
pkill -f "$APP_PROC" 2>/dev/null && echo "已退出启动器" || echo "启动器未在运行"
pkill -f "$WATCH_PROC" 2>/dev/null && echo "已退出启动监听器" || echo "监听器未在运行"

echo "== 2/5 关闭并移除开机自启 / 启动监听 =="
# 按 label 停止（运行中的服务）+ 按 plist 路径停止（已加载但未跑的服务兜底）
for svc in local.claued.splash local.claued.watch; do
  launchctl bootout "gui/$(id -u)/$svc" 2>/dev/null
done
launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null
launchctl bootout "gui/$(id -u)" "$WATCH_PLIST" 2>/dev/null
# disable 是持久状态：防止登录时 launchd 重新加载；claude-splash-watch-on.command 会先 enable
launchctl disable "gui/$(id -u)/local.claued.splash" 2>/dev/null
launchctl disable "gui/$(id -u)/local.claued.watch" 2>/dev/null
if [ -f "$PLIST" ]; then
  mv "$PLIST" "$PLIST.disabled.$(date +%Y%m%d%H%M%S)"
  echo "LaunchAgent 已停用并备份"
else
  echo "未发现 LaunchAgent（可能从未配置）"
fi
if [ -f "$WATCH_PLIST" ]; then
  mv "$WATCH_PLIST" "$WATCH_PLIST.disabled.$(date +%Y%m%d%H%M%S)"
  echo "Claude 启动监听已停用并备份"
fi
rm -f "$CFG_DIR/watch-claude-running" "$CFG_DIR/watch-claude-initialized"

echo "== 3/5 写入 DISABLED 标记（文件级开关）=="
mkdir -p "$CFG_DIR"
touch "$CFG_DIR/DISABLED"
echo "已创建 $CFG_DIR/DISABLED"

echo "== 4/5 清理可能污染 Claude 启动环境的全局变量 =="
for v in REACT_PROFILE CLAUDE_CDP_AUTH CLAUDE_USER_DATA_DIR SSLKEYLOGFILE; do
  if [ -n "$(launchctl getenv "$v" 2>/dev/null)" ]; then
    launchctl unsetenv "$v" 2>/dev/null && echo "已清除 $v"
  fi
done
echo "完成（无输出即表示本来就没有残留）"

echo "== 5/5 验证 Claude 可正常打开 =="
if ! open -b "$BUNDLE_ID" 2>/dev/null; then
  echo "⚠️  open -b $BUNDLE_ID 失败。请从 Finder 直接打开 /Applications/Claude.app；"
fi
sleep 3
# pgrep -x 匹配不到 Claude：macOS 上 Claude 的 comm 是完整可执行路径，不是 "Claude"。
# 用 LaunchServices 的 bundle id 判断更可靠。
if /usr/bin/lsappinfo info -only bundleID -app "Claude" 2>/dev/null | grep -q "bundleID=\"$BUNDLE_ID\""; then
  echo "✅ Claude 正在运行"
else
  echo "⚠️ 未检测到 Claude 进程。请从 Finder 直接打开 /Applications/Claude.app；"
  echo "   若仍失败，按《备份与恢复方案》§6 的诊断流程排查（先确认与美化无关）。"
fi
