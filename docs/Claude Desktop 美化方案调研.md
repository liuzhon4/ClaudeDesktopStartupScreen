# Claude Desktop for Mac 美化方案调研：开屏动画 + 整体主题

> ⚠️ **历史存档（2026-11-14 审计后加注）**：本文写于实现之前，其中的 CDP / `--remote-debugging-*` / `launchctl setenv` / `open --env` 类命令已被项目硬约束**禁止**（见 [AGENTS.md](../AGENTS.md)），**不要照着执行**。现行实现对 Claude 只用 `open -b com.anthropic.claudefordesktop`（不传参数、不设环境变量）。当前可用的关闭/恢复命令见 [备份与恢复方案（Safe Mode · 外部关闭）.md](备份与恢复方案（Safe%20Mode%20·%20外部关闭）.md)。

> 面向 gateway（3P）模式 · 调研时间 2026-11 · 全部为非官方方案，涉及修改客户端的行为请自行评估账号与条款风险。

> **2026-11-13 更新**：本文推荐的 CDP 注入（Theme Agent）路线在当前 Claude Desktop 5.11492.2 上已被主进程启动守卫封死（`--remote-debugging-port` 会直接 exit 1）。最终落地方案见《Claude Desktop 开屏移植评估.md》《开屏方案 v2（暗色自适应 · 音频复用 · 豪叔）.md》与 `ClauEd.app`。本文保留为调研存档。

## 0. 结论先行

你用的是 gateway 模式，这一点会改变方案选择。Claude Desktop 的 3P（third-party inference）模式主窗口加载的是随包内置的本地 Web 应用（`ion-dist`，通过 `app://` 协议提供），而不是登录版的 `https://claude.ai`。因此：

- 现成的 Claude Styled、claude-desktop-themes 主要是按 1P 登录版设计的，不能保证在 3P 模式生效；但它们的 CSS 选择器和主题资源可以复用。
- 真要“点开图标先看一段漂亮开屏”，最稳妥的是**外挂启动器**：不改官方包、不受 1P/3P 影响、Claude 更新也不会失效。
- 主题最稳妥的是 **CDP 注入**：启动时带 `--remote-debugging-port`，把 CSS 注入当前页面；对 `app://localhost` 和 `https://claude.ai` 都有效，同样不改官方包。
- 深度改包（`ion-dist.asar` / `app.asar`）在 3P 模式下反而更有意义，因为 UI 是本地的；但 Claude 开了 asar 完整性校验、签名和公证，改完要同步哈希、补 Framework 摘要、ad-hoc 重签，且每次更新重做。除非你愿意长期维护一个 patcher，否则不作为首选。

推荐组合：**Claude Splash 启动器（开屏）+ Theme Agent（CDP 注入主题）**。这套组合在 gateway 模式下可用，且官方 App 升级不会被覆盖。

---

## 1. DeepSeek Harness 的开屏为什么好看

DeepSeek Harness（DSH）的开屏不是官方功能，而是一个相当活跃的社区插件生态。它们的效果之所以“高级”，不是用了多复杂的技术，而是把几个细节做对了。

### 1.1 生态里有哪些做法

| 项目 | 机制 | 时长/特点 |
| --- | --- | --- |
| `dsh-startup-animation` | `shell.overlay` 覆盖层，纯客户端 | 约 3s；鲸鱼点亮 → 人物淡入 → 扫描线 → 环形光轨 → 横幅 → 字标由模糊转清晰 → HARNESS → 淡出；点按/Esc 跳过；支持 localStorage 换视频/图片 |
| `dsh-rsa` | Electron 主进程在**主窗口出现前**创建 splash 窗口 | 可配置窗口、圆角、主题、Logo、文字、光球、进度环；通过改写 `app.asar` 实现“真·启动画面” |
| `dsh-splash-fish` | 离线渲染的 2.5D 视差 WebM，`webserver/index-inject` 在 HTML 解析阶段铺封面 | 5.07s；深度图驱动发丝位移；视频内联；`pointer-events: none` |
| `dsh-opening-splash` | iframe 全屏开场 | 约 20s；Esc/双击跳过；可上传自定义动画 |
| `dsh-first-paint` | 注入黑色首帧 | 消除启动白闪，让后面的动画接得上 |
| `dsh-splash-launcher` | Windows WebView2 包装器 | SVG `stroke-dashoffset` 逐笔绘制鲸鱼 + 逐字描出 HARNESS |
| `dsh-companion` | 插件合集 | 启动动画 + 桌宠 + 皮肤管理 |

### 1.2 可以复用的五个设计套路

第一，**先铺黑**。几乎所有项目都会在动画前压一层与启动页同色的底，避免 Electron 的白闪。`dsh-first-paint` 就是专门干这个的。

第二，**3 秒左右**。`dsh-startup-animation` 约 3s，`dsh-splash-fish` 5s，`dsh-opening-splash` 20s 属于“电影版”。日常工具的开屏，2.5–3.5s 是甜点区；再长就会烦。

第三，**一个主视觉 + 一条时间轴**。鲸鱼点亮 → 人物 → 扫描线 → 光环 → 字标，所有效果都围绕同一个主体，不是满屏粒子乱飞。

第四，**可跳过**。点任意处、Esc、滚动，都会立刻进入收尾。跳过的那一下点击会被吃掉，不会漏到下面的界面。

