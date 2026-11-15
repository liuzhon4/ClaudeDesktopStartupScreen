# AGENTS

给在本仓库工作的编码代理（以及未来的自己）的项目说明书。**先读这一页再动手。**

## 项目是什么

ClauEd —— 一个 macOS 外挂启动器，把 `dsh-startup-screen` 的六幕开屏动画移植到 Claude Desktop 的启动流程里：

- 语言/技术：Swift（AppKit + WKWebView）+ 原生 HTML/CSS/JS（无构建器、无 npm 依赖）
- 产物：`ClauEd.app`（ad-hoc 签名，本地运行）
- 运行环境：macOS 13+，Claude Desktop `com.anthropic.claudefordesktop`

## 硬性不变量（违反即回滚）

这些是实现的安全边界，任何改动都不得破坏：

1. **不修改官方 Claude**：`/Applications/Claude.app`、其签名、`~/Library/Application Support/Claude*`、`~/.claude` 一律只读。允许读取的只有两类：两个 `config.json` 里的 `userThemeMode`；以及 `Claude*/claude-code-sessions/**/local_*.json` 中的 `model` / `effort` / `lastFocusedAt` / `isArchived`（用于身份卡显示运行模型）。**不得读取 `title` 或任何会话内容。**
2. **不向 Claude 传参数**：只用 `open -b com.anthropic.claudefordesktop`，绝不出现 `--remote-debugging-port`、`--user-data-dir`、`--inspect` 等开关。
3. **不设全局环境变量**：禁止 `launchctl setenv`、`LSEnvironment`、`open --env`。`REACT_PROFILE` / `CLAUDE_CDP_AUTH` / `CLAUDE_USER_DATA_DIR` / `SSLKEYLOGFILE` 都可能污染 Claude 启动环境；`claude-splash-off.command` 会清理它们。
4. **不以子进程持有 Claude**：Claude 由 LaunchServices 启动；启动器退出/崩溃不得影响 Claude。
5. **不联网、不读会话内容、不注入**：CDP/AppleScript/辅助功能全部不用。
6. **失败只关自己的窗口**：任何异常路径都必须收窗退出，Claude 照常可用。WKNavigationDelegate 必须实现 `webViewWebContentProcessDidTerminate`（不实现会被 WebKit 自动 reload，崩溃即整段重播）。
7. **安全开关必须保留**：Shift 跳过、`DISABLED` 标记、5s 运行探针 / 8s 导航超时 / 120s 硬截止、Esc/Cmd+Q、`done` 事件 + finished 轮询双保险。探针 eval 报错不得视为“没跑起来”。
8. **素材许可边界**：维护者已确认当前 `assets/*.mp3` / `extras/*.mp3` 具有公开再分发权；它们不随代码套用 MIT，来源与授权见 `NOTICE`。新增素材必须先确认再分发权，不得重新引入仅限个人使用的音频或官方图标。

## 构建与验证

```bash
./build.sh                                            # 生成 ClauEd.app（会重新生成 fork/assets.js；-target $(uname -m)-apple-macos13.0）
./tools/verify.sh                                     # 一键自检：构建 + minos + 离屏探针 + 配置/文档一致性（= make check）
./tools/package-release.sh 1.1.0                       # 完整 ad-hoc Release（版本必须与 Info.plist 一致）
swift tools/wk_probe.swift fork/splash.html           # 离屏 WKWebView 冒烟（不弹窗）
python3 -m http.server 8765 --bind 127.0.0.1          # 浏览器预览 fork/splash.html?theme=dark&speed=2&voice=0&sound=0
```

真机验证（会全屏播放，需先退出 Claude）：

1. `open ClauEd.app`
2. 看 `~/Library/Logs/ClaudeSplash.log`：应出现 `show theme=…` → `didFinish config: …` → `finished poll … -> fade` → 进程退出
3. `splashOnActivate: false` 且 Claude 已运行时点启动器：应出现 `Claude already running -> activate & exit`，无窗口；默认 `true` 时则会正常播放开屏再激活

## 代码地图与修改约定

