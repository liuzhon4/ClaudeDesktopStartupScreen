#!/bin/zsh
# LEGACY：旧版 shell 轮询监听，已被 src/watcher.swift 的原生 NSWorkspace watcher 取代。
# 保留仅作参考 / 调试，安装器不再使用它。
#
# Claude 冷启动监听：Claude 从「未运行」变为「运行」时，拉起一次开屏。
# 由 LaunchAgent local.claued.watch 以 --loop 常驻调用；也可手动单次运行。
#
# 测试开关：
#   CLAUDED_WATCH_PROC=sleep       用进程名匹配（干跑测试）
#   CLAUDED_WATCH_APP=/path/app    改要拉起的 app
#   CLAUDED_WATCH_DRY=1            只打印，不真正 open
set -u

DIR="$HOME/Library/Application Support/ClaudeSplash"
PROC="${CLAUDED_WATCH_PROC:-}"
BUNDLE="${CLAUDED_WATCH_BUNDLE:-com.anthropic.claudefordesktop}"
APP="${CLAUDED_WATCH_APP:-/Applications/ClauEd.app}"
DRY="${CLAUDED_WATCH_DRY:-0}"
STATE="$DIR/watch-claude-running"
INIT="$DIR/watch-claude-initialized"

mkdir -p "$DIR"

check_once() {
  local running=0
  if [ -n "$PROC" ]; then
    pgrep -x "$PROC" >/dev/null 2>&1 && running=1
  else
    # 按 bundle id 判断，避开进程名在不同 macOS 版本上的差异；
    # info 比 list 轻，不会每秒遍历所有应用。
    /usr/bin/lsappinfo info -only bundleID -app "Claude" 2>/dev/null \
      | grep -q "bundleID=\"$BUNDLE\"" && running=1
  fi

  # 第一次运行（安装或登录后）：只记录当前状态，不触发开屏，
  # 避免安装时 Claude 正在运行就立刻弹一次。
  if [ ! -f "$INIT" ]; then
    touch "$INIT"
    [ "$running" = 1 ] && touch "$STATE"
    return 0
  fi

  if [ "$running" = 1 ]; then
    if [ ! -f "$STATE" ]; then
      touch "$STATE"
      if [ "$DRY" = 1 ]; then
        echo "would open $APP"
      else
        open -a "$APP"
      fi
    fi
  else
    rm -f "$STATE"
  fi
}

if [ "${1:-}" = "--loop" ]; then
  while true; do
    check_once
    sleep 1
  done
else
  check_once
fi
