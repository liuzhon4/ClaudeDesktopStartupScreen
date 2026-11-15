# Claude Desktop 开屏移植评估

> ⚠️ **历史存档（2026-11-14 审计后加注）**：本文写于实现之前，其中的 CDP / `--remote-debugging-*` / `launchctl setenv` / `open --env` 类命令已被项目硬约束**禁止**（见 [AGENTS.md](../AGENTS.md)），**不要照着执行**。现行实现对 Claude 只用 `open -b com.anthropic.claudefordesktop`（不传参数、不设环境变量）。文中的 **EdClaude / local.edclaude.\*** 是应用改名前的旧称，现名 **ClauEd**（`local.claued.splash`）。当前可用的关闭/恢复命令见 [备份与恢复方案（Safe Mode · 外部关闭）.md](备份与恢复方案（Safe%20Mode%20·%20外部关闭）.md)。

## 把 `dsh-startup-screen` 变成 Claude 版：可行性、架构与品牌替换方案

> 评估时间：2026-11-13 · 对象：[6shenhonghong9/dsh-startup-screen](https://github.com/6shenhonghong9/dsh-startup-screen) v1.3.0（MIT）
> 本机环境：Claude Desktop **5.11492.2**，Electron **45.2.1**，arm64，macOS 13+，当前运行在 **3P（custom-3p）模式**，页面 origin 为 `app://localhost`
> 方法：源码逐行精读 + Claude.app 只读勘测（含 app.asar / ion-dist.asar 解析）+ 两套移植设计 + 对抗性评审。全程未修改、未启停 Claude。原始调研报告仅作本机证据存档，不随公开仓库分发。

---

## 0. 结论先行

**可移植性：高。但路线必须改。**

1. **动画引擎本身不依赖 DeepSeek Harness。** `lib/splash.js` 是一个 1,750 行、零 npm 依赖的浏览器 IIFE，配置从 `window.__DSH_STARTUP__` 读取；`lib/splash.css` 全部选择器限定在 `#dsh-startup-root` 之下。DSH 专属的只有 Host 半侧的三件事：配置注入、`/dsh-startup/asset/` 素材路由、设置页——全都可以用本地替代品换掉。**引擎可以原样带走。**
2. **⚠️ 一条颠覆现有调研文档的事实：CDP 注入路线在当前版本上被封死。** Claude Desktop 5.11492.2 的主进程里有启动守卫：命令行出现 `--remote-debugging-port` / `--remote-debugging-pipe` / `disable-web-security` 等开关时，直接打印 `Claude: refusing to start — a debugging or network-override switch is present on the command line.` 并 `exit 1`；唯一豁免需要 Anthropic 签名的 `CLAUDE_CDP_AUTH` token（Ed25519，公钥硬编码），个人无法自签。证据：`app.asar` 内 `.vite/build/index.pre.js` 的黑名单（byte 889287）与拒绝逻辑（byte 970639）——这是高置信的静态证据，建议按 §7 的 T1 实测确认。**这意味着你调研文档里的「Theme Agent（CDP 注入主题）」同样不可用，不只是开屏。**
3. **因此推荐架构 = 纯外挂启动器（你文档的路线 A）承载整套 DSH 式开屏。** 启动器在 t=0 显示全屏黑幕窗口（`.screenSaver` 层级，先于 Claude 出现），WKWebView 里跑 fork 后的 splash 引擎，播完淡出露出 Claude。这是当前版本上**唯一能落地**的载体。混合模式（启动器黑幕 → CDP overlay 接管 → 在 Claude 窗口内揭幕）作为**条件增强**保留，默认关闭，等 guard 放开才有意义。
4. **「图片」其实是矢量，不是位图。** 插件本体没有任何位图/照片资产；`docs/screenshots/` 的两张 JPG 只是 README 截图。实际要换的「图像」是内联 SVG 的 **DeepSeek 鲸鱼标识**（`WHALE_PATH`，3 处运行时引用 + preview 里 1 份副本）。换成 Claude 星芒即可，几何与现成 path 见 §4.2。
5. **品牌字段替换量**：12 个可配置文案字段 + 8 处硬编码文案 + 3 处鲸鱼 SVG + 若干 CSS 颜色。完整逐项表见 §4，最小改动清单 17 条。
6. **音频不能复用。** 原素材取自第三方视频真声/克隆音色（XTTS-v2，CPML 非商用），换成自产预渲染 mp3 或浏览器 TTS。代码自带 `voiceSource:'tts'` / `sfx:'synth'` 降级路径，改造代价低。
7. **工作量估计**：纯 B 最小可用版约 2–3 个晚上（P0 离线壳半天 → P1 品牌 fork 一天 → P2 音频半天 → P3 启动器一天）。

---

## 1. 插件解剖：它到底是什么

### 1.1 三段式结构

| 部分 | 文件 | 行数 | 职责 | 移植结论 |
|---|---|---|---|---|
| Host 半侧 | `lib/index.js` | 416 | Cordis 插件：注册 `/dsh-startup/*` 路由、注入 `index.html`、读写配置、Windows 标题栏透明 | **丢弃**，职责由启动器/壳页面替代 |
| 设置页 | `lib/client.js` | 869 | 向 DSH 设置 UI 注册「启动动画」分组（38 个配置键） | **丢弃**（v1 用 JSON 配置；以后可做独立设置页） |
| 运行时 | `lib/splash.js` | 1,750 | 六幕动画状态机、音频、主题、交互、看门狗——**零依赖 IIFE** | **原样带走**，只做品牌/素材路径 fork |
| 样式 | `lib/splash.css` | 1,182 | 全部限定 `#dsh-startup-root`；17 个 `--dsu-*` 变量；玻璃层 `backdrop-filter` | **带走**，换色 + 星芒 stroke 适配 |
| 独立壳 | `preview/index.html` | 568 | 不依赖 DSH 的离线预览页：相对路径加载三件套 + 内联配置 + 调试面板 | **最佳移植起点**（删面板即得壳页面） |
| 素材 | `lib/assets/*.mp3` | 8 个 | 6 句人声 + 2 个音效 | **不可复用**，需自产 |

### 1.2 运行时关键机制（移植时必须保留的契约）

- **挂载**：`document.body.appendChild(#dsh-startup-root)`，`root.innerHTML` 建壳；`window.__DSH_STARTUP_LOADED__` 单例防重入；`run()` 在 `DOMContentLoaded` 后启动。
- **配置**：`cfg()` 先复制 `DEFAULTS`（38 键），再用 `window.__DSH_STARTUP__` 的非空键覆盖；`window.__DSH_STARTUP_API__` 暴露 `replay/skip/finish/dispose`。
- **时间轴**：黑幕 820ms → 标识淡入/字距收紧/扫光 → 洗白 → 暖白档案底板 → 五步授权（第 1、2 步等按钮/Enter/Space）→ 终幕故障揭幕 → `dsu-handoff`。完整约 **12–18s**（取决于台词时长和点击速度）。
- **音频**：voice 双通道（素材 `fetch` + `speechSynthesis` 兜底）、WebAudio 合成音效（cue/sweep/rise/chime）、首次手势解锁、`holdFor = max(视觉基准, 播报时长+240ms)`。
- **看门狗**：9s 未启动兜底（拆 root 解锁）、15s 停滞强制收尾——这两个是防止「黑屏锁死」的生命线，移植必须保留。
- **素材 URL 硬伤**：两处 `fetch('/dsh-startup/asset/' + name + '.mp3')` **写死 origin 绝对路径**（`splash.js:1050,1066`），源码里没有 `assetBase` 配置字段。移植时必须 fork 成可配置基址。

---

## 2. 环境勘测：决定路线的六个事实

| # | 事实 | 对移植的含义 |
|---|---|---|
| 1 | 真实主界面在 **`ion-dist.asar`**（207.9 MB / 5,399 文件）；`Resources/ion-dist/` 目录只是 1,466 B 的「Claude was updated」占位页 | 任何「改本地 UI」的想法都以 asar 为准 |
| 2 | CSP 不是 `<meta>`，而是 `app://` 响应头动态生成：`style-src 'self' 'unsafe-inline'`；`script-src 'self' 'wasm-unsafe-eval'` + 运行时计算的内联脚本 sha256（无 `unsafe-inline`）；`media-src 'self'`；`img-src 'self' data: blob:`；`connect-src 'self' + 白名单` | 若将来做 in-app 注入：`<style>` 可插；`<audio src=data:/blob:>` 被 media-src 拦截（走 Web Audio `decodeAudioData` 可以）；外链一律不行 |
| 3 | 两个 asar 都启用 **ElectronAsarIntegrity**（plist 里是 asar header JSON 的 SHA256，已实测核对一致）；Developer ID + hardened runtime + 已公证 + team 级 keychain entitlement | 改 ion-dist 补丁必须改 plist + Framework 摘要 + ad-hoc 重签；重签会丢 keychain 组 → safeStorage 登录 token 可能失效。**不建议** |
| 4 | **CDP 启动守卫**：`--remote-debugging-port` 等开关直接拒绝启动（exit 1），豁免需 Anthropic 签名 token | 方案 A（窗口内 overlay）与 Theme Agent 当前均不可用；静态证据高置信，建议 T1 实测确认 |
| 5 | 单实例锁：`requestSingleInstanceLock()`，第二次启动只唤醒现有实例并转发参数 | 对正在运行的 Claude 再 `open --args` 不会加调试端口；任何「重启带参数」都会打断当前会话 |
| 6 | 自动更新走 Squirrel.Mac / ShipIt（本机今天 21:26 刚更新过一次） | 启动器不碰官方包，不受更新影响；这是它相对补丁路线的最大优势 |

---

## 3. 三条路线对照（更新后的判决）

| 维度 | A. CDP 注入 | B. 外挂启动器 | C. ion-dist 补丁 |
|---|---|---|---|
| 当前 build 能否落地 | **不能**（启动守卫，静态证据） | **能** | 技术可行，风险高 |
| 开屏在 Claude 窗口内播放 | 是（原生体验） | 否（独立全屏窗口） | 是 |
| 首帧前生效 | 需 preload 注入，且受守卫阻断 | **可以**（启动器先黑） | 可以 |
| 修改官方包 / 签名风险 | 无 | **无** | 破坏签名、可能丢 keychain、每次更新重打 |
| 升级后存活 | —（守卫可能变化） | **是**（只调用 `open`） | 否 |
| 维护成本 | — | 低 | 高 |
| **判决** | **条件方案**（等 guard 放开 / 官方签名 token，保留离线 payload） | **✅ 主方案** | 不推荐 |

**「放到 Claude Desktop 里面」的诚实回答**：在这个版本上，动画会播在一个模仿 Claude 气质、先于 Claude 出现的全屏启动器窗口里，结束时淡出露出真正的 Claude 窗口——视觉上几乎无缝，但严格说不是「在 Claude 窗口内部」。想要真正的应用内接管，只有两条路：等 CDP 守卫放开（或官方开放能力），或走 ion-dist 补丁并接受重签风险。建议先用纯 B 交付，把 payload 写成「离线可验证、将来可插入 overlay」的形态。

---

## 4. DeepSeek → Claude 品牌替换总表

### 4.1 文案字段（12 个可配置项，`splash.js:71-105` 与 `index.js:38-80` 两处 DEFAULTS 必须同步改）

| 字段 | 现值 | **Claude 建议值（候选 A，推荐）** | 候选 B | 落点 |
|---|---|---|---|---|
| `brand1` | `DEEPSEEK` | `CLAUDE` | `ANTHROPIC` | 左上主标题 33px |
| `brand2` | `SYNTHESIZE INTELLIGENCE` | `ANTHROPIC` | `CLAUDE DESKTOP` | 左上副标题 15px |
| `brand3a` | `HARNESS` | `DESKTOP` | `AI` | 左上产品行（粗体） |
| `brand3b` | `OS` | `APP` | `ASSISTANT` | 左上产品行（细体） |
| `orgZh` | `深度求索` | `克劳德`（音译，非官方名，见 §8） | `安思罗匹克` | 黑幕中文主字 |
| `orgEn` | `DEEPSEEK` | `CLAUDE` | `ANTHROPIC` | 黑幕英文 |
| `orgSub` | `DEEPSEEK HARNESS` | `CLAUDE DESKTOP` | `CLAUDE DESKTOP` | 黑幕小字 |
| `welcomeBox` | `DEEPSEEK HARNESS` | `CLAUDE DESKTOP` | `ANTHROPIC · CLAUDE` | 终幕中央黑框 |
| `footer` | `POWERED BY DEEPSEEK` | `POWERED BY ANTHROPIC` | `BUILT BY ANTHROPIC` | 右下页脚 |
| `identity` | `JOYCE MOORE` | 你自己的名字 | — | 终幕欢迎语 / 身份卡 |
| `identityId` | `0087` | `CLD-0087`（显示会规范成 `CLD0087`） | — | ID CONFIRMED / 身份卡 |
| `accessLevel` | `3` | `PRO` | `MAX` | 身份卡「访问等级」 |

### 4.2 硬编码文案（8 处，必须改代码）

| 位置 | 现值 | 换成 |
|---|---|---|
| `splash.js:764` | `D E E P S E E K` | `C L A U D E` |
| `splash.js:769` | `D E E P S E E K · H A R N E S S` | `C L A U D E · A N T H R O P I C`（或删） |
| `splash.js:791` | `REV 0.1.0 · WEB PROFILE` | `REV 1.0.0 · CLAUDE DESKTOP` |
| `splash.js:748` | `'欢迎 ' + identity + ' 访问'` | `'欢迎 ' + identity + ' 开始对话'` |
| `splash.js:749` | `· ID CONFIRMED : 0087` | `· IDENTITY CONFIRMED : CLD0087` |
| `splash.js:1585-1588` | 身份卡三行标签 | 用户名称 / 会话编号 / 访问等级 |
| `splash.js:648` | `WELCOME TO` | 保留（通用） |
| `preview/index.html:125-126` | 鲸鱼 SVG + `DeepSeek Harness` | 星芒 + `Claude`（随假主界面一起删也行） |

### 4.3 「图片」= 鲸鱼 → 星芒（插件里唯一的图像资产）

- 鲸鱼是 `WHALE_PATH` 常量（`splash.js:26-68`，DeepSeek 官方 path，取自其 favicon），由 `svgWhale()`（`splash.js:517-528`）渲染，出现在 3 处：黑幕中央（122px）、第二幕标识（84px）、终幕（76px）。`preview/index.html:125` 另有 1 份。
- Claude 星芒直接复用你 `extras/claude-splash-demo.html` 的几何：**12 条射线、每 30°、内外半径 20→88/76、viewBox 240、stroke 3.2、`stroke-linecap: round`**。烘焙成单 path 可直接替换：

```js
/* Claude 星芒：12 射线，长短交替，viewBox 0 0 240 240，stroke 用 */
var SPARK_PATH =
  'M120.00 100.00L120.00 32.00' +
  'M130.00 102.68L158.00 54.18' +
  'M137.32 110.00L196.21 76.00' +
  'M140.00 120.00L196.00 120.00' +
  'M137.32 130.00L196.21 164.00' +
  'M130.00 137.32L158.00 185.82' +
  'M120.00 140.00L120.00 208.00' +
  'M110.00 137.32L82.00 185.82' +
  'M102.68 130.00L43.79 164.00' +
  'M100.00 120.00L44.00 120.00' +
  'M102.68 110.00L43.79 76.00' +
  'M110.00 102.68L82.00 54.18'
```

- **三个必须注意的坑**：
  1. `svgWhale()` 改成 `svgSpark()`：星芒是 **stroke** 不是 fill（`fill:none; stroke:currentColor; stroke-width:6`），而现有 CSS 有 `fill: currentColor` 会覆盖 presentation attribute，CSS 侧必须同步改成 `fill:none; stroke:currentColor`（`splash.css:87-88,190-193`）。
  2. **`assembleLogo()` 的收尾会把星芒擦掉**：原实现画完把 `strokeWidth` 归零（`splash.js:1571`，对填充鲸鱼是「落墨」，对 stroke 星芒等于消失）。必须删除该行，只保留 dashoffset 动画。
  3. 若保留 12 条独立 path（更贴近 demo 的 38ms 错峰入场），`assembleLogo()` 要从「取第一条 path」改成遍历全部。

### 4.4 六句台词（Claude 版草案）

叙事保持「授权访问」，语义改为 Claude 语境。默认 `voiceLang:'en'`，英文台词实际出声，中文只做视觉。

| # | 中文主字 | 英文副标题 | 台词（TTS/字幕） | 按钮 |
|---|---|---|---|---|
| 1 | 需要访问许可 | `ACCESS PERMISSION REQUIRED` | `Access permission required.` | 授予访问权限 / `GRANT ACCESS` |
| 2 | 身份资料确认 | `IDENTITY VERIFICATION` | `Identity verification.` | 确认身份 / `CONFIRM IDENTITY` |
| 3 | 已接收请求 | `REQUEST RECEIVED` | `Request received. Establishing session.` | 自动 |
| 4 | 读取上下文中 | `READING CONTEXT` | `Reading context.` | 自动 |
| 5 | 上下文就绪 · 校验通过 | `CONTEXT READY · VERIFIED` | `Context loaded. Verification passed.` | 自动 |
| 6 | 欢迎 {name} 开始对话 | `WELCOME, {NAME}` | `Welcome. Access granted.`（可选） | 自动 |

终幕语音注意：`splash.js:1634` 现在是 `voice.line(null, null, 'line-6')`——素材缺失时**静音**。要出声就改成 TTS 文本，或提供自产 `line-6.mp3`。

### 4.5 配色（换皮时建议一起换，避免「Claude 的字 + 参考片的橙」）

| Token | 现值 | 建议 |
|---|---|---|
| `accent` 强调色 | `#ff7500` | `#cc785c`（Claude coral） |
| `glitchA / glitchB` 故障色 | `#ff3b30` / `#2971b8` | `#d97757` / `#6a9bcc` |
| 浅色底板 | `#e5e3df` / `#eceae6` | `#f5f0e6` / `#faf9f5`（cream） |
| 深色底板 | `#0b0b0c` | `#0f0e0d` / `#171412`（暖黑） |

CSS 里有两处没走变量的橙色泄漏：`splash.css:559-560`（`rgba(255,117,0,…)`）与 `798,802`（蓝色）——要硬改。

### 4.6 音频

- **不可复用原素材**：前 5 句取自第三方视频真声，`line-6` 是 XTTS-v2 克隆（CPML 非商用），均不能随 Claude 版分发。
- 推荐管线：用 `STEPS[].say` 的文本**预渲染 6 个 mp3**（macOS `say`、Volcano/edge-tts 或自录均可，中文只做视觉不必录），随启动器打包；`speechSynthesis` 只当兜底（WKWebView 是否暴露该 API 未验证）。
- 音效不用管：缺 `sfx-tick.mp3` 时引擎自动用 WebAudio 合成等价音（`splash.js:1126-1129`）。

### 4.7 法律边界（一句话版）

DeepSeek 商标与鲸鱼必须清干净；Claude/Anthropic 名称与星芒归 Anthropic 所有，**个人、非商用、本地、不再分发**的界面美化风险较低；不要公开分发改好的包、不要暗示官方背书。代码按 MIT 可用，第三方素材（原音频、参考片视觉）不在 MIT 覆盖范围内。

---

## 5. 移植架构（纯 B：外挂启动器）

### 5.1 组件与文件布局

```
ClaudeTheme/                      ← 本项目目录
├─ EdClaude.app/             ← 编译产物（ad-hoc 签名）
│  └─ Contents/
│     ├─ MacOS/EdClaude
│     ├─ Resources/
│     │  ├─ splash.html           ← 从 preview/index.html 派生的壳
│     │  ├─ splash.css            ← fork 版
│     │  ├─ splash.js             ← fork 版
│     │  ├─ bridge.js             ← skip/done/error 桥
│     │  └─ assets/line-1..6.mp3  ← 自产音频
│     └─ Info.plist               （LSUIElement、local.edclaude.splash）
├─ src/main.swift                 ← 窗口/时序/看门狗
├─ fork/splash.js · fork/splash.css
├─ assets/                        ← 音频源文件
└─ build.sh · install.sh
```

### 5.2 壳页面：从 `preview/index.html` 派生（27 项改造的要点）

1. **删掉**：`#mockApp` 假主界面（含鲸鱼）、`#console` 调试面板、`#settingsMock` 设置页模拟（约 400 行）。
2. **保留**：`<div id="dsh-startup-root" class="dsu-root dsu-boot">` 挂载点、`window.__DSH_STARTUP_SCRIPT_URL__='splash.js'`、`defer` 的 splash.js。
3. **补上**：
   - 完整 38 字段配置（preview 只写了 22 个），Claude 值见 §4；
   - Host 侧的四条 critical CSS（`html.dsu-lock` 锁滚动 / body 压黑 / root 黑罩）——preview 里没有，壳必须自带，否则首帧可能闪白；
   - 9 秒兜底脚本（判断「时间线是否 RUNNING」，不是判断类名）；
   - `window.__CLAUDE_SPLASH_ASSET_BASE__`（或 base64 音频表）。
4. 页面、root、窗口三层都设黑色，任何一帧都不会白闪。

### 5.3 splash.js fork 清单（14 项，最小改动）

| # | 位置 | 动作 |
|---|---|---|
| 1 | `:93-101` | 9 个品牌默认值 → §4.1 |
| 2-4 | `:764,769,791` | 硬编码字标 → §4.2 |
| 5 | `:1585-1588` | 身份卡标签 |
| 6-8 | `:26-68` + `:517-528` + `:753,763,768` | 鲸鱼→星芒（§4.3） |
| 9 | `:1551-1576` | `assembleLogo` 适配 stroke，**删除 `strokeWidth='0'`** |
| 10 | `:1050,1066` | `fetch('/dsh-startup/asset/…')` → `assetUrl(name)`（基址可配置） |
| 11 | `:1634` | 终幕语音（TTS 或静音） |
| 12 | `:222-396,1412,1683` | 删 Windows 标题栏探针（macOS 上本来空转，改成 no-op 即可） |
| 13 | `:1407-1675` | 可选：插入 `phase()` 钩子（为将来 overlay/交接留口） |
| 14 | 存储键 | 改 `claude-splash:*`；纯 B 下去重交给 Swift，页面 `mode:'always'` |

### 5.4 素材管线（关键决定：v1 用 base64，不用 custom scheme）

- `splash.js` 用 `fetch()` 读音频，`file://` 下 fetch 不可用 → 两条替代：
  - **v1 推荐 base64**：构建期把 mp3 转 base64 生成 `assets.js`，`atob → ArrayBuffer → decodeAudioData`。零协议、零 CORS、零 MIME 未知数；代价是体积 +33%（254 KB → 340 KB）。
  - P2 再考虑 `WKURLSchemeHandler`（`claude-splash://`）省体积——**注意 MIME 必须按扩展名映射**（`.css→text/css`、`.js→text/javascript`、`.mp3→audio/mpeg`），否则 WKWebView 拒绝加载样式表（这是评审抓到的实打实 bug）。

### 5.5 启动器时序（纯 B）

| 时间 | 事件 | 用户看到 |
|---|---|---|
| t=0 | 全屏无边框窗口（`.screenSaver` 层级、`canBecomeKey`、`hidesOnDeactivate=false`）显示，WKWebView 加载壳 | 纯黑 |
| +80ms | `open -b com.anthropic.claudefordesktop`（**不带任何调试参数**；Claude 已在运行则只激活并退出） | 黑幕 + 星芒/CLAUDE |
| +820–2700ms | 黑幕标识、字距收紧、扫光（DSH 原版节奏） | 动画 |
| +2700ms 起 | 洗白 → 暖白档案底板 → 五步授权 → 终幕 | 完整开屏 |
| 终幕结束 | 优先「透明揭幕」（窗口切透明 + `dsu-handoff` 放大失焦露出 Claude，未验证则回退）；兜底整窗 0.45s alpha 淡出 | Claude 界面 |
| 任意时刻 | Esc / SKIP → 立即收尾淡出；9s/15s/30s 三级看门狗 | — |

- 时长两档：`full`（speed 1，12–18s，两次点击）或 `quick`（speed 1.8，约 6–8s，自动过）。**建议默认 quick**——本机有正在跑的 Claude Code 会话，长时间全屏遮罩会挡住用户干预。
- 只调用 `open`，从不 kill/重启/修改 Claude；任何启动器异常只关自己的窗口。这是「不影响 Claude」的不变量。

---

## 6. 对抗性评审：开工前必须修的坑

评审逐条复核了 8 份报告，抓出 3 处设计内事实错误与 15 项阻塞/高风险项。最关键的：

**P0（不修就踩）**
1. **CDP 相关代码全部降级为二期**：guard 未解除前，任何依赖端口的实现都是死代码；`hybridEnabled` 默认 false。
2. **修 `SplashSchemeHandler` 的 MIME 映射**（若走 custom scheme）——否则壳页面一加载就是裸 HTML。
3. **bridge 必须内联或 `WKUserScript(.atDocumentStart)`**，不能作为第二个 `defer` 脚本（否则抓不到 splash.js 初始化错误）。
4. **长遮罩改默认 quick（4–6s）或每日一次**：本机有运行中的 Code 会话；且 Dock/Spotlight/更新重启等路径根本不经过启动器——产品上接受「开屏是可选彩蛋」。
5. **`assembleLogo` 的 `strokeWidth='0'`**（星芒消失）、**base64 接线**（assets 要放进 `__DSH_STARTUP__.assets` 或 fork 里显式读）、**RUNNING 探针放宽到 5s**——都是实现期就会撞上的具体 bug。

**P1（不改会踩）**：键盘监听残留（splash 结束后 removeEventListener）、`prefers-reduced-motion` 补全（现在只覆盖 3 个动画，全屏闪烁/色散对光敏用户不友好）、多屏黑窗、焦点交还 Claude、Claude 页面 reload/崩溃不补播（写进文档）。

**已被评审修正的设计错误**（如果照着两份设计报告直接写代码会中招）：`C.assets` 字段从未接线；`addScriptToEvaluateOnNewDocument` 会在所有 frame 执行、需要 top-frame 守卫；`waitForDebuggerOnStart` 有永久冻结 renderer 的风险；08 设计的 preview 字段数写错（19 vs 实际 22）；bridge 顺序自相矛盾。

---

## 7. 未验证事项与实测清单

### 7.1 先确认最大的未知数（T1：CDP 守卫，需要你同意后完全退出 Claude 再做）

```bash
osascript -e 'tell application "Claude" to quit'; sleep 2
/Applications/Claude.app/Contents/MacOS/Claude --remote-debugging-port=9222 \
  >/tmp/claude-guard.out 2>/tmp/claude-guard.err; echo "exit=$?"
cat /tmp/claude-guard.err
open -b com.anthropic.claudefordesktop   # 恢复
```

预期：stderr 出现 `Claude: refusing to start — a debugging or network-override switch is present on the command line.`，`exit=1`。若意外的 `exit=0` 且出现 9222 端口 → CDP 路线复活，混合模式可以重新评估。

### 7.2 WKWebView PoC（T12：不碰 Claude，新建最小 Swift 工程）

验证四件事：`file://` 或 custom scheme 下 CSS 是否生效、`fetch` + `decodeAudioData` 能否读 mp3、`speechSynthesis` 是否存在、`Element.animate` 是否可用。这决定 v1 用 base64 还是 scheme、TTS 能否当兜底。

### 7.3 其余未验证项（按优先级）

WKWebView 中 Web Audio 是否必须用户手势（影响第一句台词是否静音）；`drawsBackground` KVC 与透明窗口 + `.screenSaver` 的合成；`.screenSaver` 窗口在多 Space/多屏/全屏 app 上的表现；`CGWindowList` 不带屏幕录制权限时的可见性；`DIN Alternate` 字体是否总在；1P 模式是否也加载本地 SPA（当前按 3P 事实设计）。

---

## 8. 实施路线

| 阶段 | 内容 | 验收 |
|---|---|---|
| **P0（半天）** | 离线壳：从 preview 删面板、补配置/critical CSS/兜底；**Chrome 里 `file://` 打开**，无音频 | 六幕完整播放不崩；Esc/SKIP 生效；结束后 root/锁/overflow 全部还原 |
| **P1（1 天）** | 品牌 fork：字段、硬编码字标、鲸鱼→星芒、`assembleLogo`、CSS 颜色 | 画面无任何 DeepSeek 字样/鲸鱼；星芒画完不消失 |
| **P2（半天）** | 音频：自产 `line-1..6.mp3`；base64 内联；构建校验 | 缺文件不崩、按 hold 走；有文件时第一句之后出声 |
| **P3（1 天）** | 启动器：窗口/时序/桥接/看门狗/多屏/焦点 | t=0 黑屏先于 Claude；任何失败 1.5s 内收窗且 Claude 正常启动；Claude 已运行只激活不重启 |
| **P4（可选）** | 透明揭幕、Reduce Motion、日志、安装脚本、LaunchAgent | 揭幕不露桌面；无卡死 |
| **二期（条件）** | CDP overlay：能力探测、agent、`prewash` 交接、自动回退 | 仅当 T1 显示守卫放开后 |

### 需要你拍板的三个小决策

1. **中文名**：`克劳德` / `安思罗匹克` 都是音译，未见官方中文名。求稳可把黑幕中文也写成 `CLAUDE`（失去一点版式对比）。
2. **身份卡默认值**：名字填你自己的名字，编号 `CLD-0087`，等级 `PRO`——还是想换成别的（比如 `MAX` / 自定义）？
3. **节奏默认档**：完整版（12–18s、两次点击，仪式感强）还是 quick 档（6–8s，不挡事）？

---

## 9. 与你已有材料的关系

- **`Claude Desktop 美化方案调研.md` 的 6.1 节（Swift 启动器骨架）可直接沿用**：无边框窗口、`.screenSaver`、`LSUIElement`、build.sh、ad-hoc 签名全部有效，只需补 `canBecomeKey`、`hidesOnDeactivate=false`、phase 驱动淡出。
- **6.2 节（Theme Agent / CDP 注入）需要更新**：同一守卫也封死了主题注入；主题路线要么等，要么走 ion-dist 补丁（不推荐）。
- **`extras/claude-splash-demo.html` 有两个用途**：它的星芒几何就是 §4.3 的替换来源；它的 3 秒时间轴可以作为「启动器 quick 档」的备选视觉（但那是另一套动画，不是 DSH 引擎）。
- 原调研里「1P 主窗口加载 `https://claude.ai`、3P 加载本地 SPA」的判断与本次勘测一致；但调研写 Claude 是 Electron 42.5.1，本机实际已是 **45.2.1**——版本相关结论以本次勘测为准。

---

## 10. 一句话总结

**这套开屏可以搬进 Claude Desktop，但只能以「外挂启动器」的形态搬——因为 5.11492.2 把 CDP 注入封死了。** 动画引擎零依赖、拿走即用；真正的工作量在品牌 fork（约 20 处文案 + 鲸鱼→星芒 + 一个会擦掉星芒的 `assembleLogo` 坑）和素材管线（base64 + 自产 mp3）。先做纯 B 的最小闭环，混合模式留作将来的条件增强。
