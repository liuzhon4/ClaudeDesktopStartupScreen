# Changelog

## 未发布 — 2026-11-15（开源配置化与设置窗口）

- 默认身份改为中性的 `OPERATOR`；`identity` / `identityId` / `accessLevel` 支持空字符串隐藏对应内容
- 新增 `voiceGreeting`、`welcomeTemplate` 与三个身份卡标签配置；欢迎文案和语音支持 `{identity}` 占位符
- 终幕语音改用可配置文本 + 系统 TTS，不再播放含固定个人名的烘焙 `line-6` 素材
- Swift 注入改为完整 JSON 配置对象；新增 JS 配置键不再需要逐字段修改注入代码
- 新增原生设置窗口：双击 `claude-splash-settings.command` 或按住 Option 启动；只写自己的 config.json，不启动 Claude
- 开源准备：个人名纳入源码残留检查；本地工具状态、原始调研、录屏与备份不进入公开仓库
- 应用图标改为原创「C 形窗口 + 启动条」，新增 SVG 母版并重建完整 ICNS；不再使用官方星芒图标
- 新增 `NOTICE` 与 `tools/package-release.sh`：Release 包含完整音频、管理脚本、许可和首次打开说明；当前为 arm64 ad-hoc 包

## 未发布 — 2026-11-14（全项目审计修复）

- 身份卡：`identityId: "auto"` 显示当天日期（本地时区 `YYYYMMDD`）；`accessLevel: "auto"` 显示最近 Code 会话的模型与 effort（如 `FABLE 5 · MAX`），读不到回退 `PRO`
- 监听器：修复屏幕参数变化重建黑幕时的过度释放崩溃（程序化 `NSWindow` 默认 `isReleasedWhenClosed=true`，ARC 下 `close()` 会二次释放）；该崩溃会触发 KeepAlive 重启，使 20s 启动宽限反复吞掉 Claude 启动、开屏不出现
- 新增受控只读：`Claude*/claude-code-sessions/**/local_*.json` 的 `model` / `effort` / `lastFocusedAt` / `isArchived`（不读 title 或会话内容），AGENTS/CLAUDE 红线条款已同步
- 审计：7 维度并行 + 三视角对抗复核 + 补漏，确认 50 条问题，报告见 `docs/audit-report-2026-11-14.md`
- 修复 CSS 全局 reset 特异性事故：`#dsh-startup-root *` 压掉 17 处组件 margin/padding（按钮内边距、欢迎框、星芒间距全部归零），改为 `:where()`
- 修复互动步骤 520ms 输入死区：按钮出现后立即挂监听；同一 click 事件不会误触下一步
- `.dsu-black` 与进度条/声纹/页脚/四角/扫描线不再拦截鼠标
- 启动器：实现 `webViewWebContentProcessDidTerminate`（不再整段重播/黑屏卡死）；单实例保护；所有直通出口补发 `splash.done`；5s 探针 eval 失败不再误杀；fadeOut 兜底拉起 Claude；日志 2MB 轮转
- 监听器：尊重 `DISABLED` 与 `enabled=false`；屏幕热插拔重建黑幕后重挂 3 秒超时；日志 2MB 轮转
- 脚本：watch-on 改 bootout → enable → bootstrap 并用 `launchctl print` 验证（修复 off 之后重装静默失效）；watch-on 删除 DISABLED；off 改用 `open -b` 并以 bundle id 验证 Claude；uninstall 确认监听器停止后再删 app
- build.sh 显式 `-target $(uname -m)-apple-macos13.0`，与 `LSMinimumSystemVersion` 一致
- 文档：README 时序/目录/文案同步（speed=1.0 含语音实测约 22s）、文档索引加入审计报告；《备份与恢复方案》按 ClauEd + 原生 watcher 重写；三份设计/调研文档加「历史存档」警示
- 引擎：`dispose()` 取消收尾定时器；结束后音频闸门（Esc 后不再补播音效）；默认身份与 splash.html 同步（Edward / always）
- 项目结构：文档收拢到 `docs/`（含审计报告与原始调研）、构建输入（`Info.plist` / `watcher-Info.plist` / `AppIcon.icns`）收拢到 `resources/`、根目录 demo 移入 `extras/`；新增 `tools/verify.sh`（`make check`）、`Makefile`、`.editorconfig`

## 未发布 — 2026-11-13

- 应用更名为 **ClauEd**（bundle id `local.claued.splash`），构建产物为 `ClauEd.app`
- 图标改为白底橘色星芒（原橘底白色星芒对调），与 Claude 官方图标区分
- 六句台词全部改用 en-GB SoniaNeural（英音）重新生成，统一 EQ / 早期反射 / 房间底噪；终幕为 `Edward, Welcome to Anthropic's Claude. It's been a while.`（句间停顿 1.0s）
- 进度条改为 rAF 连续推进；恢复第 1、2 步的两下点击
- 终幕黑框文案改为 `CLAUDE`；身份改为 Edward
- 性能：移除收尾全屏 blur；扫光 / 扫描线 / 光条 / 语音电平均值动画改为 transform；光晕层缩小并修正居中；按钮呼吸改为边框伪元素
- 稳定性：硬截止 30s → 120s；新增 8s 导航超时；Claude 启动延后到 1.6s；跳过 / 揭幕时停止 WebAudio
- 启动：音频错峰解码；素材模式跳过 speechSynthesis 预热；十六进制瀑布改用 textContent
- 维护：移除 Windows 专用标题栏同步死代码；配置枚举校验；卸载脚本覆盖 /Applications
- 新增可选「Claude 启动监听」：原生 `ClauEdWatcher.app` 用 NSWorkspace 事件监听 Claude 冷启动，立刻铺全屏黑幕再拉起开屏；LaunchAgent `local.claued.watch` 保活，附安装与关闭脚本

## 1.0.0 — 2026-11-13

首个可用版本。

- 移植 `dsh-startup-screen`（MIT，© 沈宏宏）六幕开屏引擎到 Claude Desktop 外挂启动器
- 品牌替换：Claude 星芒（12 射线 stroke）、`CLAUDE / ANTHROPIC` 品牌块、黑幕 `CLAUDE / ANTHROPIC / CLAUDE DESKTOP`、身份「豪叔」、页脚 `POWERED BY ANTHROPIC`
- 自动主题：读取 Claude `userThemeMode` → macOS 系统外观 → 配置覆盖；暗色洗白/闪白/故障混合模式适配
- 音频：复用原素材（8 个 mp3），base64 内联 + `decodeAudioData`，兼容 `file://`
- 安全：Shift/Esc 跳过、DISABLED 标记、5s/30s 看门狗、`done` 事件 + finished 轮询、关闭/卸载脚本
- 应用：`ClauEd.app`，图标沿用官方 Claude Desktop，ad-hoc 签名
- 修复：`dsh-startup:done` 在 `window` 上派发、桥接误监 `document` 导致 30s 硬截止才收窗
- 文档：README / AGENTS / CLAUDE / 备份与恢复 / 移植评估 / 方案 v2
