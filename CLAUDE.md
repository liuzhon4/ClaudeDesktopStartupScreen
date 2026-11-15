# CLAUDE.md

本仓库的完整说明见 [AGENTS.md](AGENTS.md)（编码代理必读）。这里只放最短要点。

## 项目

ClauEd：macOS 外挂启动器，为 Claude Desktop 播放 DSH 风格开屏。Swift + 原生 HTML/CSS/JS，产物 `ClauEd.app`。

## 常用命令

```bash
./build.sh                                   # 构建（含 base64 音频生成 + ad-hoc 签名）
swift tools/wk_probe.swift fork/splash.html  # 离屏 WKWebView 冒烟
python3 -m http.server 8765 --bind 127.0.0.1 # 浏览器预览 fork/splash.html?theme=dark&speed=2&voice=0&sound=0
./claude-splash-settings.command             # 原生设置窗口（不启动 Claude）
```

## 不可违反

- 不修改 `/Applications/Claude.app` / 其签名 / Claude 数据目录；只读 `config.json` 的 `userThemeMode`，以及 Code 会话元数据的 `model`/`effort`（不读会话内容）。
- 对 Claude 只用 `open -b com.anthropic.claudefordesktop`，不传任何参数、不设环境变量。
- 音频必须走 `window.__CLAUDE_SPLASH_AUDIO__`（base64）；事件 `dsh-startup:done` 派发在 `window` 上。
- 星芒是 stroke，`assembleLogo()` 不能把 `strokeWidth` 归零。
- 品牌字段两处同步：`fork/splash.js` DEFAULTS 与 `fork/splash.html` 默认配置。
- 安全开关（Shift / DISABLED / 看门狗 / 双击关闭脚本）必须保留。

## 文档

- [README.md](README.md) 用户手册
- [AGENTS.md](AGENTS.md) 项目规则与代码地图
- [备份与恢复方案（Safe Mode · 外部关闭）.md](docs/备份与恢复方案（Safe%20Mode%20·%20外部关闭）.md) 关闭/恢复