第五，**尊重 reduced motion**。动画只使用 opacity/transform，`prefers-reduced-motion` 时直接显示静态画面。

这些套路用 HTML/CSS/SVG 就能复刻，不需要视频，也不需要复杂的渲染管线。文末附了一个可以直接打开预览的 Claude 风格 demo。

---

## 2. Claude Desktop 的真实结构（决定方案边界）

### 2.1 它就是一个标准 Electron 应用

2026-07 的一份公开 teardown 显示，Claude Desktop 是 stock Electron 42.5.1 / Chromium 148，`CFBundleIdentifier` 为 `com.anthropic.claudefordesktop`，Developer ID 签名 + 公证 + hardened runtime。它的结构比一般 Electron 应用多两层：

- `app.asar` 里是主进程、preload、少量本地壳层页面；
- 主产品 UI 在 1P 模式下通过 `WebContentsView` 加载远程 `claude.ai/epitaxy`；
- 同时随包携带一份完整的本地 SPA（`Resources/ion-dist`，通过 `app://localhost` 提供），用于固定版本/本地模式；
- 3P 模式则直接使用这份本地 SPA，不再加载 `claude.ai`。

Electron fuse 状态比较强硬：`RunAsNode` 关闭、`NODE_OPTIONS` 关闭、Node inspect 参数关闭、**embedded asar integrity validation 开启**、**only load application code from asar 开启**。`Info.plist` 里钉了 `Resources/app.asar` 的 SHA-256。更新走 Squirrel.Mac。

这带来两个直接后果：

1. **改本地文件不一定能改到界面**。1P 模式下界面是远程 `claude.ai`，你改本地 `app.asar`/`ion-dist` 影响不到它；3P 模式下界面是本地 `ion-dist`，改本地资源才会生效。
2. **改 asar 不是“解包再打包”这么简单**。除了 `Info.plist` 的哈希，较新的 Electron 还会用 Framework 二进制里编译期写入的摘要校验整个 `ElectronAsarIntegrity` 字典；只改 plist 会直接 FATAL 启动失败。`claude-desktop-zh-cn` 的 macOS 补丁就是同时改 plist 和 Framework 两个架构切片，再 ad-hoc 重签，才能跑起来。

### 2.2 1P 与 3P 的关键差异

| | 1P 登录版 | 3P gateway 模式 |
| --- | --- | --- |
| 主窗口来源 | 远程 `https://claude.ai`（本地 `ion-dist` 兜底） | 本地 `ion-dist`，`app://localhost` |
| 用户数据目录 | `~/Library/Application Support/Claude` | `~/Library/Application Support/Claude-3p` |
| 现成主题项目 | Claude Styled、claude-desktop-themes 可用 | 注入路径大多不匹配，CSS 可复用 |
| `REACT_PROFILE` 扩展钩子 | 未公开但可用，content script 注入 `claude.ai` | 钩子是否存在需实测；`app://` 不是 Chrome match pattern 的常规 scheme，content script 很可能不匹配 |
| 改 `ion-dist` | 只影响兜底 SPA，日常界面不受影响 | 直接影响主界面 |
| 改 `app.asar` | 改本地壳层，界面仍是远程 | 可改主进程/preload，效果更直接 |

所以：**在 gateway 模式下，1P 的“扩展注入”路线要打一个问号；CDP 注入和本地资源补丁才是确定能生效的两条路。**

社区项目 ClaudeRipple 的文档也从另一个角度确认了这些差异：3P 模式下窗口不再加载 `claude.ai`，改为本地打包页面；配置写在 `Claude-3p/claude_desktop_config.json`；Chat、Remote Control、连接器等 1P 能力在 3P 下会被替换或关闭。

### 2.3 现成项目盘点（以及它们在 3P 下的可用性）

**Claude Styled（`beforeold/claude-styled`）** 是目前最接近“主题 + 启动器”的 macOS 项目。它提供一个 `Claude Styled.app` 启动器，把 `manifest.json`、`style.css`、`weather.js` 放进 Claude 的应用数据目录，通过 Claude 内部的启动路径加载，然后打开官方 `/Applications/Claude.app`。它不改官方包，启动器自己 ad-hoc 签名。效果包括 16px 正文字号、约 26px 行高、640px 消息列宽、纯黑深色背景、雨/雪氛围动画，并尊重 Reduce Motion。它的 README 明确说依赖“当前版本 Claude Desktop 的未公开启动路径”，更新后可能失效。3P 模式下，它的启动器可以打开 App，但注入路径大概率不生效；它的 CSS 可以拿来复用。

**claude-desktop-themes（`0toshigami/claude-desktop-themes`）** 是主题生态里最完整的一个。它通过 Claude Desktop 的插件市场安装，在 Code tab 里用 `/themes` 打开主题条；第一次安装时把扩展复制到 `~/Library/Application Support/Claude/extensions/fmkadmapgofadopljbjfkapdkoienihi`，并用 `launchctl setenv REACT_PROFILE 1` + LaunchAgent 让 Claude 每次启动都加载它。主题是 `<id>.json` + 可选 `<id>.css`，放在 `~/.claude/themes-for-claude/`；还带 ASCII 动态壁纸和 `make-theme` 技能。它支持 macOS/Windows，明确不支持 Linux。它依赖的正是 2.2 里说的 1P 扩展钩子，3P 下不保证可用；但它的 CSS 文件（`themes/_base.css`、`themes/night-sea.css` 等）写得很好，可以直接拿来做自己的主题底稿。

