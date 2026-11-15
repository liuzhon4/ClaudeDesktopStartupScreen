<div align="center">
  <img src="extras/AppIcon-preview.png" width="160" alt="ClauEd icon">
  <h1>ClauEd</h1>
  <p><strong>Claude Desktop Startup Screen for macOS</strong></p>
  <p>为 Claude Desktop 加一段六幕 DSH 风格开屏：原生 Swift 启动器，不修改官方应用。</p>
  <p>An unofficial, standalone startup-screen launcher for Claude Desktop on macOS.</p>
</div>

## 致敬与来源

特别致敬 **沈宏宏** 的 [dsh-startup-screen](https://github.com/6shenhonghong9/dsh-startup-screen)。

**这个原项目就是 ClauEd 的动画引擎来源。** 六幕时间线、技术档案式视觉和大量交互细节都建立在原作品的 MIT 源码之上；ClauEd 在其基础上完成了 Claude Desktop 品牌化、双主题适配、macOS 原生启动器、配置窗口与发布打包。感谢原作者把这些设计和实现开源。

## 我的工具链

**Claude Desktop Gateway + CC Switch + DeepSeek**

这是作者当前搭配 ClauEd 使用的桌面工具链，仅作为项目背景与使用环境记录。它们**不是 ClauEd 的安装依赖**；ClauEd 不修改这些工具，也不要求用户安装或配置其中任何一项。

## 特性

- 六幕动画、亮色/暗色双主题、语音与界面音效
- 用户名称、会话编号、访问等级、欢迎文案与身份卡标签均可配置
- 独立原生设置窗口，无需手动编辑 JSON
- 可选 Claude 冷启动监听：仍然从 Dock 里的官方 Claude 入口启动
- Shift / Esc 跳过，配置开关、外部关闭脚本和多层超时兜底
- 不修改 Claude.app、不注入、不挂调试端口、不设置全局环境变量

**运行要求：** macOS 13 或更高版本；已安装 Claude Desktop（bundle id `com.anthropic.claudefordesktop`）。当前 Release 为 Apple Silicon（arm64）构建；Intel Mac 请从源码构建。

## 下载与使用

1. 从 [Releases](https://github.com/liuzhon4/ClaudeDesktopStartupScreen/releases) 下载最新的 `ClauEd-*-macOS-arm64.zip` 并解压。
2. 把 `ClauEd.app` 拖入 `/Applications`。
3. **首次打开时在 Finder 中右键 `ClauEd.app` →「打开」→ 再点「打开」。** 当前 Release 使用 ad-hoc 签名，未购买 Apple Developer ID 公证，因此可能有 Gatekeeper 提示。
4. 之后双击 ClauEd：播放开屏，然后自动进入官方 Claude。

Release 已包含音频、原生监听器和设置功能，**不需要安装 Xcode、Python 或命令行工具**。

> ClauEd 是独立启动器，不是 Claude 的插件。直接打开官方 Claude 始终可用；不安装启动监听时，官方入口不会播放开屏。

## 设置

双击 Release 包中的 `claude-splash-settings.command`，或按住 **Option** 启动 ClauEd。

设置模式只打开原生配置窗口，不播放开屏、不启动 Claude。保存后下次启动生效。

配置文件位于：

```text
~/Library/Application Support/ClaudeSplash/config.json
```

| 键 | 默认值 | 说明 |
|---|---|---|
| `enabled` | `true` | 开屏总开关；关闭后只打开 Claude |
| `displayMode` | `"always"` | `always` 每次 / `daily` 每天最多一次 |
| `themeOverride` | `"auto"` | `auto` / `light` / `dark` |
| `darkWash` | `"soft"` | 暗色过场：`soft` 暗房亮起 / `faithful` 原版过曝 |
| `speed` | `1.0` | 0.35–3；压缩段落停顿，不改变语音速度 |
| `requireInteraction` | `true` | 第 1、2 步等待按钮、Enter 或 Space |
| `voice` / `sound` | `true` | 人声 / 界面音效 |
| `identity` | `"OPERATOR"` | 用户名称；留空隐藏名称与终幕身份行 |
| `identityId` | `"auto"` | 会话编号；`auto`/`date` 为当天日期，固定文本为静态代号，留空隐藏 |
| `accessLevel` | `"auto"` | 访问等级；`auto` 显示最近 Code 会话模型，固定文本手动覆盖，留空隐藏 |
| `welcomeTemplate` | `"欢迎 {identity} 访问"` | 终幕画面文案；支持 `{identity}` |
| `voiceGreeting` | `"Welcome to Anthropic's Claude. It's been a while."` | 终幕英文 TTS；支持 `{identity}` |
| `labelIdentity` | `"用户名称"` | 身份卡标签 |
| `labelIdentityId` | `"会话编号"` | 身份卡标签 |
| `labelAccessLevel` | `"访问等级"` | 身份卡标签 |
| `splashOnActivate` | `true` | Claude 已运行时是否也播放开屏 |

### 隐私边界

主题自动模式只读取 Claude `config.json` 中的 `userThemeMode`。

`accessLevel: "auto"` 会读取 `Claude*/claude-code-sessions/**/local_*.json` 中的 `model`、`effort`、`lastFocusedAt`、`isArchived`，用于显示最近会话的模型名。**不读取标题或会话内容。** 把访问等级设为固定文本或留空即可完全禁用这项读取。

ClauEd 不联网，不上传配置或遥测数据。

## 从 Dock 里的 Claude 启动（可选）

安装监听后，可以只保留官方 Claude 图标：

1. 确保 `ClauEd.app` 位于 `/Applications`。
2. 双击 `claude-splash-watch-on.command`。
3. 退出 Claude，再从 Dock 打开 Claude。监听器会先铺黑幕，再接入开屏。

监听由独立 `ClauEdWatcher.app` 和 LaunchAgent `local.claued.watch` 实现。关闭监听或停用开屏，双击 `claude-splash-off.command`。

## 跳过、关闭与卸载

| 操作 | 方法 |
|---|---|
| 跳过本次启动 | 启动时按住 **Shift** |
| 跳过正在播放的开屏 | **Esc**；Cmd+Q 也可退出启动器 |
| 安全关闭 | 双击 `claude-splash-off.command` |
| 卸载 | 双击 `claude-splash-uninstall.command`；会将 ClauEd 移入废纸篓并删除自己的配置 |
| 绕过 ClauEd | 直接打开官方 `/Applications/Claude.app` |

更多诊断见 [备份与恢复方案](docs/备份与恢复方案（Safe%20Mode%20·%20外部关闭）.md)。

## 从源码构建

只有自行构建才需要 Xcode Command Line Tools、Swift 和 Python 3；普通 Release 用户不需要。

```bash
git clone https://github.com/liuzhon4/ClaudeDesktopStartupScreen.git
```

```bash
cd ClaudeDesktopStartupScreen
```

```bash
./build.sh
```

```bash
open ClauEd.app
```

完整自检：

```bash
./tools/verify.sh
```

自检覆盖构建、macOS 13 部署目标、离屏 WKWebView、音频键数、配置一致性和文档链接。

浏览器预览：

```bash
./build.sh
```

```bash
python3 -m http.server 8765 --bind 127.0.0.1
```

打开 `http://localhost:8765/fork/splash.html?theme=dark&speed=2&voice=0&sound=0&interact=0`。还支持 `identity`、`identityId`、`accessLevel`、`voiceGreeting`、`welcomeTemplate` 和三个标签参数的 URL 覆盖。

## 制作 Release

```bash
./tools/package-release.sh 1.1.0
```

产物写入 `dist/`：包含应用、设置/监听/关闭/卸载脚本、README、LICENSE 和 NOTICE 的 ZIP，以及 SHA-256 校验文件。

当前打包脚本使用 ad-hoc 签名。若以后使用 Developer ID，请先完成签名、公证和 stapler 验证，再替换 Release 产物；不要把证书、Keychain 凭据或 notarytool 密码写入仓库。

## 项目结构

```text
src/main.swift          启动器、配置注入、窗口与安全看门狗
src/settings.swift      原生设置窗口
src/watcher.swift       Claude 冷启动监听器
fork/splash.js          六幕引擎（上游 MIT fork）
fork/splash.css         双主题样式
fork/splash.html        本地壳页面与浏览器预览入口
assets/                 语音与音效源文件
resources/              Info.plist、原创 SVG 图标与 ICNS
extras/                 配置示例、试听音频与实验页面
tools/                  构建、探针、自检与 Release 打包工具
docs/                   整理后的设计、审计与恢复文档
```

原始调研报告、本机工具状态、录屏、备份和构建产物不进入公开仓库。

## 文档

- [项目规则与代码地图](AGENTS.md)
- [更新记录](CHANGELOG.md)
- [全项目审计报告](docs/audit-report-2026-11-14.md)
- [Claude Desktop 开屏移植评估](docs/Claude%20Desktop%20开屏移植评估.md)
- [开屏方案 v2](docs/开屏方案%20v2（暗色自适应%20·%20音频复用%20·%20豪叔）.md)
- [备份与恢复方案](docs/备份与恢复方案（Safe%20Mode%20·%20外部关闭）.md)

## 许可与致谢

- 动画引擎 fork 自 [dsh-startup-screen](https://github.com/6shenhonghong9/dsh-startup-screen)（© 沈宏宏，MIT）；本项目的源代码修改同样以 MIT 发布，见 [LICENSE](LICENSE)。
- 音频、原创应用图标和商标不属于 MIT 的自动覆盖范围；音频再分发权已由维护者确认，详细边界见 [NOTICE](NOTICE)。
- 新图标是原创的「C 形窗口 + 启动条」，不使用 Claude Desktop 官方图标或星芒素材。

**ClauEd 是非官方独立项目，与 Anthropic 无隶属、赞助或背书关系。Claude / Anthropic 名称与相关商标归其权利人所有。**
