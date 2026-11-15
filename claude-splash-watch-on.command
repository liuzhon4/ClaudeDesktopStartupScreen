#!/bin/zsh
# 安装 Claude 冷启动监听（原生 watcher）：
# Claude 启动时立刻铺黑幕，再拉起 ClauEd 开屏。
# 只写自己的 LaunchAgent 与配置；不修改 Claude、不改 Dock。
set -u

ROOT="$(cd "$(dirname "$0")" && pwd)"
DIR="$HOME/Library/Application Support/ClaudeSplash"
PLIST="$HOME/Library/LaunchAgents/local.claued.watch.plist"
APP="/Applications/ClauEd.app"
WATCHER="$APP/Contents/Resources/ClauEdWatcher.app/Contents/MacOS/ClauEdWatcher"

mkdir -p "$DIR" "$HOME/Library/LaunchAgents"

# off 脚本会写入 DISABLED 标记；用户主动重开监听 = 重新启用开屏
rm -f "$DIR/DISABLED"

if [ -f "$DIR/config.json" ]; then
  if /usr/bin/xcode-select -p >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
    /usr/bin/env python3 - "$DIR/config.json" <<'PY'
import json, sys
p = sys.argv[1]
try:
    with open(p) as f:
        cfg = json.load(f)
except Exception as e:
    print("无法解析 config.json：%s" % e)
    sys.exit(1)
cfg["splashOnActivate"] = True
with open(p, "w") as f:
    json.dump(cfg, f, ensure_ascii=False, indent=2)
    f.write("\n")
PY
    if [ $? -ne 0 ]; then
      echo "⚠️  config.json 未能更新（splashOnActivate 保持原值）"
    fi
  else
    echo "⚠️  未找到可用的 python3（需要 Xcode 命令行工具），跳过 config.json 更新。"
    echo "    默认值已是 splashOnActivate=true；若你手动改过它，请自行改回 true。"
  fi
fi

# 清理旧版 shell 监听留下的文件
rm -f "$DIR/watch-claude.sh" "$DIR/watch-claude-running" "$DIR/watch-claude-initialized"

if [ ! -x "$WATCHER" ]; then
  echo "❌ 未找到 $WATCHER"
  echo "   请先运行 ./build.sh 并把 ClauEd.app 放进 /Applications。"
  exit 1
fi

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>local.claued.watch</string>
    <key>ProgramArguments</key>
    <array>
        <string>$WATCHER</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>ProcessType</key>
    <string>Interactive</string>
</dict>
</plist>
EOF

# 顺序很重要：off 脚本会 launchctl disable 这个 label（该状态是持久的），
# 处于 disabled 的服务 bootstrap 会被 launchd 拒绝（error 119）。
# 必须先 bootout → enable → bootstrap，最后用 launchctl print 验证真的跑起来了。
launchctl bootout "gui/$(id -u)/local.claued.watch" 2>/dev/null
launchctl enable "gui/$(id -u)/local.claued.watch" 2>/dev/null
if ! launchctl bootstrap "gui/$(id -u)" "$PLIST" 2>/dev/null; then
  # 某些系统上 enable 后仍需再 bootstrap 一次
  launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null
  launchctl bootstrap "gui/$(id -u)" "$PLIST" 2>/dev/null
fi

sleep 0.8
if launchctl print "gui/$(id -u)/local.claued.watch" 2>/dev/null | grep -q "state = running" \
   && pgrep -f "$WATCHER" >/dev/null 2>&1; then
  echo "✅ 原生监听器已安装并运行：local.claued.watch"
else
  echo "❌ 监听器未能启动。请执行下面的命令查看原因："
  echo "   launchctl print gui/$(id -u)/local.claued.watch"
  echo "   常见原因：macOS 隐私/安全设置拦截、或 ClauEd.app 不在 /Applications。"
  exit 1
fi

echo "   日志：~/Library/Logs/ClauEdWatcher.log"
echo ""
echo "接下来："
echo "  1. 在 Dock 里右键 ClauEd（若固定过）→ 选项 → 从 Dock 中移除；文件要留在 /Applications"
echo "  2. 退出 Claude，再从 Dock 点 Claude"
echo "  3. 黑幕会立刻出现，开屏随后接上"
echo ""
echo "关闭监听：双击 claude-splash-off.command"