**claude-desktop-skin（`mohannad789/claude-desktop-skin`）** 是纯 CSS/JS，粘贴到应用开发者控制台运行，不改磁盘，重启即恢复。它主要是布局改造：双栏侧边栏、项目颜色/标签、更宽的聊天区、会话树等。它的 macOS 自动重放脚本用 AppleScript 操作开发者控制台，配合 BetterTouchTool/Shortcuts/Raycast/Hammerspoon 在启动时执行，需要辅助功能权限。**这条“控制台注入”路线在 3P 模式下同样有效**，因为它操作的就是当前页面，不关心页面是 `https://claude.ai` 还是 `app://localhost`。缺点是每次启动要重放，且依赖辅助功能权限。

**userstyles.world 的 Claude Theme** 是纯 CSS 用户样式，主要面向 Web 版，桌面端需要借助 Stylus 之类的注入器；对 3P 桌面端参考价值有限。

**官方能力** 目前只有 Settings → Appearance 里的 Light / Match System / Dark 和聊天字体（Default / Match System / Dyslexic Friendly）。社区一直在提自定义主题/强调色的 feature request（anthropics/claude-code #79305、#85115），但截至调研时没有官方自定义主题。另有 #104600 在请求恢复 Desktop Code tab 的动画启动页，说明官方启动页本身也是社区关注点。

**开屏方面，没有找到现成的 Claude Desktop 启动动画项目。** DSH 的开屏插件不能直接移植，因为它们的宿主接口（`shell.overlay`、`webserver/index-inject`、`app.asar` 插桩）是 DSH 特有的。但它们的视觉和时间轴可以复刻。

---

## 3. 五条路线对比

| 路线 | 真·开屏（窗口出现前） | 主题持久化 | 改官方包 | 更新后 | 签名影响 | 难度 | 适用模式 | 推荐度 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| A. 外挂启动器 | 可以 | 不负责 | 否 | 不受影响 | 无 | 中 | 1P/3P 都可以 | ★★★★★ |
| B. CDP 注入 | 窗口内（偏晚） | 可以，需常驻 agent | 否 | 不受影响 | 无 | 中 | 1P/3P 都可以 | ★★★★★（主题） |
| C. `REACT_PROFILE` 扩展钩子 | 窗口内 | 可以 | 否 | 可能失效 | 无 | 低-中 | 1P 可用；3P 需实测 | ★★★（1P）/ ★★（3P） |
| D. `ion-dist`/`app.asar` 补丁 | 可以（主进程插桩） | 可以 | 是 | 每次更新重做 | 破坏官方签名，需 ad-hoc 重签 | 高 | 3P 更有意义 | ★★（深度玩家） |
| E. DevTools 粘贴 + AppleScript | 否 | 仅当次会话 | 否 | 不受影响 | 无 | 低 | 1P/3P 都可以 | ★★★（快速试皮肤） |
| F. Hammerspoon 覆盖层 | 窗口出现后覆盖 | 不负责 | 否 | 不受影响 | 无 | 低 | 1P/3P 都可以 | ★★★（原型） |

一句话选择：**要开屏选 A，要主题选 B；想零依赖快速试效果选 E；愿意维护 patcher 再考虑 D。**

---

## 4. 推荐架构：Claude Splash + Theme Agent

### 4.1 结构

```
Dock / 快捷键
   │
   ▼
Claude Splash.app（LSUIElement，无 Dock 图标）
   ├─ 0 ms      显示无边框 WKWebView 开屏，level = .screenSaver
   ├─ 80 ms     /usr/bin/open -a Claude --args --remote-debugging-port=9222
   ├─ 100 ms    启动 Theme Agent（Node，轮询 9222）
   ├─ 2800 ms   开屏淡出（0.45s）
   └─ 3300 ms   启动器退出
                     │
                     ▼
             Claude.app（3P）→ app://localhost
                     ▲
                     │ Runtime.evaluate 注入 theme.css（幂等，掉线重连）
             Theme Agent（每秒检查 target）
```

### 4.2 启动时序

| 时间 | 发生什么 | 用户看到什么 |
| --- | --- | --- |
| 0 ms | 启动器显示全屏开屏 | 黑场 + 第一帧 |
| 80 ms | LaunchServices 打开 Claude | 开屏保持在上层 |
| 200–1200 ms | 星芒逐笔绘制 | 主视觉出现 |
| 900–1800 ms | 字标逐字浮起 | Claude 字样出现 |
| 1500–2200 ms | 细线展开 + caption | 构图完成 |
| 2200–2800 ms | 停留、呼吸光 | 稳定画面 |
| 2800–3250 ms | 开屏淡出 | Claude 界面露出 |
| 100 ms 起 | Theme Agent 注入 CSS | 界面按主题渲染 |

### 4.3 为什么是这套

启动器负责“点开图标立刻有反应”，这是 Electron 应用自身做不到的：Claude 的主窗口要等 LaunchServices、主进程、WebContents 创建完才出现，这段时间在 macOS 上就是空白/Dock 弹跳。外挂启动器把这段时间用动画填满。

Theme Agent 负责“进去之后好看”。CDP 注入不依赖页面 origin，`app://localhost` 也能注入；不需要改包，Claude 升级不会覆盖；CSS 改坏了刷新即恢复，迭代成本最低。

