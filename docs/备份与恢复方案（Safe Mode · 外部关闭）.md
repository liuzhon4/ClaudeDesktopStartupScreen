# 备份与恢复方案（Safe Mode · 外部关闭）

> 本文是 ClauEd 现行的安全开关、外部关闭与恢复手册。
> 目的：无论 Claude Desktop 未来如何收紧策略，或启动器/开屏本身出任何问题，都能**从 Claude 外部**关掉我们添加的一切，让官方 Claude 照常打开。
> 状态：**现行版（2026-11-14 审计后更新）**。命令已按当前实现（ClauEd + 原生 watcher）逐条核对。

---

## 0. 结论先行（30 秒版恢复卡）

1. **官方 Claude 永远可以直接打开**：Finder 双击 `/Applications/Claude.app`，或终端 `open -b com.anthropic.claudefordesktop`。我们从不修改 Claude 的任何文件，所以这条路不受任何影响。
2. 黑屏卡住：按 `Esc`（内置跳过）；无效就终端 `pkill -f "ClauEd.app/Contents/MacOS/ClauEd"`——Claude 已在后台正常启动，退出启动器即露出。ClauEd 是 `LSUIElement`（无 Dock 图标、无菜单栏），**不会出现在 Cmd+Opt+Esc 的强制退出列表里**，别在那里找它。
3. 永久关闭：双击 `claude-splash-off.command`，它停启动器与监听器、关开机自启、放 DISABLED 标记、清环境变量，并验证 Claude 能打开。

---

## 1. 非侵入契约：启动器永远不会做的事

| # | 约束 | 原因 |
|---|---|---|
| 1 | 从不向 Claude 传任何命令行参数（尤其 `remote-debugging-*`、`--user-data-dir`、`disable-web-security`） | 这些正是当前启动守卫的黑名单 |
| 2 | 从不设置任何会被 Claude 继承的环境变量；不用 `launchctl setenv`、不用 `open --env`、不写 `LSEnvironment` | 守卫会清理/拒绝可疑环境变量（`CLAUDE_USER_DATA_DIR`、`SSLKEYLOGFILE` 已知） |
| 3 | 从不修改 `/Applications/Claude.app` 及其签名、不碰 `~/Library/Application Support/Claude*` 里的任何文件 | 不改包就不触发 asar 完整性、公证、keychain 问题 |
| 4 | 不改 Dock 里的官方 Claude 图标、不注册 `claude://` URL scheme、不做代理/劫持 | 用户始终有官方入口 |
| 5 | 只通过 LaunchServices（`open -b com.anthropic.claudefordesktop`）启动 Claude，不以子进程直接 exec | Claude 的父进程是 launchd；启动器退出/崩溃不带走 Claude |
| 6 | 不读 Claude 会话内容；不注入页面、不用 CDP/AppleScript/辅助功能 | 攻击面最小化 |
| 7 | 不常驻、无网络请求、无辅助功能/屏幕录制权限（可选监听器只读应用启动通知） | 不引入 TCC 依赖 |
| 8 | 只读 Claude 配置里的 `userThemeMode` 一个键，不写回 | 主题解析不污染配置 |

**启动器的全部对外动作只有两个**：读主题偏好（只读）、`open -b com.anthropic.claudefordesktop`（无参数）。其余一切都在自己的进程和窗口里。

---

## 2. 「Claude 进一步收紧」会怎么收紧，我们为什么天然免疫

| 可能的收紧方式 | 对默认方案的影响 | 依据 |
|---|---|---|
| 扩大启动守卫黑名单（更多开关/环境变量） | **无影响**：我们从不传参、不设环境变量 | 当前守卫已拒绝 debugging/network-override 开关 |
| 加强 asar 完整性 / 签名校验 | **无影响**：我们不碰任何官方文件 | 当前已开 ElectronAsarIntegrity，且校验通过 |
| 封禁 CDP/调试端口（已经封了） | **无影响**：混合模式默认关闭；纯 B 不用端口 | 主进程 guard（评估文档 §2） |
| 封禁辅助功能/AppleScript 注入 | **无影响**：默认方案不需要这些权限 | 设计约束 §1-7 |
| 检测「有外部窗口盖屏」 | **无影响（推断）**：应用没有屏幕录制权限，读不到其他进程的窗口内容/标题 | macOS TCC |
| Squirrel 自动更新替换版本 | **无影响**：启动器只调用 `open`，与版本解耦 | 更新机制 |
| Anthropic 条款层面禁止第三方美化 | 与「能否启动」无关；如你选择遵守，执行 §4.2 一键卸载即可 | — |