| 位置 | 约定 |
|---|---|
| `fork/splash.js` | 对上游 `dsh-startup-screen/lib/splash.js` 的**最小 diff** fork。保持 `#dsh-startup-root` 作用域；不得重新引入 DeepSeek 品牌（鲸鱼路径、`DEEPSEEK`、`深度求索`）。星芒是 stroke：`assembleLogo()` 里**不能**把 `strokeWidth` 归零（否则星芒画完消失）。`finish()` 里的收尾定时器必须存入 `doneTimer` 并在 `dispose()` 清除；所有 `setTimeout`/wait 都必须可通过 `releaseAll()`/`dispose()` 取消；`finished` 之后 `ac()` 返回 null（跳过时不得补播音效）。 |
| `fork/splash.css` | 同上；所有选择器留在 `#dsh-startup-root` / `.dsu-*` 下；不得引入远程资源或 webfont；暗色通过 `.dsu-dark` token 覆写。**通用重置必须用 `:where(#dsh-startup-root) *`**（(1,0,0) 的 ID 选择器会压掉所有组件的 margin/padding）；装饰层（进度条/声纹/页脚/四角/扫描线/黑幕）必须 `pointer-events: none`，只有按钮和 SKIP 接收点击。 |
| 品牌字段 | **两处同步**：`fork/splash.js` 的 `DEFAULTS` 与 `fork/splash.html` 的 `__CLAUDE_DEFAULT_CFG__`；Swift 注入（`src/main.swift`）优先级最高。当前品牌：黑幕 `CLAUDE / ANTHROPIC / CLAUDE DESKTOP`，品牌块两行 `CLAUDE / ANTHROPIC`（`brand3*` 留空自动隐藏）。 |
| 音频 | 引擎经 `window.__CLAUDE_SPLASH_AUDIO__`（base64）读取；`tools/embed_audio.py` 生成。不要改回 `fetch('/dsh-startup/asset/...')` 绝对路径（`file://` 下必失败）。引擎的 `fetch` 分支只作 HTTP 预览兜底。 |
| 事件 | 引擎在 **`window`** 上派发 `dsh-startup:done`（不是 `document`）。桥接与 Swift 轮询都以此为准；改动 `finish()` 时保留该事件。 |
| `src/main.swift` | 主题解析顺序：`themeOverride` → Claude `userThemeMode` → 系统外观。`identityId: "auto"/"date"` → 当天日期（本地时区 `yyyyMMdd`）；`accessLevel: "auto"` → 最近 Code 会话的 `model`/`effort`（读不到回退 `PRO`）；这三个身份字段为空字符串时隐藏对应内容。只读会话元数据的四个字段，不读会话内容。注入用 `JSONSerialization` 输出完整配置对象（新增 JS 配置键无需逐字段改 Swift），并转义 U+2028/U+2029；`WKUserScript` 保持 `forMainFrameOnly: true`。`--settings` 或 Option 启动进入原生设置窗口，不开 Claude、不播开屏。启动时按 bundle id 做单实例检查；**所有不播放开屏的直通出口都要调用 `postSplashDone()`** 后再退出（否则 watcher 黑幕只能等 3 秒超时）；`fadeOut()` 里兜底调用幂等的 `openClaude()`；日志 2MB 轮转。 |
| `src/settings.swift` | 原生 AppKit 设置窗口；`build.sh` 与 `main.swift` 一起编译。保存时更新自己的 `config.json`、保留未知键并原子写入；关闭窗口即退出，不触发 `openClaude()`。入口脚本 `claude-splash-settings.command`。 |
| `resources/AppIcon.svg` / `AppIcon.icns` | 原创「C 形窗口 + 启动条」；SVG 是母版，ICNS 含完整 16–1024px 尺寸。不得换回官方 Claude 图标或星芒素材。 |
| `resources/Info.plist` | `LSUIElement=true`、`CFBundleDisplayName=ClauEd`、`CFBundleIconFile=AppIcon`、`CFBundleIdentifier=local.claued.splash`。 |
| 脚本 | `claude-splash-off.command` / `claude-splash-uninstall.command` 的进程匹配路径必须与 `ClauEd.app/Contents/MacOS/ClauEd` 一致。 |
| 启动监听 | `src/watcher.swift` 编译为 `ClauEd.app/Contents/Resources/ClauEdWatcher.app`（独立 bundle id `local.claued.watcher`，LSUIElement）。LaunchAgent `local.claued.watch` 事件驱动：Claude 冷启动时铺黑幕 → 拉起 ClauEd；`src/main.swift` 在窗口就绪/结束时发 `local.claued.splash.visible` / `.done` 通知，watcher 收到后收黑幕；所有直通出口也必须发 `.done`（否则黑幕只能等 3 秒超时）。`claude-splash-watch-on.command` 必须按 bootout → enable → bootstrap 顺序（off 会持久 disable 该 label），并删除 DISABLED 标记后重启。`tools/watch-claude.sh` 是旧版 shell 轮询，仅作 legacy 参考。`ClauEd.app` 必须留在 `/Applications`。 |

## 文档维护

- 改了配置字段 → 同步 `README.md` 的配置表、`extras/config.example.json`、`src/main.swift` 默认值；需要图形化编辑时同步 `src/settings.swift`。
- 改了品牌/文案 → 同步 README 的现行说明。
- 换了构建产物名 → README、AGENTS、CLAUDE.md、两个 `.command` 脚本、`备份与恢复方案`。
- 改了监听器 / 直通出口 / 黑幕行为 → 同步 README「Claude 启动监听」小节与 `备份与恢复方案` §3、§5、§7。
- 新增验证 → 更新 README「验证记录」与下列文档的状态。
- 新增/搬迁文件 → 更新 README「目录结构」与 AGENTS 代码地图；**文档一律放 `docs/`，构建输入（plist / 图标）放 `resources/`**，根目录只留用户可直接双击的入口（`build.sh`、`.command`）。

## 文档索引

- [README.md](README.md) — 用户手册
- [备份与恢复方案（Safe Mode · 外部关闭）.md](docs/备份与恢复方案（Safe%20Mode%20·%20外部关闭）.md) — 5 级开关与诊断
- [Claude Desktop 美化方案调研.md](docs/Claude%20Desktop%20美化方案调研.md) — 最初的宏观调研（历史存档，CDP 路线已封死）

原始调研报告仅保存在维护者本机，不进入公开仓库；公开文档不得链接到该目录。

## 禁止事项

- 不要为了让 CDP/注入工作而去改 guard、改 asar、重签官方包。
- 不要把开屏做成常驻代理或网络服务。
- 不要在仓库里提交 `ClauEd.app/`、`fork/assets.js`、`.DS_Store`（见 `.gitignore`）。
- 不要公开分发未获再分发授权的音频或 Claude 官方图标；当前音频授权范围见 `NOTICE`。