两者共享同一套 design tokens（颜色、字体、间距），开屏和界面才像一套东西。

需要说明一个使用边界：**启动器是主入口。** 如果用户直接从 Dock 或 Spotlight 打开官方 Claude，不会经过启动器，也就不会播开屏；如果 Claude 没有带调试端口启动，Theme Agent 也注入不了。想每次都生效，就把 `Claude Splash.app` 放在原来 Claude 的位置，或者在启动器里加一个“重启 Claude 并应用主题”的菜单项。

### 4.4 文件布局

```
claude-splash/
├─ Claude Splash.app/                 # 编译产物
│  └─ Contents/
│     ├─ MacOS/ClaudeSplash
│     ├─ Resources/splash.html       # 开屏动画（单文件）
│     └─ Info.plist
├─ src/
│  ├─ main.swift                     # 启动器
│  └─ splash.html                    # 与 demo 同源
├─ theme/
│  ├─ theme.css                      # 注入的皮肤
│  └─ agent.mjs                      # CDP 注入器
├─ build.sh
└─ install.sh
```

---

## 5. 开屏动画设计（Claude 版）

### 5.1 视觉方向

不要照抄 DSH 的鲸鱼和 HARNESS 字标；要抓的是它的**节奏和层次**。Claude 自己的视觉语言是：温暖的近黑（`#141312` / `#181715`）、奶油白（`#faf9f5` / `#f5f0e6`）、珊瑚橙（`#cc785c`）、衬线字标（Copernicus 风格，系统里可用 Iowan Old Style / Georgia 近似）、星芒/放射状 logo。

方案叫“**Spark, drawn**”：把 Claude 的星芒当作唯一主视觉，用 SVG 一笔一笔画出来，其他元素全部退后。

- 底色：暖黑，不是纯黑；带一点棕，避免冷硬。
- 主色：珊瑚橙只用在星芒和一条细线上，不做大面积铺色。
- 字体：字标用衬线，caption 用系统 sans，字号克制。
- 动效：只做 opacity / transform / stroke-dashoffset；不做弹跳、不做爆炸粒子。
- 声音：默认关闭。

### 5.2 时间轴

| 时间 | 画面 | 实现 |
| --- | --- | --- |
| 0–250 ms | 暖黑底、暗角、细颗粒 | 静态 CSS + SVG noise |
| 160–1200 ms | 12 条星芒按 42 ms 间隔逐条画出 | SVG `pathLength="1"` + `stroke-dashoffset` |
| 700–1400 ms | 细光环扫过一圈 | SVG circle dash + rotate |
| 900–1800 ms | “Claude” 逐字浮起、去模糊 | 每个字母 span，`translateY` + `blur` |
| 1500–2100 ms | 细线从中心展开，caption 淡入 | `scaleX` + opacity |
| 2100–2800 ms | 停留、星芒呼吸光 | `filter: drop-shadow` 脉动 |
| 2800–3250 ms | 整层淡出、轻微放大到 1.015 | opacity + transform |
| 任意时刻点击/Esc | 250 ms 快速淡出 | JS 加 `.exit.fast` |

### 5.3 性能与可访问性

动画只用合成层属性；星芒是 12 条 `<path>`，没有 canvas/WebGL；总资源 < 20KB；本地 `file://` 加载，无网络请求。`prefers-reduced-motion: reduce` 时跳过逐笔动画，直接显示最终构图，1.2s 后淡出。点击/Esc 可跳过，跳过的点击不会穿透到 Claude。

### 5.4 和 DSH 的差异

DSH 的 3 秒是“信息密度高”的 3 秒：鲸鱼、人物、扫描线、光环、横幅、字标、HARNESS，一层接一层。Claude 的方案应该更克制：一个星芒、一个字标、一条线足矣。这不是技术差距，是品牌气质的差异。Claude 的关键词是安静、纸张、思考；开屏应该像一盏灯慢慢亮起来，而不是一场发布会。

---

## 6. 实现手册

### 6.1 启动器（Swift + AppKit）

一个最小启动器只需要做四件事：显示无边框窗口、加载本地 HTML、打开 Claude、定时淡出。下面是骨架，按实际路径调整。

`src/main.swift`：

```swift
import Cocoa
import WebKit

final class AppDelegate: NSObject, NSApplicationDelegate, WKScriptMessageHandler {
    var window: NSWindow!
    var web: WKWebView!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 如果 Claude 已经在运行，直接激活，不播开屏
        if let running = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.anthropic.claudefordesktop")
            .first {
            running.activate(options: [.activateIgnoringOtherApps])
            NSApp.terminate(nil)
            return
        }

        let screen = NSScreen.main?.frame ?? .zero
        window = NSWindow(
            contentRect: screen,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.backgroundColor = .black
        window.isOpaque = true
        window.ignoresMouseEvents = false
        window.alphaValue = 1

        let config = WKWebViewConfiguration()
        config.userContentController.add(self, name: "skip")
        web = WKWebView(frame: screen, configuration: config)
        web.setValue(false, forKey: "drawsBackground") // 透明背景
        if let url = Bundle.main.url(forResource: "splash", withExtension: "html") {
            web.loadFileURL(url, allowingReadAccessTo: Bundle.main.resourceURL!)
        }
        window.contentView = web
        window.makeKeyAndOrderFront(nil)

        // 80ms 后再拉起 Claude，让开屏先上屏
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            p.arguments = ["-a", "Claude", "--args", "--remote-debugging-port=9222"]
            try? p.run()
        }

        // 3.25s 后淡出并退出
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.25) {
            self.fadeOut()
        }
    }

    func userContentController(_ controller: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        if message.name == "skip" { fadeOut() }
    }

    func fadeOut() {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.45
            window.animator().alphaValue = 0
        } completionHandler: {
            NSApp.terminate(nil)
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
```