**唯一两个真正的风险点**，都已在设计中默认关闭：

1. **全局环境变量残留**（`launchctl setenv REACT_PROFILE 1` 之类的旧配方）——这是唯一可能「从外部污染 Claude 启动环境」的通道。本方案明确禁止；若曾经设置过，`claude-splash-off.command` 会一键清除。
2. **混合模式（CDP overlay）**——会触发已知守卫。本项目从未启用；调研文档里的相关命令只是历史存档，**不要照做**（见各文档顶部的警示条）。

---

## 3. 开关层级：从「跳过一次」到「彻底卸载」

| 层级 | 操作 | 效果 | 适用场景 |
|---|---|---|---|
| **L0 跳过本次** | 启动时按住 `Shift`；或开屏中按 `Esc` | 不播/立即结束动画，直接打开 Claude | 赶时间、演示时 |
| **L1 临时停用** | `touch ~/Library/Application\ Support/ClaudeSplash/DISABLED` | 启动器与监听器都直通：只 `open -b …` 并退出（不建窗、不铺黑幕） | 排查期、暂时不想要开屏 |
| **L2 停开机自启** | `launchctl bootout gui/$(id -u)/local.claued.splash`（如果配置过自启） | 登录时不再自动拉起启动器 | 自启造成困扰 |
| **L2' 停启动监听** | 双击 `claude-splash-off.command`，或 `launchctl bootout gui/$(id -u)/local.claued.watch` + `launchctl disable gui/$(id -u)/local.claued.watch` | 点 Claude 不再触发黑幕/开屏 | 想回到裸启动 |
| **L3 一键安全关闭** | 双击 `claude-splash-off.command`（见 §4.1） | L1+L2+L2'+清理环境变量+验证 Claude 可打开 | 日常「关掉美化」 |
| **L4 一键卸载** | 双击 `claude-splash-uninstall.command`（见 §4.2） | 在 L3 基础上删配置、把启动器移到废纸篓 | 彻底不玩了 |
| **L5 完全绕过** | Finder 双击 `/Applications/Claude.app`，或终端 `open -b com.anthropic.claudefordesktop` | 不经过启动器，永远可用 | 任何紧急情况 |

设计上 L1 是**文件系统级开关**：即使启动器坏了、你打不开配置，也能用一个 `touch` 关掉它。监听器启动时也会读这个标记。

> 注意：`launchctl disable` 是**持久**状态（跨重启保留）。重新开启监听请双击 `claude-splash-watch-on.command`——它会先 `enable` 再 `bootstrap` 并验证真的跑起来；手动恢复时顺序也必须是 `enable` → `bootstrap`，反过来 bootstrap 会被 launchd 拒绝（error 119）。

---

## 4. 一键脚本（随项目交付）

### 4.1 `claude-splash-off.command`（安全关闭，保留启动器）

以仓库里的实际脚本为准（本文不内嵌副本，避免再次与实现脱节）。它做五件事：

1. `pkill` 停止 `ClauEd.app/Contents/MacOS/ClauEd` 与 `ClauEdWatcher.app/Contents/MacOS/ClauEdWatcher`；
2. 按 label `local.claued.splash` / `local.claued.watch` bootout + disable，并把两个 LaunchAgent plist 改名备份；
3. `touch ~/Library/Application Support/ClaudeSplash/DISABLED`；
4. 清理 `REACT_PROFILE` / `CLAUDE_CDP_AUTH` / `CLAUDE_USER_DATA_DIR` / `SSLKEYLOGFILE` 四个全局变量；
5. `open -b com.anthropic.claudefordesktop` 并用 `lsappinfo` 按 bundle id 验证 Claude 在运行。