`splash.html` 里在点击/Esc 时调用：

```js
window.webkit?.messageHandlers?.skip?.postMessage(null);
```

`Info.plist` 关键项：

```xml
<key>CFBundleExecutable</key><string>ClaudeSplash</string>
<key>CFBundleIdentifier</key><string>local.claude.splash</string>
<key>CFBundleName</key><string>Claude Splash</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
```

编译与打包：

```bash
#!/bin/zsh
set -euo pipefail
APP="Claude Splash.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O src/main.swift -o "$APP/Contents/MacOS/ClaudeSplash" \
  -framework Cocoa -framework WebKit
cp src/splash.html "$APP/Contents/Resources/splash.html"
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --deep --sign - "$APP"
```

本地构建的 app 没有 quarantine，ad-hoc 签名即可运行。把 `Claude Splash.app` 拖进 Dock，以后从它启动 Claude。如果希望开机自启，可以加一个 LaunchAgent；不建议把官方 Claude 从 Dock 移除，否则误点时不会经过启动器。

如果你的 gateway 客户端不是 `/Applications/Claude.app`（例如独立的 3P 构建），把 Swift 里的路径和 bundle ID 换成实际值；可以用 `mdfind "kMDItemCFBundleIdentifier == 'com.anthropic.claudefordesktop'"` 定位。

**可选的“等窗口真正出现再淡出”**：用 `CGWindowListCopyWindowInfo` 轮询 Claude 的 PID，检测到 layer 0 的窗口后再淡出。窗口的 owner/bounds 通常不需要屏幕录制权限，但窗口标题需要；为了少一个权限弹窗，默认用固定时长更省事。

### 6.2 Theme Agent（Node + CDP）

先确认 Claude 接受调试端口。退出正在运行的 Claude，然后：

```bash
open -a Claude --args --remote-debugging-port=9222
curl -s http://127.0.0.1:9222/json | python3 -m json.tool | head -40
```

如果能看到 `type: "page"`、`url: "app://localhost/..."` 的 target，说明这条路可行。`--remote-debugging-port` 只在启动时生效；Claude 已经在运行时再 `open --args` 不会重新开端口。

`theme/agent.mjs`（Node 22+ 自带 `fetch` 和 `WebSocket`；更老的 Node 用 `npm i ws`，国内可先把 npm registry 切到 `https://registry.npmmirror.com`）：

```js
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const css = readFileSync(join(here, 'theme.css'), 'utf8');
const PORT = process.env.CDP_PORT ?? '9222';
const alive = new Map();

async function listTargets() {
  const r = await fetch(`http://127.0.0.1:${PORT}/json`);
  if (!r.ok) throw new Error(String(r.status));
  return r.json();
}

function attach(target) {
  if (alive.has(target.id)) return;
  const ws = new WebSocket(target.webSocketDebuggerUrl);
  let id = 0;
  const send = (method, params = {}) =>
    ws.send(JSON.stringify({ id: ++id, method, params }));

  const paint = () => send('Runtime.evaluate', {
    expression: `(() => {
      let s = document.getElementById('__claude_theme__');
      if (!s) {
        s = document.createElement('style');
        s.id = '__claude_theme__';
        (document.head || document.documentElement).appendChild(s);
      }
      s.textContent = ${JSON.stringify(css)};
    })()`,
  });

  ws.addEventListener('open', () => {
    send('Runtime.enable');
    paint();
    const timer = setInterval(paint, 1500); // 刷新/重载后自动补回
    alive.set(target.id, { ws, timer });
  });
  ws.addEventListener('close', () => {
    const rec = alive.get(target.id);
    if (rec) clearInterval(rec.timer);
    alive.delete(target.id);
  });
  ws.addEventListener('error', () => {});
}

setInterval(async () => {
  try {
    for (const t of await listTargets()) {
      if (t.type !== 'page') continue;
      if (!/^(app:\/\/|https:\/\/claude\.ai)/.test(t.url)) continue;
      attach(t);
    }
  } catch {
    // Claude 还没起来或端口没开，下一轮再试
  }
}, 700);
```

启动脚本：

```bash
#!/bin/zsh
set -euo pipefail
if pgrep -x Claude >/dev/null; then
  osascript -e 'quit app "Claude"'
  sleep 1
fi
open -a Claude --args --remote-debugging-port=9222
node theme/agent.mjs
```

注意：调试端口是本机暴露面。默认只监听 `127.0.0.1`，不要把端口转发到局域网；不调样式时用正常方式启动 Claude，不要长期挂着 `--remote-debugging-port`。

### 6.3 主题 CSS 底稿（3P 可用）

下面这些选择器来自 claude-desktop-themes 的实际主题文件，适用于同一套 Ion UI。先从“改表面”开始，不要一上来重排布局。

```css
/* theme.css — Claude Desktop theme starter */
:root {
  --ink: #141312;
  --ink-2: #1b1917;
  --ink-3: #23201d;
  --cream: #f5f0e6;
  --coral: #cc785c;
  --line: rgba(245, 240, 230, 0.14);

  /* 尽量走 Claude 自己的 token，减少对具体 class 的依赖 */
  --cds-surface-0: var(--ink);
  --cds-surface-1: var(--ink-2);
  --cds-surface-2: var(--ink-3);
  --cds-text-primary: var(--cream);
  --cds-text-muted: rgba(245, 240, 230, 0.56);
  --cds-text-accent: var(--coral);
  --desktop-theme-backdrop: var(--ink);
}

html,
body {
  background: var(--ink) !important;
}

.dframe-root,
main.dframe-content,
.tiles-shell {
  background: transparent !important;
}

.dframe-sidebar,
.dframe-sidebar-body {
  background: var(--ink-2) !important;
}

/* 输入框：毛玻璃 + 细边 */
[data-cds="ChatComposer"] > .bg-surface-3 {
  background: rgba(245, 240, 230, 0.055) !important;
  backdrop-filter: blur(14px);
  box-shadow: inset 0 0 0 1px var(--line) !important;
  border-radius: 18px !important;
}

/* 正文排版 */
.epitaxy-markdown {
  font-size: 16px !important;
  line-height: 1.65 !important;
  letter-spacing: normal !important;
}

[class~="group/msg"] {
  max-width: 680px !important;
  margin-inline: auto !important;
}

::selection {
  background: var(--coral);
  color: var(--ink);
}

/* 可选：极轻的噪点/暗角，别抢内容 */
html::after {
  content: "";
  position: fixed;
  inset: 0;
  pointer-events: none;
  z-index: 2147483646;
  opacity: 0.35;
  background:
    radial-gradient(1px 1px at 20% 30%, rgba(245, 240, 230, 0.5), transparent),
    radial-gradient(1px 1px at 70% 60%, rgba(204, 120, 92, 0.35), transparent),
    radial-gradient(1.5px 1.5px at 45% 80%, rgba(245, 240, 230, 0.3), transparent);
  background-size: 420px 420px;
}
```

如果要做“工具运行时发光 / 出错时抖动”这类状态效果，claude-desktop-themes 的做法是在 `html` 上写 `data-theme-state` / `data-theme-event` 属性，CSS 用属性选择器响应。你可以用一个小的 MutationObserver 监听 composer 的状态文本，自己打这两个属性；具体状态文案会随版本变化，属于易碎逻辑，建议先不做。

### 6.4 扩展钩子路线（1P 可用；3P 先实测）

这条路线只在你能接受“未公开开发钩子”时使用。机制是：Claude Desktop 启动时读环境变量 `REACT_PROFILE`，为 `1` 时调用 `loadReactDevTools()`，用 `session.defaultSession.loadExtension()` 加载固定目录下的 Chrome 扩展；扩展 ID 目录名是 React DevTools 的 `fmkadmapgofadopljbjfkapdkoienihi`。Mac 上的路径按用户数据目录类推，1P 是 `~/Library/Application Support/Claude/extensions/...`，3P 要先确认是不是 `Claude-3p`。

`manifest.json`：

```json
{
  "manifest_version": 3,
  "name": "claude-desktop-theme",
  "version": "0.1.0",
  "content_scripts": [
    {
      "matches": ["https://claude.ai/*"],
      "css": ["theme.css"],
      "js": ["theme.js"],
      "run_at": "document_start"
    }
  ]
}
```

安装：

```bash
EXT="$HOME/Library/Application Support/Claude/extensions/fmkadmapgofadopljbjfkapdkoienihi"
mkdir -p "$EXT"
cp manifest.json theme.css theme.js "$EXT/"
launchctl setenv REACT_PROFILE 1
```

登录时保持：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>local.claude.react-profile</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/launchctl</string>
    <string>setenv</string>
    <string>REACT_PROFILE</string>
    <string>1</string>
  </array>
  <key>RunAtLoad</key><true/>
</dict>
</plist>
```

保存到 `~/Library/LaunchAgents/local.claude.react-profile.plist`，然后 `launchctl load ~/Library/LaunchAgents/local.claude.react-profile.plist`。卸载时 `launchctl unsetenv REACT_PROFILE`，删掉扩展目录和 plist。

注意事项：

- 这个目录可能同时被真正的 React DevTools 或其他 mod 使用。不要整个覆盖；像 `claude-desktop-webext` 那样合并 `content_scripts` 更安全。
- 3P 模式下 `app://localhost` 不是 Chrome match pattern 的常规 scheme，`matches: ["https://claude.ai/*"]` 不会命中。可以试 `matches: ["app://localhost/*"]` 或 `<all_urls>`，但不要抱太大期望；不行就回到 CDP。
- content script 运行在已登录页面里。只放本地 CSS/JS，不要 `fetch` 外部资源，不要读会话内容。主题 CSS 里也不要有 `@import` 或远程 `url()`。

### 6.5 深度补丁路线（可选，不建议首选）

如果你追求“完全不依赖外部启动器/agent，点开就是定制版”，那就要改本地资源。3P 模式下 `ion-dist` 就是主界面，改它最直接。

只换皮肤的话，步骤大致是：