### 4.2 `claude-splash-uninstall.command`（彻底卸载）

在新 shell 里调用 4.1，然后：

- 再次确认 `local.claued.watch` 不在 launchd 里（防止 KeepAlive 对着已删除的路径反复重启）；
- 把仓库目录与 `/Applications` 下的 `ClauEd.app` 一起移入废纸篓；
- 删除 `~/Library/Application Support/ClaudeSplash`。

> 两个脚本都只用用户级命令（无 `sudo`），不触碰 `/Applications/Claude.app` 和 Claude 数据目录。

### 4.3 `claude-splash-watch-on.command`（安装/恢复启动监听）

- 删除 DISABLED 标记（用户主动重开 = 重新启用开屏）；
- 确保配置里 `splashOnActivate: true`；
- 写 LaunchAgent `local.claued.watch`（`ProgramArguments` 指向 `ClauEd.app/Contents/Resources/ClauEdWatcher.app/Contents/MacOS/ClauEdWatcher`，`KeepAlive`）；
- bootout → enable → bootstrap，并用 `launchctl print` + `pgrep` 验证 state=running 才打印成功。

前提：`ClauEd.app` 必须在 `/Applications`（监听器从它内部启动开屏，不复制第二份）。

---

## 5. 故障速查表（症状 → 动作）

| 症状 | 判断 | 动作 |
|---|---|---|
| 全屏黑屏不消失 | 启动器窗口卡住（Claude 已在后台运行） | 先按 `Esc`；无效终端 `pkill -f "ClauEd.app/Contents/MacOS/ClauEd"`；再不行 `pkill -f ClauEdWatcher`（黑幕是监听器铺的） |
| 点 Claude 先黑屏 3 秒再直通 | 监听器在跑但开屏被禁用/失败 | 检查 `~/Library/Logs/ClauEdWatcher.log`；确认没有 `DISABLED` 标记、配置 `enabled=true` |
| 点 Claude 完全没反应（无黑幕无开屏） | 监听器没在跑 | `launchctl print gui/$(id -u)/local.claued.watch`；双击 `claude-splash-watch-on.command` 重装 |
| 启动器双击无反应 | 启动器自身坏了 | 直接用官方 Claude；有空再 `./build.sh` 重编译 |
| 开屏播一半消失、Claude 正常 | 引擎看门狗生效（预期行为） | 无需处理；查 `~/Library/Logs/ClaudeSplash.log` 看原因 |
| 点启动器后 Claude 没起来 | 启动器找不到 Claude | Finder 打开 `/Applications/Claude.app`；检查 `mdfind "kMDItemCFBundleIdentifier == 'com.anthropic.claudefordesktop'"` |
| **Claude 本身打不开** | 先分清是不是我们的问题（见 §6） | 终端直接运行 Claude 二进制看报错；`codesign --verify`；必要时官方重装（数据不丢） |
| 开机自动弹出开屏（不想） | LaunchAgent 在拉起 | `launchctl bootout gui/$(id -u)/local.claued.splash` + `touch DISABLED`（§3 L1/L2） |
| 每次启动都弹、想只看一次 | 配置模式问题 | 配置 `"displayMode": "daily"`，或按 §3 L1 关闭 |
| Dock 里 ClauEd 点击没反应 | ClauEd 被移走/改名 | 重新 `cp -R ClauEd.app /Applications/`；监听器路径写死 `/Applications` |

---

## 6. Claude 打不开时的 60 秒诊断（先证明与我们无关）