1. 找到 `/Applications/Claude.app/Contents/Resources/ion-dist`（目录或 `ion-dist.asar`）。
2. 目录形态：在 `index.html` 里加 `<link rel="stylesheet" href="./claude-theme.css">`，把 CSS 放进同目录。
3. asar 形态：解包、加文件、重打包；同步 `Info.plist` 里 `ElectronAsarIntegrity` 对应条目的 SHA-256。
4. 较新的 Electron 还要改 `Electron Framework` 二进制里 `__DATA_CONST,__asar_integrity` 的编译期摘要（arm64/x86_64 两个切片），否则会 FATAL：`Failed to get integrity for validatable asar archive`。
5. 对整个 app 做 ad-hoc 重签，清 quarantine。若希望 Squirrel 自动更新还能安装，重签时要写 identifier 级别的 designated requirement（`claude-desktop-zh-cn` 已经踩过这个坑并给出了做法）。
6. 每次 Claude 更新后重做。更新会覆盖 `/Applications/Claude.app`，主题回到官方样子。

想连开屏也做进主进程，则要改 `app.asar` 里的主进程 bundle，在主窗口创建前插一个 splash BrowserWindow。`dsh-rsa` 的做法是在入口第一行注入 `import("./splash.cjs")`，macOS 上同样可行，但 Claude 的主进程是 Vite 打包的 `.vite/build/index.pre.js`，混淆/拆分方式随版本变化，插入点比 DSH 更难找。**性价比不高，建议用外挂启动器代替。**

深度路线的真实成本不在“改”，在“每次更新后重新改”。`claude-desktop-zh-cn` 之所以能长期维护，是因为它把备份、版本识别、哈希同步、重签、自动更新开关都脚本化了。如果你只想做皮肤，不值得从零写一套；可以直接参考它的 macOS 脚本，把汉化 payload 换成你的 CSS。

### 6.6 Gateway 模式检查清单

在动手前，先在 Claude 里确认这四件事：

1. **主界面 origin**：Help → Troubleshooting → Enable Developer Mode，然后 Cmd+Opt+I，Console 里执行 `location.href`。看到 `app://localhost/...` 就是 3P 本地 UI；看到 `https://claude.ai/...` 才是 1P。
2. **用户数据目录**：`ls -d ~/Library/Application\ Support/Claude*`。3P 应该有 `Claude-3p`；扩展目录、配置、日志都在对应目录下。
3. **调试端口**：退出 Claude，`open -a Claude --args --remote-debugging-port=9222`，再 `curl -s http://127.0.0.1:9222/json`。有 target 就能走 CDP。
4. **ion-dist 形态**：`ls /Applications/Claude.app/Contents/Resources | grep ion`。是目录还是 asar，决定深度路线的工作量。

如果第 3 步失败，先走 6.4 的 DevTools 粘贴方案（配合 AppleScript 自动重放），或者 6.5 的 ion-dist 补丁；不要在没有备份的情况下直接改 `/Applications/Claude.app`。

---

## 7. 维护与风险

**更新会变。** Claude Desktop 更新频繁，Ion UI 的 class、`data-*` 属性、`ion-dist` 的打包方式都可能变。主题 CSS 尽量依赖 `--cds-*` 变量和稳定的 `data-cds` 属性，少依赖哈希 class；开屏启动器不受影响，因为它只调用 `open -a Claude`。

**签名会破。** 任何改 `/Applications/Claude.app` 内部文件的做法都会破坏官方签名。ad-hoc 重签能让它本机运行，但会失去公证，TCC 权限可能被重置，Squirrel 更新也可能不认。外挂启动器和 CDP 注入不碰签名，这是它们最大的优势。

**端口是暴露面。** `--remote-debugging-port` 能让本机任何进程控制 Claude 的渲染进程。只在需要注入时开，用完正常重启；不要把端口暴露到局域网。

**内容脚本的边界。** 主题 JS 运行在登录页面里。只做样式和装饰 DOM，不要读会话内容、不要发网络请求。claude-desktop-themes 的 CSS 安全策略（禁止 `@import` 和远程 `url()`）值得照抄。

**条款与账号风险。** 这些都是非官方修改，Anthropic 不背书。Claude Styled 的 README 明确说无法替你评估未来的兼容性和条款风险；DSH 插件也都在 README 里声明商标归属。自己用可以，别做成分发包到处传。

**测试清单。** 改完至少检查：浅色/深色切换、窗口缩放、侧边栏折叠、输入框聚焦、代码块、Mermaid/表格、工具调用状态、重启后是否自动恢复、点击跳过是否会误触 Claude 界面、Reduce Motion 下是否静止。

---

## 8. 落地路线图

**第一个晚上：把开屏跑起来。** 用`extras/claude-splash-demo.html` 当素材，套进 6.1 的 Swift 启动器；先不做主题，确认“点 Dock → 开屏 → Claude 出现”这条链路顺畅。重点调时间轴：星芒绘制速度和字标出现时机。

**第二个晚上：主题注入。** 用 6.2 的 agent 注入 6.3 的 CSS；先只改背景、正文宽度、输入框三个地方，确认 `app://localhost` target 能稳定注入。把 agent 做成 LaunchAgent，或者让启动器拉起它。

**第三个晚上：统一视觉。** 让开屏和主题共用一套 token：同一个珊瑚橙、同一个暖黑、同一个圆角。加 Reduce Motion、跳过、错误兜底（agent 连不上时静默退出，不影响 Claude 启动）。