```zsh
# 1) Claude 是否在运行（按 bundle id，pgrep -x Claude 在 macOS 上匹配不到）
/usr/bin/lsappinfo info -only bundleID -app "Claude" | grep claudefordesktop || echo "(未运行)"

# 2) 绕过启动器，直接让系统打开 Claude
open -b com.anthropic.claudefordesktop; sleep 3
/usr/bin/lsappinfo info -only bundleID -app "Claude" | grep claudefordesktop && echo "LaunchServices 启动成功"

# 3) 若上面失败，直接运行二进制，让错误打在终端里
/Applications/Claude.app/Contents/MacOS/Claude
# 观察最后几行报错（例如 "refusing to start — a debugging or network-override switch…"）
# 注意：若 Claude 已在运行，这条命令会因单实例而立即退出，属正常

# 4) 检查我们的东西是否还挂着
launchctl print "gui/$(id -u)/local.claued.watch" 2>/dev/null | grep -E "state = |path = "
ps aux | grep -E "ClauEd|ClauEdWatcher" | grep -v grep || echo "启动器与监听器均未运行"
ls "$HOME/Library/Application Support/ClaudeSplash" 2>/dev/null || echo "无配置目录"
for v in REACT_PROFILE CLAUDE_CDP_AUTH CLAUDE_USER_DATA_DIR SSLKEYLOGFILE; do
  val=$(launchctl getenv "$v" 2>/dev/null); [ -n "$val" ] && echo "残留变量: $v=$val"
done

# 5) 官方包完整性（应输出 valid on disk / satisfies its Designated Requirement）
codesign --verify --deep --strict --verbose=2 /Applications/Claude.app
spctl -a -vvv -t exec /Applications/Claude.app

# 6) 最近 5 分钟 Claude 系统日志里有没有启动错误
log show --last 5m --predicate 'process == "Claude"' --style compact 2>/dev/null | tail -40
```

**判读规则**：

- 第 2/3 步能起、只是启动器不行 → **是我们的问题**：按 §3 L1/L3 关闭，Claude 照常。
- 第 3 步的报错里出现 `refusing to start` → 有调试/网络开关被传入了 Claude 的启动参数。我们从不传参数；用 `ps -o command= -p <pid>` 检查是谁启动的、带了什么参数；必要时按 §4.1 清环境变量后重开。
- 第 5 步报 `code object is not signed at all` 或 integrity 错误 → 官方包被改过（**不会是本方案做的**，因为全程只读）。最稳妥：从 claude.com/download 下载同版本重装；`~/Library/Application Support/Claude*` 里的账号数据不受影响（重装后可能需要重新登录）。
- 第 6 步有崩溃栈 → 与美化无关，走官方支持/重装。

---

## 7. 安全埋点（已在代码中实现）

- [x] **Shift 跳过**：启动器与监听器两侧都检查，不建窗、直接 `open -b`、退出。
- [x] **DISABLED 标记**：启动器与监听器启动时都检查 `~/Library/Application Support/ClaudeSplash/DISABLED`，存在即直通。
- [x] **看门狗**：5s 运行探针（eval 失败不误杀）、8s 导航超时、120s 硬截止；页面内 9s/15s 兜底。
- [x] **键盘逃生**：页面 Esc + Swift `NSEvent` 双保险；Swift 侧显式监听 `Cmd+Q`（LSUIElement 无菜单栏）。
- [x] **失败隔离**：导航失败、资源缺失、**WebContent 内容进程崩溃**，一律收窗；Claude 已由 `open` 拉起，不受影响。
- [x] **黑幕兜底**：监听器 3 秒超时收起；屏幕热插拔重建黑幕后重新计时；启动器所有直通出口补发 `splash.done`。
- [x] **日志**：`~/Library/Logs/ClaudeSplash.log` 与 `~/Library/Logs/ClauEdWatcher.log`，只记启动/相位/退出原因，2MB 轮转，不记录 Claude 页面内容。
- [x] **卸载脚本随包交付**：`claude-splash-off.command` / `claude-splash-uninstall.command` 位于仓库根目录。

---

## 8. 每月一次的 3 分钟演练（建议）

1. `touch ~/Library/Application Support/ClaudeSplash/DISABLED`
2. 双击启动器 / 点 Claude → 应立即打开 Claude、**无黑屏**、无开屏
3. 删除标记 → 再启动 → 开屏恢复
4. 双击 `claude-splash-off.command` → 验证 Claude 正常打开
5. 双击 `claude-splash-watch-on.command` → 验证 `launchctl print gui/$(id -u)/local.claued.watch` 显示 state=running

演练通过意味着：任何时候出问题，你都有已验证的退路。