**之后：** 如果发现每次更新后 CSS 选择器失效，再考虑 6.5 的 ion-dist 补丁；否则维持“启动器 + agent”的组合，维护成本最低。

---

## 9. 参考与来源

DSH 开屏生态：

- [dsh-startup-animation](https://github.com/davidLi17/dsh-startup-animation) — 3s shell.overlay 开屏，内联 WebP，可换视频/图片
- [dsh-rsa](https://github.com/BeckChiang/dsh-rsa) — Electron 主进程 splash，深度部署 app.asar（Windows）
- [dsh-splash-fish](https://github.com/Streamfish-lab/dsh-splash-fish) — 2.5D 视差 WebM 开屏
- [dsh-splash-launcher](https://www.npmjs.com/package/dsh-splash-launcher) — WebView2 包装器，SVG 逐笔绘制
- [dsh-opening-splash](https://socket.dev/npm/package/dsh-opening-splash) — iframe 长开场
- [dsh-first-paint](https://socket.dev/npm/package/dsh-first-paint) — 黑色首帧，消除白闪
- [dsh-web-start-ui](https://raw.githubusercontent.com/stushansusu/dsh-web-start-ui/main/README.zh.md) — 视频皮肤启动页
- [dsh-companion](https://github.com/sssswwwwbbbb/dsh-companion) — 启动动画 + 桌宠 + 皮肤管理

Claude Desktop 主题/定制：

- [Claude Styled](https://github.com/beforeold/claude-styled) — macOS 启动器 + CSS 注入，不改官方包
- [claude-desktop-themes](https://github.com/0toshigami/claude-desktop-themes) — `/themes` 主题系统、ASCII 壁纸、`REACT_PROFILE` 扩展钩子
- [claude-desktop-skin](https://github.com/mohannad789/claude-desktop-skin) — 开发者控制台 CSS/JS 布局皮肤
- [Claude Theme on userstyles.world](https://userstyles.world/style/28342/claude-theme) — Web 版纯 CSS 主题
- [claude-desktop-zh-cn](https://github.com/javaht/claude-desktop-zh-cn) — macOS/Windows 汉化补丁，含 asar 完整性、重签、自动更新的完整处理
- [Claude-WebExtension-Launcher](https://github.com/lugia19/Claude-WebExtension-Launcher) — 修改版 Claude Desktop，支持 WebExtension（macOS 上 Cowork 会因签名失效）
- [Qiita：REACT_PROFILE 与 React DevTools 加载路径](https://qiita.com/zawa356/items/207104b10a46ea6d9960) — 扩展钩子的来源说明

Claude Desktop 结构与官方信息：

- [Claude Desktop (macOS) Teardown — 2026-07-10](https://raw.githubusercontent.com/OpenAgentsInc/openagents/8f84d05896ef14edee491621bf977ee5315cc8ed/docs/teardowns/2026-07-10-claude-desktop-app-teardown.md) — Electron 版本、fuses、asar 完整性、Squirrel、目录结构
- [Electron ASAR Integrity](https://www.electronjs.org/docs/latest/tutorial/asar-integrity) — `EnableEmbeddedAsarIntegrityValidation` 与哈希机制
- [Customizing your appearance settings](https://support.claude.com/en/articles/8887527-customizing-your-appearance-settings) — 官方只有 Light/Dark/System + 字体
- [Claude Desktop on 3P: Overview](https://claude.com/docs/third-party/claude-desktop/overview) — 3P 模式加载本地 Web 应用、独立用户数据目录
- [Claude Desktop 3P Gateway 配置](https://claude.com/docs/third-party/claude-desktop/gateway) — Gateway base URL / key / auth scheme
- [ClaudeRipple](https://github.com/PBJ-2/clauderipple) — 社区项目，记录了 3P 与 1P 的行为差异（本地页面、`Claude-3p` 配置、功能取舍）
- [anthropics/claude-code #79305](https://github.com/anthropics/claude-code/issues/79305) — 桌面端自定义主题/强调色 feature request
- [anthropics/claude-code #85115](https://github.com/anthropics/claude-code/issues/85115) — 桌面端自定义外观 feature request
- [anthropics/claude-code #104600](https://github.com/anthropics/claude-code/issues/104600) — 恢复 Desktop Code tab 动画启动页的请求

CDP 与设计参考：

- [Automating Claude Desktop via Chrome DevTools Protocol](https://www.jedi.be/blog/2026/automating-claude-desktop-via-chrome-devtools-protocol/) — `--remote-debugging-port` 启动与注入
- [Open Claude UI](https://openclaudeui.com/en) — Claude Desktop UI 的颜色、字体、motion token 逆向整理
- [Anthropic Trademark Guidelines](https://cdn.sanity.io/files/4zrzovbb/website/f7874b435aabdaee5f836e888b4439b9b56a934b.pdf) — 商标使用边界

---

## 附：开屏 demo

`extras/` 目录下的 `extras/claude-splash-demo.html` 是一个可直接用浏览器打开的 Claude 风格开屏概念稿：暖黑底、12 条星芒逐笔绘制、衬线字标逐字浮起、细线展开；点击/Esc 可跳过，支持 `prefers-reduced-motion`。动画本体按 2.8 秒设计，demo 为了便于观察会多停留一会儿（约 4.6 秒）再进入重播页。它不是启动器的一部分，但可以原样作为 `src/splash.html` 使用，或者在它的基础上改时间轴和配色。
