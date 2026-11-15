# ClauEd 全项目审计报告

生成方式：7 个维度并行审计（Swift 启动器 / Swift watcher / splash.js / splash.css / 构建与脚本 / 文档一致性 / 跨文件集成），每条发现经反驳、复现、影响三视角独立复核，三票中两票确认才计入；最后经完备性评审补漏一轮。

## 汇总

确认 50 条（P0 1 / P1 7 / P2 26 / P3 16），复核否决 1 条。

### 1. [P0] claude-splash-off 第 45 行用 `open -a Claude` 按应用名启动，违反 P0 约束

- 位置：`claude-splash-off.command:45`（维度：gap:claude-splash-off.command 第 5 步（45–47 行）对 Claude 的启动与健康验证；claude-splash-uninstall.command:6 会先调用它）
- 详情：claude-splash-off.command:44-45 的 5/5 验证步骤执行 `open -a Claude`：`-a` 按应用显示名经 LaunchServices 解析，不是硬约束要求的 bundle id。项目唯一合规实现是 src/main.swift:395-398 的 `/usr/bin/open -b com.anthropic.claudefordesktop`（watcher 也按 bundle id 判断，见 src/watcher.swift:13/113），而这条按名启动路径同时存在于 off 和 uninstall（claude-splash-uninstall.command:7 先调用 off）两条流程中。CLAUDE.md:20、AGENTS.md:18、README.md:14 把“只用 open -b com.anthropic.claudefordesktop”定为 P0；第 47 行的 `pgrep -x Claude` 也无法区分最终起来的是哪个 Claude。
- 失败场景：机器上存在第二份名为 Claude 的 app（旧备份/下载目录里的旧版本 Claude.app、改名或改签的副本、或任何第三方同名 app）时，`open -a Claude` 由 LaunchServices 按名字挑选，可能启动旧副本而非 /Applications/Claude.app：旧版/改签副本可能直接起不来，或使用另一份数据目录，而官方 com.anthropic.claudefordesktop 从未被启动；若该副本进程名同为 Claude，第 47 行还会报“Claude 正在运行”。用户刚执行“安全关闭/卸载”，以为官方 Claude 已被验证可打开，实际验证对象是错误副本。若官方 app 被移动或改名，`open -a` 还可能找不到/找错，而 `open -b` 可按 bundle id 正确解析。
- 修法：第 45 行改为 `open -b com.anthropic.claudefordesktop`（与 src/main.swift:395-398 一致），并检查其退出码。
- 票数：3

### 2. [P1] 关闭监听后再开启会静默失效：off 写入的 disabled 状态使 watch-on 的 bootstrap 报 119，脚本仍打印 ✅

- 位置：`claude-splash-watch-on.command:57`（维度：watcher-swift）
- 详情：claude-splash-off.command:23-24 对 gui/$UID/local.claued.watch 执行了 launchctl disable——该状态写进 launchd 的持久 override 库，跨重启保留。重新开启时 claude-splash-watch-on.command:56-58 的执行顺序是 bootout → bootstrap → enable，且三步全部 2>/dev/null 吞掉错误、第 60 行无条件打印「✅ 原生监听器已安装」，从不检查 launchctl print 的实际结果。对处于 disabled 的 label，launchctl bootstrap 会以「Bootstrap failed: 119: Service is disabled」失败；随后的 launchctl enable 只清除 disabled 标记，并不会把服务加载起来。
- 失败场景：按 README 的流程用 off 关闭监听（它 disable 了 label 并把 plist 改名备份），之后再次双击 watch-on 想恢复：bootout 因路径已变而无操作，bootstrap 因 disabled 状态报 119 被吞，enable 只清标记不加载，脚本显示成功。实际 watcher 根本没在运行——退出 Claude 再点 Dock 只得到裸启动，无黑幕无开屏，~/Library/Logs/ClauEdWatcher.log 也不会出现新的「watcher started」行；要等到下一次登录 launchd 才重新加载该 agent。用户会误判监听器损坏，若再跑一次 off 又会把下一个登录周期也关掉。
- 修法：改成 bootout → launchctl enable gui/$UID/local.claued.watch → bootstrap（失败时 enable 后再 bootstrap 一次），并用 launchctl print 验证 state=running 后才打印成功。
- 复核修正：主体属实，行号准确（watch-on:57 即 bootstrap 行，off:24 即 disable 行）。两处细节修正：(a) watch-on:56 的 bootout 指向第 35-54 行刚重写出的 $PLIST 路径，无操作的真实原因是服务已被 off bootout 且未重新加载（bootout 报错被 2>/dev/null 吞掉），不是"路径已变"；(b) 第 58 行 enable 会清除持久 disabled 标记，故同一会话内第二次运行 watch-on 可成功，或下一次登录自动恢复——失败范围是"off 之后的第一次 watch-on 静默不生效"，描述中"要等下一次登录"仅在用户不重试时成立。给定可选功能、可自愈、不触及任何 P0 硬约束，严重度我评为 P2。
- 票数：3

### 3. [P1] 全局 reset `#dsh-startup-root *` 特异性压过所有组件规则，19 处 margin/padding 全部失效（按钮/欢迎框/中央排版/身份卡）

- 位置：`fork/splash.css:19`（维度：splash-css）
- 详情：fork/splash.css:14-21 的 `#dsh-startup-root * { margin:0; padding:0 }` 带 1 个 ID，特异性 (1,0,0)，高于文件中所有 `.dsu-*` 规则的 (0,n,0)，导致组件规则的间距声明全部被压成 0：`.dsu-btn{padding:13px 26px}`(538)、`.dsu-w2{padding:7px 16px 8px}`(656) 与 `margin-top:12px`(653)、`.dsu-w3{margin-top:30px}`(663)、`.dsu-w4{margin-top:20px}`(678)、`.dsu-sub-en{margin-top:14px}`(379)、`.dsu-rule{margin-top:22px}`(392)、`.dsu-logo{margin-top:26px}`(402)、`.dsu-logolabel`(420)、`.dsu-dots`(428)、`.dsu-brand-2`(308)、`.dsu-black .dsu-mark{margin-bottom:18px}`(200)、`.dsu-black-en`(211)、`.dsu-black-sub`(225)、`.dsu-card{padding:2px 0}`(599)、`.dsu-card-row{padding:8px 2px}`(611)、`.dsu-skip{padding:5px 10px}`(974)、`.dsu-hint kbd`(587-588)。已用真实 splash.css 在离屏 WKWebView 实测：上述元素 computed padding/margin 全部为 0px（例如 .dsu-btn padding-top=0px、.dsu-w2 padding-top=0px/margin-top=0px、.dsu-card-row padding-top=0px）。已安装 /Applications/ClauEd.app 内资源与源码 MD5 完全一致，线上同样生效。
- 失败场景：每次开屏固定出现：终幕 `.dsu-w2` 的 CLAUDE 色块没有 7/16/8px 内边距，底色直接贴住字形，并与上一行 WELCOME TO 零间距；w3/w4 的 30px/20px 间距也丢失，四行欢迎文案与星芒全部贴在一起。第 1、2 步唯一的操作按钮 `.dsu-btn` 失去 13px×26px 内边距，点击热区从约 46px 高缩到约 21px（离屏实测同结构 .dsu-skip 只剩 15px 高），视觉上只剩 1.5px 边框紧包文字。第 2–5 步中央区状态行/英文副标题/分隔线/星芒之间 14/22/26px 间距全为 0，星芒紧贴分隔线；第 1 幕标识与 CLAUDE 大字之间只剩 flex gap 2px。
- 修法：把 reset 改为 `:where(#dsh-startup-root) *`（特异性归零），或把组件规则统一提升为 `#dsh-startup-root .dsu-*`。
- 复核修正：原描述基本准确，仅两处措辞可精确化（不影响结论）：(a) 重置规则体位于 fork/splash.css:14-21，`margin:0`/`padding:0` 在第 19/20 行，位置行号"19"可接受；(b) ".dsu-* 规则的 (0,n,0)" 是简化说法，实际 `.dsu-hint kbd` 为 (0,1,1)、`.dsu-black .dsu-mark` 为 (0,2,0)，但仍全部低于重置的 (1,0,0)，结论不变。另补充一次实测快照细节：`.dsu-btn` 在文字尚未填入时高度为 3px（仅剩 1.5px 上下边框），填入文字后约为 21px，与原描述"约 21px"一致。
- 票数：3

### 4. [P1] 《备份与恢复方案》仍是 EdClaude 时代的旧方案稿，文档里的恢复命令全部失效

- 位置：`备份与恢复方案（Safe Mode · 外部关闭）.md:60`（维度：docs-consistency）
- 详情：README.md:48/108 把该文档当作现行关闭与诊断手册，但文档第 4 行仍写「状态：方案稿，未改代码」，全篇是改名前的 EdClaude：第 60/80/87 行用 LaunchAgent `local.edclaude.splash`，第 78/145/171 行用 `EdClaude.app/Contents/MacOS/EdClaude` 做 pkill/ps，第 126 行卸载路径为 `EdClaude.app`；第 137 行承诺的 .sh 版本在仓库中不存在（只有 .command）；第 151 行让用户配 `mode: once-per-day`，而实际配置键是 `displayMode: "daily"`（src/main.swift:48、README.md:67）；第 197-204 行验收项还是未勾选状态。实际交付的 claude-splash-off.command:6-9、23-28 用的是 ClauEd 路径并 bootout `local.claued.watch`，与文档内嵌脚本完全不同。
- 失败场景：开屏卡黑屏时，用户按 §0/§5 执行 `pkill -f "EdClaude.app/Contents/MacOS/EdClaude"`，或按 §3 L2 执行 `launchctl bootout ... local.edclaude.splash.plist`：进程名和 plist 都不存在，ClauEd 与 local.claued.watch 都不会被停掉，黑幕/开屏继续；照 §4.1 抄脚本也停不掉 watcher，下次 Claude 启动仍自动弹开屏。
- 修法：按当前 claude-splash-off.command / claude-splash-uninstall.command 重写该文档（ClauEd 路径、local.claued.watch、displayMode），或删掉内嵌脚本改为指向仓库里的 .command。
- 复核修正：核心事实全部成立，仅作少量校正：(a) 未勾选验收项实为第 198-204 行（描述写 197-204，197 为空行/引言）。(b) 第 171 行是 `ps aux | grep -i "EdClaude.app"`，不含完整 MacOS 路径；完整路径 `EdClaude.app/Contents/MacOS/EdClaude` 出现在第 78 和 145 行。描述漏掉的同类失效点：第 11 行 Cmd+Opt+Esc 强制退出名为「EdClaude」（实际应用名 ClauEd）；第 170 行 `launchctl list | grep -i splash` 无法发现 `local.claued.watch`；§4.2 内嵌卸载脚本（第 126 行）只移动 `$(dirname $0)/EdClaude.app`，从不处理 `/Applications/ClauEd.app`，而实际交付的 claude-splash-uninstall.command:10-17 会同时处理仓库目录与 /Applications 两份。(c) 「照 §4.1 抄脚本也停不掉 watcher，下次 Claude 启动仍自动弹开屏」需细分：内嵌 §4.1 脚本仍会 touch DISABLED（第 95-98 行），src/main.swift:222-224 会让 ClauEd 直通，因此抄脚本后下次冷启动不会播开屏动画，但 watcher 仍在、黑幕仍会铺约 3 秒（watcher.swift:17 kCoverTimeout=3.0，265-267 超时收起）且 ClauEd 仍被拉起；「仍弹开屏」严格成立的是只执行 L2/pkill（未写 DISABLED）的路径。(d) 风险边界：用户若直接双击真实交付的 claude-splash-off.command（README:104 指向的文件）是正常工作的（它会停 `local.claued.watch`），坏的是文档内嵌脚本与 §3 L2/§5/§6 的终端命令；且 §0 第一步 Esc（src/main.swift:274-276）仍是有效逃生。这使严重度可争议为 P2，但鉴于该文档是 README/CLAUDE.md 指定的恢复手册，在「黑屏卡住」这一文档专门要解决的场景下终端命令全部失效，维持 P1 合理。
- 票数：3

### 5. [P1] off 之后再跑 watch-on 无法重新装载监听：bootstrap 在 enable 之前执行且错误被吞

- 位置：`claude-splash-watch-on.command:57`（维度：integration）
- 详情：claude-splash-off.command:24 会执行 `launchctl disable gui/$(id -u)/local.claued.watch`；man launchctl 明确规定服务一旦被 disable，“cannot be loaded in the specified domain until it is once again enabled”，且状态跨重启持久。而 claude-splash-watch-on.command:56-58 的顺序是 bootout → bootstrap → enable：bootstrap 面对 disabled 服务会被 launchd 拒绝，本行 `2>/dev/null` 把错误吞掉，脚本仍打印“✅ 原生监听器已安装”。随后的 enable（第 58 行）只清除禁用标记，不会把已有 plist 加载进 gui/$(id -u)（LaunchAgents 只在登录时被扫描），watcher 进程根本不会启动。
- 失败场景：用户按文档双击 claude-splash-off.command 关闭一次（或任何之前跑过 off 的机器），之后想恢复监听再双击 watch-on：脚本提示安装成功，但 `launchctl print gui/$(id -u)/local.claued.watch` 会报不存在；退出 Claude 再点 Dock 里的 Claude 既没有黑幕也没有开屏，直到注销/重启才恢复。用户会误判为监听功能坏了。
- 修法：把 `launchctl enable` 挪到 `launchctl bootstrap` 之前，并在 bootstrap 后用 `launchctl print`/`launchctl list` 校验，失败时报错退出。
- 复核修正：机制与行号（off:24、watch-on:56-58）均准确，但失败场景结尾"直到注销/重启才恢复"不成立：claude-splash-off.command:31-34 还会创建 `~/Library/Application Support/ClaudeSplash/DISABLED`（第 33 行 touch），claude-splash-watch-on.command 从不删除它，而 src/main.swift:222-227 检测到该标记时直接 openClaude 并退出（pass-through）。因此注销/重启后 watcher 进程会因 enable 已生效而被 launchd 加载，但 ClauEd 仍会直通——最多闪一下黑幕，开屏永远不播，直到用户手动删除 DISABLED。准确描述：(1) off 后首次跑 watch-on，本次会话 watcher 完全未加载（bootstrap 被 disabled 拒绝、错误被吞、却打印安装成功），冷启动 Claude 无黑幕无开屏；(2) 注销/重启不会恢复开屏，因为 off 留下的 DISABLED 标记会挡住 ClauEd（这是同一恢复路径上的第二个独立缺陷）；(3) launchd 这一半可被"再双击一次 watch-on"修复（第一次的 enable 已清除 override），但脚本没有提示，且 DISABLED 标记仍需单独删除。
- 票数：3

### 6. [P1] off 的成功判定 `pgrep -x Claude` 无法证明 open 成功，且脚本恒以 0 退出

- 位置：`claude-splash-off.command:47`（维度：gap:claude-splash-off.command 第 5 步（45–47 行）对 Claude 的启动与健康验证；claude-splash-uninstall.command:6 会先调用它）
- 详情：claude-splash-off.command:47 用 `pgrep -x Claude` 作为“验证 Claude 可正常打开”的判据，但 pgrep -x 只比对进程 basename：无法区分本次 open 拉起的进程、运行前就已存在的进程、还是另一份同名副本。同时第 45 行 `open -a Claude` 的退出码完全未检查——脚本只有 `set -u`（第 4 行），没有 set -e/trap，且最后执行的语句是 if/else 分支里的 echo，因此 off 无论验证是否失败都恒定 exit 0。claude-splash-uninstall.command:7 直接调用 off 并在 :18-19 无条件 `rm -rf` 配置、打印“完成。官方 Claude 不受影响。”，off 的失败无法通过退出码向上传播。
- 失败场景：状态 1：Claude 在脚本运行前已在运行（用户发现开屏异常后重跑 off 做“验证”很常见）——`open -a Claude` 只是激活或直接失败，pgrep 必然命中旧进程，脚本打印“Claude 正在运行”，实际没有验证任何事；若 Claude 此时处于卡死/拒绝开窗状态，用户会被误导为“官方 Claude 已验证正常”。状态 2：Claude 被改名/未安装，`open -a Claude` 以非 0 退出，pgrep 失败仅打印警告，off 仍以 0 退出；uninstall 第 7 行照常继续，把 ClauEd 挪进废纸篓并删掉配置后输出“完成”，双击运行或自动化调用方从退出码上看不到任何失败。状态 3：pgrep 命中的是另一份同名 Claude 副本进程，同样误报成功。
- 修法：改用 `open -b com.anthropic.claudefordesktop` 并检查其退出码，再按进程完整路径（如 `pgrep -f '/Applications/Claude\.app/Contents/MacOS/Claude'`）而非进程名判定，验证失败时 `exit 1`；uninstall 检查该退出码后再继续删除。
- 票数：3

### 7. [P1] 存档调研仍把含 --remote-debugging-port 的启动骨架标为可直接沿用，并保留 launchctl setenv REACT_PROFILE 配方

- 位置：`Claude Desktop 美化方案调研.md:273`（维度：gap:被 CLAUDE.md:31 列为「设计依据」的文档仍含硬约束禁止的 Claude 启动/环境命令：Claude Desktop 开屏移植评估.md:234,271、开屏方案 v2…md:217、Claude Desktop 美化方案调研.md:126,351,430,547）
- 详情：§6.1 的 Swift 骨架第 273 行是 `p.arguments = ["-a", "Claude", "--args", "--remote-debugging-port=9222"]`，同文件 126/351/430/601 行也反复给出 `open -a Claude --args --remote-debugging-port=9222`；第 547 行的 `launchctl setenv REACT_PROFILE 1` 与 557-570 行的登录 LaunchAgent 仍是可直接复制的安装配方。顶部第 5 行的存档横幅只声明 CDP／调试端口路线被 guard 封死，没有声明 `REACT_PROFILE` 环境变量路线同样被 AGENTS.md:19 禁止；而 CLAUDE.md:31 列为设计依据的《Claude Desktop 开屏移植评估.md》第 307 行明写「美化方案调研.md 的 6.1 节（Swift 启动器骨架）可直接沿用」，README.md:179 也把它列入文档索引，所以它仍会被当作可用材料读取。此内容与 AGENTS.md:18/19、CLAUDE.md:20 的硬约束冲突。
- 失败场景：维护者按《评估》§9 复制 6.1 骨架时，启动器会在 +80ms 用 `open -a Claude --args --remote-debugging-port=9222` 拉起 Claude：当前 5.11492.2 的 guard 让 Claude 打印拒绝信息并 exit 1，开屏照常播完淡出，而 Claude 根本没有启动；若 guard 在后续版本失效，Claude 则带本机 CDP 控制端口运行。照 §6.4 执行还会注册登录级 LaunchAgent 常驻 `REACT_PROFILE=1`，此后 Claude 每次启动都加载第三方扩展，普通卸载脚本不会清理该变量——正是《备份与恢复方案》§4.1 点名要清理的污染通道。
- 修法：删除或改写 6.1-6.4 的启动与安装命令，统一为不带参数的 `open -b com.anthropic.claudefordesktop`，并把 launchctl setenv / REACT_PROFILE 段落明确标注为禁止实施。
- 票数：3

### 8. [P1] 设计依据文档仍给出用 --remote-debugging-port 直接启动 Claude 的 T1 实测步骤

- 位置：`Claude Desktop 开屏移植评估.md:268`（维度：gap:被 CLAUDE.md:31 列为「设计依据」的文档仍含硬约束禁止的 Claude 启动/环境命令：Claude Desktop 开屏移植评估.md:234,271、开屏方案 v2…md:217、Claude Desktop 美化方案调研.md:126,351,430,547）
- 详情：§7.1（264-272 行）给出的 T1 步骤是：先 `osascript -e 'tell application "Claude" to quit'`，再直接执行 `/Applications/Claude.app/Contents/MacOS/Claude --remote-debugging-port=9222`，最后用 `open -a Claude` 恢复。这同时违反 CLAUDE.md:20 与 AGENTS.md:18（向 Claude 传调试开关）、AGENTS.md:20（Claude 须由 LaunchServices 启动，不能由 shell 直接 exec）、AGENTS.md:21（AppleScript 全部不用）。该文档在 CLAUDE.md:31 被列为「设计依据」，§0.2 仍写「建议按 §7 的 T1 实测确认」，§0.3 保留「混合模式作为条件增强」，全文没有「已废弃、不要执行」的标注。
- 失败场景：维护者或按 CLAUDE.md 阅读设计依据的编码代理照此执行：先强制退出用户正在使用的 Claude 会话；在 guard 行为变化（文档自己预设的「若 exit=0 且出现 9222 端口」分支）时，Claude 会作为 shell 子进程带着本机 CDP 端口运行，不注入／不传参／由 LaunchServices 启动三条不变量同时被打破，文档还会引导把混合模式重新纳入方案；即使走预期分支，Claude 也会因 guard 拒绝而不启动，用户需手动恢复。
- 修法：将 §7.1 改为只读静态证据复核，删除可复制的 quit／调试启动／名称恢复命令，或整段标注为历史且禁止执行。
- 票数：3

### 9. [P2] 未处理 WKWebView 内容进程终止：崩溃即整段重播，连续崩溃后全屏黑幕最长 120 秒且 Esc 失效

- 位置：`src/main.swift:508`（维度：main-swift）
- 详情：AppDelegate 只实现了 didFinish / didFail / didFailProvisionalNavigation（508–526 行），全文没有 webViewWebContentProcessDidTerminate。WKWebView 在客户端未实现该回调时会自动 reload（WebKit Bug 186468 的 tryReloadAfterProcessTermination），因此内容进程一崩，六幕动画就从第一幕重新开始、语音重播；连续崩溃达到 WebKit 重试上限后不再 reload，窗口停留在 .screenSaver 级不透明全屏黑窗（319–322、367–368 行）。此时 Esc 只是 webView?.evaluateJavaScript("…skip()")（418–424 行），内容进程已死则静默无效；pollFinished 也忽略 evaluateJavaScript 错误（443 行），只剩 120s hard-deadline（297–299 行）或 Cmd+Q 能收场。
- 失败场景：Claude 冷启动、系统内存紧张时 WebContent 进程因超内存或 GPU 驱动崩溃（开屏恰好在 Claude 启动后 1.6s 内开始，是内存峰值时段）：第一次崩溃，用户看到六幕开屏从头重播一遍（语音重来一遍）；若短时间内再次崩溃，WebKit 停止自动 reload，整块屏幕被黑色全屏窗口盖住，Esc/Enter 全部无反应，最长持续 120 秒，只有 Cmd+Q 能退出。
- 修法：实现 webViewWebContentProcessDidTerminate，直接 fadeOut(content-crashed)（或最多 reload 一次，再崩即收窗），并让 requestSkip 在 evaluateJavaScript 失败时回退到 fadeOut。
- 复核修正：行号全部准确，问题本质成立；建议修正/补充以下细节：(1) WebKit 自动 reload 的重试上限具体是全局仅允许 1 次，崩溃计数在重载后主页 didFinishLoad 起 30 秒后清零——"连续崩溃"指 30 秒内的第二次崩溃；间隔超过 30 秒的再次崩溃仍会再次自动 reload。(2) 放弃 reload 后窗口仍是全屏不透明 .screenSaver 窗口，但 WKWebView 内容此时可能是空白（通常呈白色）或冻结的最后一帧，未必呈黑色；"整屏被无响应窗口盖住"的结论不变。(3) 120 秒是从启动时起算的绝对上限（297-299 行），若动画处于 requireInteraction 交互等待，剩余黑屏时间可短于 120 秒；若两次崩溃都发生在启动后 5 秒内，289/426 行的运行探针可能提前触发 fadeOut（边缘情况，不构成通用逃生路径）。(4) "开屏恰好在 Claude 启动后 1.6s 内开始"措辞有误：实际是开屏先显示，open -b Claude 在 1.6 秒后才执行（266-271 行），开屏处于 Claude 启动的内存峰值窗口。
- 票数：3

### 10. [P2] 1.6s 延迟 openClaude 与提前收窗无协调：加载失败或 1 秒内退出时 Claude 永远不会被启动

- 位置：`src/main.swift:266`（维度：main-swift）
- 详情：openClaude() 只由 asyncAfter(.now() + 1.6)（263–272 行）触发，且仅在 claudeAlreadyRunning == false（即直接双击 ClauEd）时调度；finishAndQuit（482–489 行）只在 claudeAlreadyRunning 时调用 activateClaude()，从不补发 openClaude()。任何在约 1.05 秒前完成的收窗（0.45s 淡出 + 0.1s 后 terminate）都会让进程在 1.6s 定时器触发前退出：splash.html 缺失时 0.5s 后 fadeOut（357–364 行）、didFail / didFailProvisionalNavigation（517–526 行）、以及用户在 1 秒内按 Cmd+Q（274–286 行直接 fadeOut）。
- 失败场景：直接双击 ClauEd 且 Claude 未运行时，如果 bundle 里 splash.html 缺失/损坏（build 中断、拷贝不全）或 WebView 导航失败：窗口黑屏约 1 秒后进程退出，/usr/bin/open -b 从未发出，Claude 根本没有启动，用户只看到闪一下就没了；开头 1 秒内按 Cmd+Q 想跳过黑屏也同样导致 Claude 不启动。
- 修法：记录 openClaude 是否已发出，在 finishAndQuit 中若 !claudeAlreadyRunning 且尚未打开则补调 openClaude()，或把 open 提前到 buildWindows 之前同步执行。
- 复核修正：核心结论成立，仅需修正几处细节：
1) "openClaude() 只由 asyncAfter 触发"不严谨：main.swift:225/232/245 在 DISABLED / Shift / daily 直通分支中也直接调用 openClaude（随后立即 terminate）；准确说法是"开屏播放流程内，openClaude 只由 263-272 的 1.6s 定时器触发"。
2) 缺失分支的准确范围是 main.swift:359-364（357 行是 guard 的 if-let，回调在 else 分支）；Cmd+Q 在 280-284。
3) 致命边界应表述为"fadeOut 在约 1.05s 前发起"（fade 发起 + 0.45s + 0.1s < 1.6s），而非"1.05s 前完成收窗"——缺失路径在 0.5s 发起、1.05s 退出，didFail 路径约 0.55s 退出，均早于 1.6s。
4) "splash.html 损坏"通常不会触发早退：HTML 解析宽容，截断/损坏文件一般仍会 didFinish，随后由 5s running-probe 在约 6s 收窗（晚于 1.6s，openClaude 已发出）。可靠触发前提是文件"缺失或不可读"（走 else 分支或 didFailProvisionalNavigation）。
5) Esc 跳过不在可靠触发范围内：requestSkip → finish() 立即置 __DSH_STARTUP_FINISHED__，但 dsh-startup:done 延迟 900ms 才派发（fork/splash.js:1596-1631、splash.html:84），且 1.5s 轮询首拍即能看到 finished 标志，fade 完成时 1.6s 定时器已触发；只有开屏后约 150ms 内按 Esc 才可能抢跑，实际不可达（原发现也未把 Esc 列入，仅作范围澄清）。
6) Cmd+Q 子场景可争议为"用户主动取消"的预期行为；但 missing-html 与 didFail 两条路径无歧义，缺陷本质成立。
- 票数：3

### 11. [P2] 无单实例保护：两份 ClauEd 同时运行会叠出两个 screenSaver 级全屏窗口并双份播放语音

- 位置：`src/main.swift:218`（维度：main-swift）
- 详情：applicationDidFinishLaunching 只检查 Claude 的运行实例（250–251 行），从不检查本 bundle（local.claued.splash）是否已在运行；Info.plist 也没有 LSMultipleInstancesProhibited。当存在两份不同路径的 ClauEd.app（仓库构建产物与 /Applications 安装版，README 的验证步骤正是 open ClauEd.app）、使用 open -n、或直接执行 Contents/MacOS/ClauEd 时，macOS 会并行启动两个进程。
- 失败场景：两个实例各自创建 .screenSaver 级无边框全屏窗口（317–320 行）并同时播放六幕动画与语音（两路音频相差几百毫秒，出现明显回声）；各自在 1.6s 调 open -b、各自 post visible/done、各自写日志。Esc 只被当前激活实例的 local key monitor 捕获，另一个实例的窗口仍盖在最上层，需要点击它再按一次 Esc；若它停在 requireInteraction 交互等待，遮挡最长可到 120s 硬截止。
- 修法：启动时用 NSRunningApplication.runningApplications(withBundleIdentifier:) 排除本进程后若已有实例就退出（或使用 NSDistributedLock），并在 Info.plist 增加 LSMultipleInstancesProhibited。
- 复核修正：修正三处细节：(1) 触发条件：普通 `open "ClauEd.app"`（README.md:26）在两份同 bundle id 副本之间不会并行启动两个进程——LaunchServices 默认复用已在运行的实例（NSWorkspace.h: createsNewApplicationInstance 默认 NO、allowsRunningApplicationSubstitution 默认 YES），这正是 `open -n` 的用途；LSMultipleInstancesProhibited 缺失只意味着不阻止"强制新实例"请求。真正能产生双实例的是：`open -n`（或 NSWorkspace createsNewApplicationInstance=true）、以及直接执行 Contents/MacOS/ClauEd（README.md:134 的 FPS 调试命令即属此类，完全绕过 LaunchServices）。(2) 项目并非全无自实例检查：src/watcher.swift:133-150 的 clauEdIsRunning() 按 bundle id 排除自身 pid 后检测已运行的 ClauEd，watcher 自动路径不会在开屏进行中再拉一个（但有 check-then-open 窄竞态，且不覆盖直启/open -n）。(3) "各自在 1.6s 调 open -b"不总是成立：main.swift:263-272 只在 !claudeAlreadyRunning 时于 1.6s 调 openClaude；若第二个实例在第一个已拉起 Claude 后启动，则跳过 open，但因 splashOnActivate 默认 true（main.swift:58、252-257）仍会照样播开屏、post visible/done、写日志。可重叠的时间窗受开屏寿命限制：默认完整版约 12-18s，若停在 requireInteraction 交互等待（splash.js:652-679，默认 true）可到 main.swift:297-299 的 120s 硬截止。其余描述（无自身实例检查、Info.plist 无 LSMultipleInstancesProhibited、.screenSaver 全屏窗口 317-320 行、双份语音、Esc 仅当前激活实例的 local monitor 274-286 行可捕获）与源码一致，行号 218 / 250-251 / 317-320 均准确。
- 票数：3

### 12. [P2] DISABLED / enabled=false / daily 已播 / splashOnActivate=false 时，watcher 仍无条件铺全屏黑幕约 3 秒

- 位置：`src/watcher.swift:138`（维度：watcher-swift）
- 详情：src/watcher.swift:112-141 的 handleLaunch 确认是 Claude 后就直接 showCovers()（第 138 行），watcher 从不读 ~/Library/Application Support/ClaudeSplash 下的 config.json / DISABLED / state.json。而 src/main.swift 的几条跳过路径——DISABLED 标记或 enabled=false（222-228 行）、Shift（230-235 行）、displayMode=daily 当天已播（243-248 行）、claudeAlreadyRunning && !splashOnActivate（252-257 行）——都是 openClaude 后直接 NSApp.terminate(nil)，既不 post local.claued.splash.visible 也不 post local.claued.splash.done。watcher 只能等 src/watcher.swift:263-268 的 3 秒超时兜底收幕。
- 失败场景：把 displayMode 设为 daily（README 第 67 行文档化）后，当天第一次冷启动正常播放；此后每次冷启动都是：watcher 收到 didLaunch → 所有屏幕铺 .screenSaver 级黑幕（连菜单栏一起盖住）→ ClauEd 发现 daily 已播、open -b Claude 后立即退出、不发任何通知 → 黑幕一直僵持到 3 秒超时才消失。用户当天每次启动 Claude 都先看 3 秒全屏黑屏。同理，touch DISABLED（README 第 103 行承诺「临时停用，启动器只开 Claude 并退出」）或 enabled:false 时，「停用」并不无感——每次冷启动仍有约 3 秒全屏黑屏。
- 修法：watcher 在 showCovers 前自查 DISABLED 标记、enabled/displayMode 与 state.json（daily 已播则直接放行）；或让 ClauEd 在所有提前退出路径先 post 一次 local.claued.splash.done。
- 复核修正：描述与代码基本一致，行号（watcher.swift:138/263-268、main.swift:222-228/230-235/243-248/252-257）全部准确。两处修正/补充：① main.swift:230-235 的 Shift 路径在 watcher 模式下不会造成黑屏——watcher 自己在 watcher.swift:121-124 先检查 Shift 并直接跳过（不铺黑幕），该路径只有直接启动 ClauEd（不经 watcher）时才可达；核心场景（DISABLED/enabled=false/daily/splashOnActivate=false）不受影响。② 发现说"watcher 只能等 3 秒超时"结论正确，但值得补充其真实原因：watcher 源码其实有 clauEd-terminated 收幕分支（watcher.swift:157-160），因 ClauEd.app 是 LSUIElement 后台 app，Apple 文档规定 didTerminateApplicationNotification 不会为 LSUIElement app 发出（实测日志中 ClauEd 退出未触发该分支），所以该兜底是死代码，黑幕实际恰好持续 kCoverTimeout=3.0 秒。
- 票数：3

### 13. [P2] 屏幕热插拔重建黑幕后不重挂 3 秒看门狗，黑幕可能永久滞留

- 位置：`src/watcher.swift:241`（维度：watcher-swift）
- 详情：rebuildCovers()（235-242 行）先调用 hideCovers("screen-change")，而 hideCovers（254-261 行）会 cancel 并置空 coverTimeout；重建完成后第 241 行 showCovers() 只做 setFrame/orderFront，不调用 scheduleTimeout()。整个文件只有 handleLaunch 第 140 行会安排超时，showCovers 自身不含兜底计时。
- 失败场景：外接/拔掉显示器、开合盖或改分辨率恰好落在点开 Claude 后的覆盖窗口期（didLaunch 后约 0.15–1 秒、ClauEd 尚未 post splash.visible）：didChangeScreenParameters → 黑幕被关闭重建并再次全屏铺开，同时 3 秒定时器已被取消且没有重挂。若 ClauEd 在这段时间内挂起（WKWebView/WindowServer 初始化卡住）没能发出 visible/done，全屏黑幕（.screenSaver 层级、ignoresMouseEvents）就永久停在所有屏幕上——没有定时器、没有可点击的 UI，用户只能盲操作退出 Claude（触发 didTerminate → hideCovers）或杀掉 watcher 才能恢复。再次热插拔只会重复「关掉-重建-重铺且依旧无计时器」的循环。
- 修法：把 scheduleTimeout 收进 showCovers（幂等：先 cancel 旧计时再挂新计时），rebuildCovers 重铺后自然重新计时。
- 复核修正：行号与核心机制均准确，仅补充三点细节：1) 脆弱时间窗不是固定的『didLaunch 后约 0.15–1 秒』，而是从 handleLaunch 的 showCovers（138 行）持续到 splash.visible / splash.done / 3 秒超时（140 行）任一先到；0.15–1 秒只是常态，ClauEd 启动变慢时窗口可接近 3 秒，卡死时因超时已被取消而无限延长。2) hideCovers 的定时器取消受 255 行 guard coverShown 约束；本场景此时 coverShown 为 true，机制成立。3) 黑幕并非绝对永久：除盲操作退出 Claude 外，盲操作退出卡住的 ClauEd（157-159 行 didTerminate → hideCovers）或杀掉 watcher 也能恢复；准确说法是『没有任何自动恢复路径，只能盲操作外部进程解除』。
- 票数：3

### 14. [P2] ShipIt 检测在主线程同步跑两次 /bin/ps 且无超时：更新重启仍可能播开屏，ps 卡死会锁死 watcher

- 位置：`src/watcher.swift:129`（维度：watcher-swift）
- 详情：handleLaunch 在 showCovers 之前调用 parentName（190-208 行）：Process + waitUntilExit 串行启动两个 /bin/ps，全部在主队列上执行，没有任何超时；判定只认 Claude 的直接父进程 comm 是否包含 "ShipIt"。
- 失败场景：(a) ShipIt 拉起新版 Claude 后随即退出，didLaunch 送达时 Claude 的 ppid 已变成 1（launchd），父进程名不含 ShipIt → 自动更新重启被当成用户冷启动，播完整个 12–18 秒开屏，正是该检测想避免的场景。(b) 两个 ps 横在 didLaunch 与 showCovers 之间，机器繁忙时黑幕要晚几十到几百毫秒才铺上，Claude 窗口可能先露出来。(c) 若 ps 因进程表/磁盘异常迟迟不退出，waitUntilExit 会永久阻塞主线程：黑幕不铺、ClauEd 不拉，之后所有 didLaunch/didTerminate 与已排的 3 秒定时器都不再被处理，watcher 假死直到被 kill 后 KeepAlive 重启。
- 修法：改为异步判定：后台队列跑 ps 并加超时（超时按非 ShipIt 放行），或直接用 sysctl KERN_PROC 取 ppid，绝不在主线程 waitUntilExit。
- 复核修正：1) (a) 的机制应修正为：并非「ShipIt 拉起新版 Claude 后随即退出，didLaunch 送达时 ppid 才变成 1」。真实流程（Squirrel.Mac ShipIt-main.m，macOS 11+）是旧 ShipIt posix_spawn 一个新 ShipIt，新 ShipIt 调 NSWorkspace launchApplicationAtURL 后立即 exit；LaunchServices 让 launchd 直接 spawn 应用（本机统一日志 2026-11-13 21:26:41.502 launchd[1]："Successfully spawned Claude[2957] because launch job demand"），Claude 从出生起 ppid 就是 launchd（本机 pid 1，comm=/sbin/launchd），与 ShipIt 是否已退出无关。因此对 launchAfterInstallation=YES 的更新重启，skip 分支不是「可能」失效，而是确定失效，整个开屏必播完；README.md:92 的「ShipIt 自动更新重启会跳过」不成立。本机 2026-11-14 10:08 的更新是 launchAfterInstallation=false 的后台安装，不重启 Claude，不属于该场景（2026-11-13 21:26 那次 Claude 自己的更新则走了重启流程）。
2) (b) 的百毫秒级延迟有日志可证（10:26:50.966→10:26:51.104，138ms），但「Claude 窗口可能先露出来」是时序推测，未观测到。
3) (c) 的「ps 卡死锁死主线程」机制正确，但依赖 /bin/ps 永久不退出这一极端前提；且此路径下 showCovers/scheduleTimeout 都还没执行，不存在本次 launch 已排的 3 秒定时器（只可能残留上一次开屏的）。
- 票数：3

### 15. [P2] finish() 的 900ms 收尾定时器不随 dispose 取消，重播后旧实例仍会派发 dsh-startup:done

- 位置：`fork/splash.js:1620`（维度：splash-js）
- 详情：finish() 在 1620-1623 行用匿名 setTimeout(ms(900)) 做两件事：摘掉 root、在 window 上派发 dsh-startup:done。这个定时器 id 没有保存，dispose()（188-212 行）只清 stall/clock/voice/root，不会取消它；回调本身也没有 stale()/代际判断。而 replay（injectSelf，215-245 行；文件头第 15 行和 API 第 1649 行都声明支持）会先 prev.dispose()（它会把 __DSH_STARTUP_FINISHED__ 重置为 false）再重新挂脚本。因此上一轮 finish()/skip 后 900ms 内发生的重播，会被旧定时器补发一次 done。
- 失败场景：一次开屏正常结束（或按 Esc 跳过）后 900ms 内调用 window.__DSH_STARTUP_API__.replay()：旧实例的 900ms 定时器到点后在 window 上 dispatch dsh-startup:done → fork/splash.html 第 84 行的桥把 done post 给 Swift → main.swift 第 496-498 行 fadeOut(reason:"done") 会对当前（新）实例执行 dispose 并淡出窗口，新开屏在约 0.9s 时被整个收掉；且 dispose 已把 __DSH_STARTUP_FINISHED__ 置回 false，finished 轮询无法把这次伪造事件和真实结束区分开。done 事件因此不是每轮恰好一次。
- 修法：保存该 timeout id 并在 dispose()/finish() 里 clearTimeout，或在回调开头加 if (stale()) return 的代际守卫。
- 复核修正：机制、时序与全部行号（splash.js:1620-1623 / 188-212 / 215-245 / splash.html:84 / main.swift:496-498）都准确。需补充两点限定：(a) 仓库内无任何 replay() 调用方，启动器无重播 UI，触发只能手动进行（README.md:134 记载的 CLAUDESPLASH_DEBUG=1 + Web Inspector 路径，或浏览器预览 devtools；后者桥为空转，无法触发 Swift 收窗），生产流程中不会自发发生；(b) 该收尾延时是 ms(900)=900/speed，speed=3 时窗口仅约 300ms，默认 speed=1 时为 900ms。另外 dispose 除 stall/clock/voice/root 外还会经 releaseAll 清 wait() 链的定时器并复位 RUNNING/FINISHED，但确实不包含这个 finish 定时器——原描述核心结论正确，仅措辞略简。
- 票数：3

### 16. [P2] finish()/dispose() 之后当前时间线链仍在继续执行：Esc 跳过时还会补播 rise/sweep/confirm 并新建定时器

- 位置：`fork/splash.js:1326`（维度：splash-js）
- 详情：run() 的 act-1/act-2 回调（1326-1383 行）和互动步骤的后续 then（1449-1454 行）都没有 finished/stale 守卫，只有 stepLoop 每步开头（1398 行）有；且 wait() 在 skipped 时直接 resolve（637 行）。requestSkip()（1626-1631 行）先置 skipped=true 再 releaseAll()，于是当前挂起的 wait 一被释放，剩余整条链会在微任务里继续跑完——即使 finish() 已执行过 voice.stop()/audio.stopAll()。之后新建的合成音源（tone/noise）和 audio.confirm() 的 sfx-tick 都创建于 stopAll 之后（或本就不在 active[] 里），因此停不掉；dispose() 路径（Cmd+Q/120s 硬截止）因 skipped 未置位，还会用真实 setTimeout 继续排程新定时器。
- 失败场景：开屏前 ~3.7s（第一幕）内按 Esc：窗口已开始 dsu-gone 淡出，但链继续执行 audio.rise()（1329 行，220→990Hz、1.1s 滑音）和 audio.sweep()（1343 行，0.75s 噪声），用户会听到"跳过之后还有一整套开场音效"。在第一步按钮等待时按 Esc，则 1451 行的 audio.confirm() 会在收窗时响一声。dispose 路径同样会在淡出中执行这些回调并在 releaseAll 之后新建不会被清理的定时器/rAF。
- 修法：在每个 act/step 的 then 开头加 if (finished || stale()) return（与 stepLoop 保持一致），并让 wait() 在 finished 时也立即 resolve 或抛出哨兵值以中止链。
- 复核修正：行号与核心机制基本准确（1326/1329/1343/637/1398/1449-1454/1626-1631 均对得上）。需修正的细节：(a) "只有 stepLoop 每步开头（1398）有守卫"不完整——finale()（1525）和步骤内 rAF（1423）也有 finished 守卫；关键点是 act-1/act-2 链与 waitAction 之后的 then 确实没有守卫。(b) 时间窗：rise 在 ~820ms、sweep 在 ~2700ms（第一幕尾声）触发，"~3.7s"是洗白转场回调结束点；在约 2.7–3.7s 之间按 Esc 不会补播 rise/sweep（这两个回调已跑过），只会执行 1348-1363、1366-1381 的视觉/进度回调（含 1379 的裸 setTimeout）和 1383 的视觉 sweep；另外 Esc 落在 820–1920ms 时正在播放的 rise 也因未被 active[] 跟踪而无法被 stopAll 掐断。(c) dispose 路径中 setProgress 重启的 rAF（progTick 716-718）有 finished 判断、只多跑一帧即返回，不构成持续 rAF；真正遗留的是 setSubtitle 的裸 setTimeout（805）与新 wait 定时器。(d) 成品 app 里 dispose 后约 0.55s 即进程退出（main.swift:474-489），dispose 路径的续跑大多被截断，最稳定的可听症状是 Esc 路径（页面活到 ~1.35s，1.1s rise 基本完整播完）以及第一步等待时按 Esc 的 confirm 声。
- 票数：3

### 17. [P2] 洗白层 z-index:35 位于黑幕 z-index:40 之下，220ms 的过曝洗白升幅全程不可见，过场退化为纯黑淡出

- 位置：`fork/splash.css:264`（维度：splash-css）
- 详情：`.dsu-wash` 的 z-index:35（splash.css:264）低于 `.dsu-black` 的 z-index:40（splash.css:169）。splash.js:1341-1362 的时序是先给 wash 设置 220ms 升到 opacity:1，但此时 black 仍完全不透明（black 的 opacity 直到下一个 .then 才在 720ms 内降到 0），随后 wash 与 black 同时淡出。wash 的可见量 = (1 - blackOpacity) × washOpacity，全程峰值只剩约两成。设计文档（开屏方案 v2 §1.4）描述的“220ms 升到中灰 #8b8a88 → 底板淡入 → 720ms 洗白退场”从未真正呈现。
- 失败场景：每次播放第 1→2 幕过场（固定时序，无需输入）：0–260ms 画面保持纯黑（wash 升到 1 的过程被不透明黑幕完全遮住，这 260ms 是死拍），随后直接变成黑幕与底板的交叉淡化，只能看到约 20% 强度的灰雾；亮色与暗色（--dsu-wash-dark）洗白一样被遮。DSH 标志性的灰/白过曝洗白效果丢失。
- 修法：把 `.dsu-wash` 提到黑幕之上（如 z-index:45），或先淡出 `.dsu-black` 再升 wash。
- 复核修正：行号与代码路径全部准确，但两处量化/描述需修正：(a) “峰值只剩约两成”偏高——按实际缓动（black 用 ease，wash 用 cubic-bezier(.2,.9,.2,1)）数值计算，(1-blackOpacity)×washOpacity 的峰值约 8.1%（出现在 720ms 过场的约 21% 处，即约 152ms），灰雾比描述更弱，结论“洗白基本不可见”反而更强；(b) “0–260ms 画面保持纯黑/死拍”不完全准确：splash.js:1342 同时给 blackInner 加 dsu-out，DSH 标识以 620ms 过渡淡出（splash.css:185-189），这 260ms 是“黑底上标识淡出”，只是 wash 的升幅被不透明黑幕完全遮住。其余描述（两层级 z-index、同时淡出、亮暗两色洗白均被遮、每次播放必现）与代码一致。
- 票数：3

### 18. [P2] opacity:0 的黑幕以 z-index:40 留在全屏拦截鼠标，SKIP 可见后 0.7s（speed 慢时约 2s）内点击无效

- 位置：`fork/splash.css:169`（维度：splash-css）
- 详情：`.dsu-black`（splash.css:163-171）没有 pointer-events:none。splash.js:1361-1362 只把黑幕 opacity 降到 0，直到 1383 行才 display:none，中间隔了 wait(ms(700))；而 `.dsu-skip`（z-index:30，splash.css:964-981）在 splash.js:1380 已经加上 dsu-in 变为可见。离屏 WKWebView 实测：black opacity=0、display=grid、z-index=40 时，对 SKIP 中心点调用 document.elementFromPoint 返回的正是 `dsu-black`，SKIP 的 click 监听（splash.js:1635）收不到事件。
- 失败场景：speed=1 时开屏约 1.0–1.7s 之间，用户看到右上角“SKIP ▸”渐显并点击，点击落在不可见的黑幕 div 上，表现为“点了没反应”（此时只有 Esc 有效）；speed=0.35 时该死区约 2 秒（JS 等待按 ms() 除以 speed 变长，黑幕透明度早已为 0），正好覆盖跳过按钮完全可见的整段时间。
- 修法：给 `.dsu-black` 加 `pointer-events: none`（该层为纯装饰，无交互元素），或黑幕淡出完成即 display:none。
- 复核修正：机制描述准确（`.dsu-black` splash.css:163-171 无 pointer-events:none、z-index 40；splash.js:1361-1362 仅降 opacity；1380 行 skip 加 dsu-in；1381 行 wait(700)（wait 内部按 ms() 除以 speed 缩放）；1383 行才 display:none；点击监听 splash.js:1635，期间失效）。需要修正的是时间：speed=1.0 时 SKIP 出现于约 3.72s（820+240+880+760+260+760ms），黑幕到约 4.42s 才移除，死区约 3.72–4.42s、持续 700ms（其中 skip 400ms 渐显结束后约 300ms 是完全可见却点不动）；原描述的 1.0–1.7s 实为 speed=3 的表现（tools/wk_probe.swift 硬编码 speed:3），speed=0.35 时死区约 2.0s（约 1.6s 完全可见无效）的描述正确。
- 票数：3

### 19. [P2] splash.html 默认配置与 splash.js DEFAULTS 不同步：mode 与 identity 两个键不一致

- 位置：`fork/splash.html:27`（维度：splash-css）
- 详情：逐键比对 34 个键：fork/splash.html:25-60 中 `mode: 'always'`（27 行）、`identity: 'Edward'`（44 行）；fork/splash.js:29-64 DEFAULTS 中 `mode: 'session'`（31 行）、`identity: '豪叔'`（48 行）。其余键取值一致（speed 1.0 与 1 数值相同）。CHANGELOG 记载“终幕黑框文案改为 CLAUDE；身份改为 Edward”只同步了 HTML 与 Swift 侧，splash.js 的 DEFAULTS 仍是旧值，正是硬约束第 9 条要防的两处漂移。
- 失败场景：任何不经过 splash.html 内联默认对象、直接加载 splash.js 的路径（脚本级冒烟/测试、Host 侧嵌入——splash.js 注释声明的同步对象就是 Host DEFAULTS）会得到 mode='session'、identity='豪叔'：终幕显示“欢迎 豪叔 访问”、身份卡“用户名称 豪叔”，而烘焙的终幕语音（splash.js:1551）念的是“Edward, Welcome to Anthropic's Claude…”，画面与声音互相矛盾；且 finish() 会写 sessionStorage['dsh-startup-screen:shown']（1608 行），与 HTML 默认 'always' 的语义不同。
- 修法：把 splash.js DEFAULTS 的 mode/identity 改为与 splash.html 一致（'always'/'Edward'），或在构建校验里加两文件逐键比对。
- 复核修正：修正后的准确描述：fork/splash.html:27 `mode:'always'`、:44 `identity:'Edward'` 与 fork/splash.js DEFAULTS 的 :31 `mode:'session'`、:48 `identity:'豪叔'` 不同步（其余 32 键相同，speed 1.0 与 1 数值相等）。CHANGELOG“身份改为 Edward”只改了 splash.html 与 src/main.swift（备份 .backup-20261113-225109 中三处原均为 '豪叔'），splash.js DEFAULTS 漏改；mode 的差异自初始 fork 就存在，不是本次改名引入。失败场景应修正为：(a) config.json 将 identity 写成空串时（src/main.swift:107 接受、:340 注入空 identity，经 splash.html:61 合并后为空），splash.js:155 回退到 DEFAULTS.identity='豪叔'，终幕显示“欢迎 豪叔 访问”、身份卡“用户名称 豪叔”，而 1551 行 line-6 烘焙语音念的是 “Edward, Welcome to Anthropic's Claude…”，画面与声音矛盾；(b) 任何裸加载 splash.js、不提供 __DSH_STARTUP__ 的页面（splash.js:327-333 会自建根节点完整播放）同样得到 mode='session'、identity='豪叔'，且 finish() 在 1608 行写 sessionStorage['dsh-startup-screen:shown']。需注意：仓库内现有加载路径均不会命中这些旧值——src/main.swift:357 与 tools/wk_probe.swift 经 splash.html（HTML 默认补齐两键）、extras/glass-demo.html:138-157 自行设置 mode/identity；splash.js:28 注释所指的 Host lib/index.js 不在本仓库，AGENTS.md:46 已把同步对象定义为 splash.html。mode='session' 在 ClauEd 中不可达（Swift 不注入 mode，HTML 恒为 'always'；每日一次状态在 Swift state.json），故本问题在正常启动流程中被遮蔽，属配置一致性缺陷 + 边缘可达的错误显示。
- 票数：3

### 20. [P2] watch-on 在 disabled 覆盖下先 bootstrap 后 enable，off 之后重装监听器必然静默失败

- 位置：`claude-splash-watch-on.command:57`（维度：scripts-build）
- 详情：off 脚本第 24 行 launchctl disable "gui/$(id -u)/local.claued.watch" 会把该 label 写入 launchd 的持久 disabled 数据库（launchctl(1) 明确：disabled 服务 "cannot be loaded in the specified domain until it is once again enabled"，且跨重启持久；本机 launchctl print-disabled gui/501 中确实存在该 label 的覆盖记录）。watch-on 第 56-58 行顺序是 bootout -> bootstrap -> enable，三条全部 2>/dev/null 且不检查退出码，第 60 行无条件打印 ✅。
- 失败场景：用户先双击 claude-splash-off.command 关闭美化（或卸载后重装），再双击 watch-on 重新安装：第 57 行 bootstrap 因服务仍处于 disabled 状态直接失败（错误被吞掉），第 58 行 enable 只是清除覆盖、不会补载服务；脚本仍显示“原生监听器已安装”。用户按提示退出 Claude 再打开，黑幕和开屏都不会出现，launchctl print gui/501/local.claued.watch 显示 not found，~/Library/Logs/ClauEdWatcher.log 也没有新的 watcher started；要等到下一次登录/重启 launchd 重新扫描 LaunchAgents 才恢复。
- 修法：把 launchctl enable 移到 launchctl bootstrap 之前，并检查 bootstrap 退出码（失败时打印错误并 exit 1）。
- 复核修正：描述与代码一致，无需实质修正；仅一处细节澄清：本机 `launchctl print-disabled gui/501` 中该 label 的覆盖记录当前显示为 `"local.claued.watch" => enabled`（watch-on 第 58 行 enable 留下的），因此此刻 watcher 是加载且在运行的（`launchctl print gui/501/local.claued.watch` 显示 state = running）；故障只在“最后一次 enable 之后又执行过 off 的 disable”时出现，即先 off 再 watch-on 的序列，而非任何时候重装都会失败。
- 票数：3

### 21. [P2] watch-on 不删除 off 写入的 DISABLED 标记，重新安装后开屏永远不播

- 位置：`claude-splash-watch-on.command:27`（维度：scripts-build）
- 详情：claude-splash-off.command:33 会 touch "$CFG_DIR/DISABLED"；watch-on 第 26-27 行的清理只删除 watch-claude.sh / watch-claude-running / watch-claude-initialized，从不删除 DISABLED。src/main.swift:222-227 只要标记存在就 open Claude 后直接退出：不建窗，也不发 local.claued.splash.visible。
- 失败场景：用户先运行 off（文档定义的“永久关闭”），之后双击 watch-on 想恢复开屏（README 唯一的监听器安装入口，脚本末尾还承诺“退出 Claude 再从 Dock 点 Claude，黑幕会立刻出现”）：即使 watcher 被成功加载（例如重启后），每次 Claude 冷启动 watcher 都会铺黑幕并拉起 ClauEd，但 ClauEd 见到 DISABLED 直接打开 Claude 退出，watcher 随即收到 ClauEd 退出而收起黑幕——用户每次启动只看到约 1 秒黑屏闪烁、永远没有开屏，安装脚本却报告成功；DISABLED 是磁盘文件、跨重启持久，只能手动 rm 才能恢复。
- 修法：watch-on 在安装成功路径上 rm -f "$DIR/DISABLED"，把“安装监听器”定义为完整的启用操作。
- 复核修正：描述与代码实质一致，仅两处细节修正：(a) main.swift 的 DISABLED 判断完整范围是 222-228 行（222 取路径、223 条件、225 openClaude、226 terminate、227 return），引用 222-227 不影响结论；(b) 黑幕收起的主路径是 watcher.swift:157-160 收到 ClauEd 的 didTerminateApplication 通知即 hideCovers("clauEd-terminated")（3 秒超时只是兜底），因此闪现时长取决于 ClauEd 启动到退出的耗时，通常不足 1 秒至 1 秒左右，与描述的「约 1 秒黑屏闪烁」吻合；另外 off 之后要恢复开屏，除手动 rm 外只能跑 uninstall 删掉整个配置目录（会连 ClauEd.app 一起移入废纸篓），不存在其他脚本清理该标记。
- 票数：3

### 22. [P2] build.sh 未指定部署目标，产物 minos 27.2 与 Info.plist 声明的 macOS 13.0 矛盾

- 位置：`build.sh:14`（维度：scripts-build）
- 详情：第 14、17 行的 swiftc 都没有 -target/-mmacosx-version-min，swiftc 默认把 minos 设为构建机当前系统版本。vtool -show-build 实测本机产物：ClauEd 与嵌套 ClauEdWatcher 均为 minos 27.2，而 Info.plist 的 LSMinimumSystemVersion=13.0、AGENTS.md 写明运行环境 macOS 13+。minos 随构建机漂移，构建不可复现。
- 失败场景：把构建出的 ClauEd.app 拷到任何低于 27.2 的 Mac（或未来在旧系统上重建）时：主程序被 dyld/LaunchServices 以“requires macOS 27.2 or later”拒绝启动；嵌套 watcher 也因同样 minos 无法被 LaunchAgent exec，KeepAlive 还会对着无法执行的路径反复重试。项目对外声称的 macOS 13+ 兼容完全失效，且只有在换机器时才会暴露。
- 修法：两处 swiftc 都加 -target "$(uname -m)-apple-macos13.0"（或 -mmacosx-version-min=13.0）。
- 复核修正：行号与事实描述准确（build.sh:14/17 无 -target；两处产物 minos 27.2；Info.plist 13.0；AGENTS.md 声明 macOS 13+），但失败机制需修正：在低于 27.2 的 Mac 上拒绝启动 ClauEd 的是 LaunchServices（实测 error -10825 = kLSIncompatibleSystemVersionErr，"The app cannot run on the current OS version"，SDK LSConstants.h:49；实测 LS 会比较可执行文件 LC_BUILD_VERSION minos 与运行系统版本，Info.plist 的 LSMinimumSystemVersion=13.0 不能豁免），而不是 dyld：直接 exec minos 99.0 的主程序可正常运行，dyld 仅在被依赖库加载失败时附加"too new"诊断，主执行文件路径不检查 minos。嵌套 watcher 由 LaunchAgent 的 ProgramArguments 经 launchd 直接 exec（claude-splash-watch-on.command:42-45，KeepAlive 48-49），不经过 LaunchServices，预计能够在旧系统启动；它打开 ClauEd 失败后走 watcher.swift:180-187 的 hideCovers("launch-failed") 路径，不会出现"watcher 无法 exec、KeepAlive 反复重试"的现象。另补充同根因的独立证据：无部署目标令所有 #available 在编译期折叠（产物无 swift_stdlib_isOSVersionAtLeast，无 activateIgnoringOtherApps: 选择器），main.swift:190-195 的 NSApp.activate()（macOS 14+ 才有，SDK NSApplication.h:236）被无条件调用，macOS 13 上即使绕过 LS 门禁也会在此崩溃；用 -target arm64-apple-macos13.0 重建即恢复 guard 与运行时检查。原结论"对外声称的 macOS 13+ 兼容失效、只有换机器才暴露"成立（受影响的旧系统不止 macOS 13，凡 < 27.2 均被 LS 拒绝），但"dyld 拒绝"与"嵌套 watcher 无法 exec/KeepAlive 重试"两点不成立。
- 票数：3

### 23. [P2] watch-on 用 python3 改 config.json，但不检查 python3 是否可用、不检查写盘结果

- 位置：`claude-splash-watch-on.command:16`（维度：scripts-build）
- 详情：第 15-24 行只有在 config.json 已存在时用 /usr/bin/env python3 - heredoc 把 splashOnActivate 改成 true。脚本只有 set -u 没有 set -e，heredoc 的退出码完全没被检查，随后照常写 plist 并打印 ✅。macOS 未安装 Command Line Tools 时 /usr/bin/python3 是 xcode-select 的 tool shim（本机 /usr/bin/python3 即 com.apple.dt.xcode_select.tool-shim-public），会弹出“安装命令行开发者工具”对话框或直接非零退出。另外第 21 行 json.dump(cfg, open(p, "w")) 是先截断再序列化，异常会留下半截 config.json。
- 失败场景：用户按 README 配置表把 splashOnActivate 设为 false（避免手动点 ClauEd 时也播开屏），然后运行 watch-on 安装监听（脚本本意就是强制改回 true）：python3 不可用/失败时配置仍是 false，之后每次 Claude 冷启动 watcher 铺黑幕 -> ClauEd 因 claudeAlreadyRunning && !splashOnActivate（src/main.swift:252-256）只激活 Claude 就退出 -> 黑幕收起，用户每次启动只看到一次黑屏闪烁、没有开屏，而脚本显示安装成功；若序列化中途失败，config.json 被截断，src/main.swift 解析失败后回落全默认值，用户的 identity/theme/speed 等设置静默丢失。
- 修法：先 command -v python3 检查（或换成不依赖 python3 的实现），失败即退出；config 写入改为临时文件 + mv 原子替换并检查退出码。
- 复核修正：原描述基本准确，补充三点边界：(1) 黑屏闪烁通常不是 3 秒——watcher 在 ClauEd 进程终止时（watcher.swift:157-159）就收起黑幕，实际只有 ClauEd 启动到退出的数百毫秒；3 秒（:263-267）只在 ClauEd 完全拉不起来时兜底。(2) 双击 .command 会打开 Terminal，python3 失败的错误文本会打印在 ✅ 之前，脚本并非完全无声，但退出码不被检查、仍无条件打印安装成功，用户容易误以为已生效。(3) 截断 config.json 的子场景要求 json.dump 在写出中途抛异常（从 JSON 载入的数据本身总是可序列化，常见诱因是孤立代理项转义或磁盘/IO 错误），不是任何写失败都会发生；一旦发生，main.swift:95-97 的 try? 静默回落全默认值且 :68-69 不会重写已有文件，设置相当于丢失。
- 票数：3

### 24. [P2] uninstall 不验证 off 是否执行成功就删除 app，KeepAlive 监听器可能对着已删除路径反复重启

- 位置：`claude-splash-uninstall.command:7`（维度：scripts-build）
- 详情：第 7 行直接执行 "$SCRIPT_DIR/claude-splash-off.command"，既不检查该文件是否存在/可执行，也不检查退出码；off 内部所有 launchctl bootout/disable 都带 2>/dev/null（第 15、23 行），且脚本最后一条命令是 if pgrep...，无论 bootout 成败都退出 0。随后第 13-17 行把 /Applications/ClauEd.app 移入废纸篓，第 18 行删除配置目录。
- 失败场景：用户把 uninstall 脚本单独拷贝/移动（或仓库目录被改名、删除）后双击，或某次 off 的 launchctl bootout "gui/$(id -u)" "$WATCH_PLIST" 失败（错误被吞、off 仍返回 0，且 off 第 25-28 行随后照样把 plist 改名）：脚本继续把 /Applications/ClauEd.app 移走，而 local.claued.watch 仍处于 loaded 且 KeepAlive=true，ProgramArguments 指向的 /Applications/ClauEd.app/Contents/Resources/ClauEdWatcher.app/Contents/MacOS/ClauEdWatcher 已不存在——launchd 会持续按 10 秒节流重试 spawn 缺失程序并写系统日志，直到注销/重启或手动 bootout；卸载脚本却照常打印“完成”。
- 修法：执行 off 前校验其存在，off 非零退出即中止；bootout 后用 launchctl print gui/$UID/local.claued.watch 确认服务不存在才删除 app，off 内部不应吞掉 bootout 错误。
- 复核修正：行号和代码引用基本准确（uninstall:7、off:15/23 及其 2>/dev/null、off:25-28、off:47-52、uninstall:13-18 均属实），但需修正两点：
(1) “仓库目录被改名、删除”不是触发条件：SCRIPT_DIR 是运行时由 $0 解析的，改名仓库不影响第 7 行；仓库被删除则脚本本身也无法双击运行。真实触发是 uninstall 脚本被单独复制/移动到 off 不在的目录（或 off 丢失可执行位/被删），或 off 中 `launchctl bootout gui/$(id -u) "$WATCH_PLIST"` 在 job 已加载时失败（例如 plist 已先被手工删除而 job 仍 loaded）。另外 uninstall:10/13 还会把仓库内的 ClauEd.app 一并移入废纸篓。
(2) 后果的持久性分两种：off 完全没执行时 watch plist 仍是原文件且 enabled，KeepAlive 的重试循环会在每次登录后重新出现，跨重启持续，“直到注销/重启”不成立，只能手动 bootout/disable/删 plist；off 执行了但 bootout 失败时，off:25-28 已把 plist 改名，循环最多持续到本次注销（或 watcher 进程在会话内退出时），重启后不会再加载。另需注意 off:24 的 `launchctl disable` 只是阻止后续加载，不能卸载已加载的 KeepAlive job，起不到兜底作用。
- 票数：3

### 25. [P2] fork/splash.js 的 DEFAULTS 仍保留旧身份「豪叔」，与 splash.html/Swift/README/CHANGELOG 的 Edward 两处不同步

- 位置：`fork/splash.js:48`（维度：docs-consistency）
- 详情：AGENTS.md:46 与 CLAUDE.md:23 要求 fork/splash.js 的 DEFAULTS 与 fork/splash.html 的 __CLAUDE_DEFAULT_CFG__ 两处同步，CHANGELOG.md:9 已声明「身份改为 Edward」。但 splash.js:48 仍是 `identity: '豪叔'`，splash.html:44 是 `identity: 'Edward'`，src/main.swift:55、extras/config.example.json:10、README.md:73 也都是 Edward；另有 splash.js:31 `mode: 'session'` 与 splash.html:27 `mode: 'always'` 同样不一致。cfg() 第 155 行用 `out.identity || DEFAULTS.identity` 兜底，会把旧值重新带回。
- 失败场景：用户在 config.json 里把 `"identity"` 置空（想清掉名字/回默认）时，Swift 注入空串（src/main.swift:340），splash.js:155 回退到 DEFAULTS 的「豪叔」，终幕显示「欢迎 豪叔 访问」、identityId 兜底成 OPERATOR，而文档承诺的默认值是 Edward/0087；任何绕过 splash.html 默认块直接加载 splash.js 的宿主也会看到旧身份，且「两处同步」这条维护约定已经失效。
- 修法：把 splash.js DEFAULTS 的 identity 改为 'Edward'（mode 与 splash.html 对齐），恢复两处同步。
- 复核修正：核心成立：fork/splash.js:48 的 DEFAULTS 仍是 `identity: '豪叔'`，与 splash.html:44、src/main.swift:55、extras/config.example.json:10、README.md:73、CHANGELOG.md:9 的 Edward 不同步；当用户在 config.json 写 `"identity": ""` 时（main.swift:107 接受空串，main.swift:340 原样注入，splash.html:61 原样合并），splash.js:155 的 `out.identity || DEFAULTS.identity` 回退为「豪叔」，终幕 splash.js:525 显示「欢迎 豪叔 访问」。需修正两处细节：(1) 该场景下 identityId 不会变成 OPERATOR——Swift 仍会注入默认 '0087'（main.swift:56/108/341，splash.js:157 得到 0087）；只有同时把 identityId 也置空才会触发 splash.js:158 的 OPERATOR 兜底（实测 {identity:'',identityId:''} → 豪叔/OPERATOR）。(2) 「绕过 splash.html 默认块直接加载 splash.js 的宿主」在仓库内不存在——ClauEd 主流程、tools/wk_probe.swift、浏览器预览全部经 splash.html:61 合并默认配置，该失败场景是假想的。另外 mode 差异（splash.js:31 'session' vs splash.html:27 'always'）属实，但 mode 仅在 splash.js:1608-1610 写 storage 且总被 splash.html 覆盖为 'always'，无实际功能影响，属于纯文本不同步。
- 票数：3

### 26. [P2] README/AGENTS/build.sh 声称「Claude 已运行只会激活、不播开屏」，与默认 splashOnActivate=true 的代码相反

- 位置：`README.md:26`（维度：docs-consistency）
- 详情：README.md:26 快速开始注释写 `# Claude 已在运行时只会激活它，不播开屏`，build.sh:34 的构建结束提示相同；AGENTS.md:38 真机验证第 3 步要求出现 `Claude already running -> activate & exit`、无窗口；README.md:168 验证记录也写「Claude 已运行 → 只激活并退出」实测通过。但默认配置 splashOnActivate=true（src/main.swift:58、extras/config.example.json:13、README.md:74，README.md:31 也说明 true 时会播），主进程只在 `claudeAlreadyRunning && !config.splashOnActivate` 时才 activate & exit（src/main.swift:252-257），默认路径会照常 buildWindows 播完整开屏，结束时才 activateClaude（src/main.swift:485）。
- 失败场景：用出厂默认配置、Claude 正在运行时双击 ClauEd：文档预期是「不播开屏、只激活」，实际会全屏播放约 12–18s 的开屏；按 AGENTS.md 第 3 步验证的编码代理等不到 `Claude already running -> activate & exit` 日志，会误判实现坏了并去改正确的代码。
- 修法：把 README 第 26 行、build.sh 第 34 行、AGENTS 验证第 3 步与 README 验证记录改为：默认 splashOnActivate=true 会播一遍，仅当设为 false 才 activate & exit。
- 复核修正：描述基本准确，仅补三点细化：1) README 属内部自相矛盾：README.md:31 已按 splashOnActivate:true 写明正确行为，过期的只是 README.md:26（以及 README.md:168 的验证记录）；build.sh:34 与 AGENTS.md:38 则是与当前默认配置直接冲突的独立表述。2) README.md:168 的「实测通过」很可能是旧默认 splashOnActivate=false（见 .backup-20261113-225109/src/main.swift:48、extras/config.example.json:13）时期遗留的过期验证记录，而非虚构结果。3) 「约 12–18s」的前提是用户完成前两步交互（requireInteraction 默认 true）；若不点击，实际停留更久（最长到 src/main.swift:297-299 的 120s 硬截止）。
- 票数：3

### 27. [P2] main.swift 的直通出口都不发 visible/done，watcher 黑幕只能等满 3 秒超时

- 位置：`src/main.swift:223`（维度：integration）
- 详情：只有正常开屏路径会在 src/main.swift:370-372 post `local.claued.splash.visible`、在 src/main.swift:455-463 post `.done`。但 enabled=false/DISABLED（223-228）、Shift 按住（230-235）、daily 今日已播（243-248）、Claude 已运行且 splashOnActivate=false（250-257）这 4 条会在 watcher 流程中出现的直通路径，都是 openClaude/activateClaude 后立即 terminate，不发任何分布式通知。watcher 在 didLaunch 时已经 showCovers()+scheduleTimeout（src/watcher.swift:138-140、263-268），收幕只能靠 3 秒超时；watcher.swift:157-159 的 ClauEd didTerminate 兜底在实测中没有触发（见最后一条）。
- 失败场景：displayMode=daily 时：当天第一次开屏已播过，用户第二次从 Dock 点 Claude → watcher 立刻铺全屏黑幕 → ClauEd 读到 state.json 走“daily already shown -> pass-through”，打开/激活 Claude 后约 0.2 秒退出，全程无 visible/done → 黑幕盖满 3 秒才收起，此后每次启动都重复。同理，用户在点 Dock 之后、ClauEd 启动检查之前才按下 Shift（watcher 的 didLaunch 时刻没看到 Shift，main.swift 看到了）会得到 3 秒黑屏，而不是文档承诺的“跳过本次”。
- 修法：在每条直通出口 terminate 之前都 post `local.claued.splash.done`（或 visible），让 watcher 立即收幕。
- 复核修正：原描述主体准确，仅作几处精确化：(1) `.done` 的 post 在 src/main.swift:461-463（fadeOut 函数从 455 开始），且 fadeOut 也被 done 事件/8s 导航超时/120s 硬截止/Cmd+Q 等路径复用，并非只属“正常开屏”，但都在 buildWindows 之后，不影响结论；(2) 静默终止的出口实际还有第 5 条 main.swift:237-241（Claude 未安装），它也不发通知，但在 watcher 流程中不可达（watcher 只在 Claude didLaunch 后触发），所以“4 条”的计数对 watcher 场景是对的；(3) ClauEd didTerminate 兜底代码在 watcher.swift:157-160（157 `else if` 判 bundle id、158 log、159 hideCovers、160 右括号），常量 kCoverTimeout 在 watcher.swift:17；(4) 重要补充：本机 ~/Library/Logs/ClauEdWatcher.log 证明该兜底在正常流程中也从未触发过（watcher 全程存活，ClauEd 正常退出后日志无 "clauEd terminated"），故直通路径“只能等满 3 秒超时”的判断成立。
- 票数：3

### 28. [P2] watcher 不读 DISABLED/config.enabled：禁用开屏后它仍铺全屏黑幕并拉起 ClauEd

- 位置：`src/watcher.swift:138`（维度：integration）
- 详情：handleLaunch（src/watcher.swift:112-141）只判断 bundleId、claudeRunning、Shift、20 秒 grace、ShipIt 和 clauEdIsRunning，从不检查 `~/Library/Application Support/ClaudeSplash/DISABLED` 或 config.json 的 enabled。README.md:103 和《备份与恢复方案》L1 都把 `touch DISABLED` 描述成“启动器只开 Claude 并退出（不建窗、不遮屏）”，但该开关只在 src/main.swift:223-228 生效；watcher 依旧在第 138 行 showCovers() 并 launchClauEd()。
- 失败场景：已安装 watch-on 的用户按 README 做 L1 临时停用（只 touch DISABLED，不跑 off）→ 之后每次点 Claude：watcher 先铺全屏黑幕并启动 ClauEd，ClauEd 看到 DISABLED 走直通、立即退出且不发 visible/done，黑幕挂到 3 秒超时。用户本想“暂时不要开屏”，结果每次启动多吃 3 秒全屏黑屏；config.json 里 enabled=false 同样触发。
- 修法：watcher 在铺幕前增加 DISABLED 文件与 config.enabled 检查，命中时像 Shift 一样直接返回，不铺幕也不拉起 ClauEd。
- 复核修正：修正后的发现：watcher（src/watcher.swift:112-141）不读 DISABLED 与 config.json 的 enabled，watch-on 用户按 L1 touch DISABLED 或把 enabled 设为 false 后，每次 Claude 冷启动 watcher 仍会 showCovers() 并 launchClauEd()，ClauEd 直通退出也不发 visible/done。但黑幕不会挂到 3 秒超时——src/watcher.swift:152-161 的 handleTerminate 在 ClauEd 终止时立即 hideCovers("clauEd-terminated")，实际症状是约 0.1-0.5 秒的全屏黑闪（时长 ≈ ClauEd 启动到退出的耗时，本机日志中正常路径全程约 160ms），外加一次多余且会再执行 open -b com.anthropic.claudefordesktop 的 ClauEd 启动（仅激活已在启动的 Claude）。该行为与《备份与恢复方案》第 59 行 L1“不建窗、不遮屏”、以及 README 配置表“enabled=false = 只打开 Claude”的承诺不符。另：README.md:103 原文并无“不建窗、不遮屏”字样，该表述仅见于备份文档；行号 138/139 与 223-228 均核对无误。影响比原报告轻，严重度应为 P3 而非 P2。
- 票数：3

### 29. [P2] ShipIt 更新重启的跳过判断永远不命中：LaunchServices 拉起的 Claude 父进程是 launchd（PPID=1）

- 位置：`src/watcher.swift:129`（维度：integration）
- 详情：src/watcher.swift:129-132 用 parentName(of:)（190-194 行经 `/bin/ps -o ppid=`、`/bin/ps -o comm=`）判断 Claude 的父进程名是否包含 “ShipIt”。但由 LaunchServices 启动的 GUI 进程父进程是 launchd：实测当前 Claude 主进程 pid 24104 的 PPID=1（ps -axo pid,ppid 输出 `24104 1`）。Claude.app 内 Squirrel.framework/Versions/A/Resources/ShipIt 二进制含有 `launchApplicationAtURL:options:configuration:error:` 符号，即 ShipIt 也是经 LaunchServices 拉起新 Claude，父进程仍是 launchd，因此 `parent.contains("ShipIt")` 永远为 false。
- 失败场景：Claude 后台自动更新（ShipIt）完成并重启时，watcher 把它当成用户冷启动：立即铺全屏黑幕 + 拉起 ClauEd；此时 Claude 已运行、splashOnActivate=true，于是开屏在用户正在做别的事情时全屏播放约 25 秒（先整屏黑幕再动画），README.md:92“Claude 的 ShipIt 自动更新重启会跳过”的承诺不成立。
- 修法：不要用父进程名判断，改为跟踪 Claude 的 didTerminate→didLaunch 更新式重启（记录退出方式/间隔或 ShipIt 事务）来识别自动更新。
- 复核修正：基本准确，补充三点修正：1) macOS 11+ 上直接调用 NSWorkspace 的不是原 ShipIt，而是它用 posix_spawn 拉起的第二个 ShipIt（ShipIt_stderr.log 可见 "Launching new ShipIt at ... / New ShipIt pid: 2952"），由该子进程执行 launchApplicationAtURL；本质仍经 LaunchServices，Claude 父进程仍是 launchd，结论不变。2) 仅 launchAfterInstallation=true 的更新会自动重启（本机 ShipItState.plist 在 2026-11-14 10:08 一次为 false，未重启；2026-11-13 21:26 等多次为自动重启），该失败只在这些自动重启时发生，而 ShipIt 日志显示此类重启按周频繁出现。3) 开屏时长随配置变化：speed=1.0 实测约 22 秒，requireInteraction=true 时还会等待用户交互，最长到 120 秒硬截止；"约 25 秒"只是典型值。另注：/Applications/ClauEd.app 内现装 watcher 二进制不含 ShipIt/parentName 代码（无 "ShipIt"、"/bin/ps" 字符串，与 src/watcher.swift 不一致，属旧版本构建），因此当前产品同样不跳过更新重启。
- 票数：3

### 30. [P2] 屏幕参数变化时 rebuildCovers 取消 3 秒兜底却不重新排期，黑幕可能永久停留

- 位置：`src/watcher.swift:237`（维度：integration）
- 详情：rebuildCovers（src/watcher.swift:235-242）响应 didChangeScreenParametersNotification：先 hideCovers("screen-change")，而 hideCovers（254-261）会 `coverTimeout?.cancel()`；随后 `if wasShown { showCovers() }`（第 241 行）重新铺幕，却没有再次调用 scheduleTimeout()。原本用于等待 ClauEd visible 的 3 秒兜底被永久取消。README.md:90 声称“黑幕有 3 秒超时兜底，ClauEd 失败或卡住不会留下黑屏”。
- 失败场景：watcher 铺幕等待 ClauEd 窗口的几秒内插拔外接显示器/改分辨率/切换镜像（触发 didChangeScreenParameters）→ 超时被取消、黑幕重铺；若本次 ClauEd 走直通路径（DISABLED/daily/Shift，不发 visible）或在启动中崩溃，且 ClauEd didTerminate 兜底未触发（见下一条），screenSaver 层级的全屏黑幕会一直盖住所有屏幕，除重新加载 watcher/重启外无法恢复。
- 修法：rebuildCovers 在重新 showCovers() 后，如果仍在等待 visible（wasShown 为真），重新 scheduleTimeout()。
- 复核修正：重建描述：rebuildCovers（src/watcher.swift:235-242）响应屏幕参数变化时确实取消了 3 秒兜底且不重新排期（237 行 hideCovers 经 254-258 取消 coverTimeout，241 行只重铺幕；scheduleTimeout 仅在 140 行调用），但触发状态应修正为：屏幕参数变化恰好落在 handleLaunch 铺幕到 splash.visible 之间的等待窗口，且随后 ClauEd 进程处于"卡住"状态——进程存活、主线程阻塞在 applicationDidFinishLaunching/buildWindows（visible 在 src/main.swift:370-372 才派发，自身 8s/120s 定时器在 src/main.swift:289-299 才安装），既不派发 visible/done 也不退出（如显示重配置导致 WindowServer 停顿、WKWebView/LaunchServices 同步调用挂起）。此时黑幕才会永久停留。原文列举的 DISABLED/daily/Shift 直通（src/main.swift:222-257）与启动中崩溃会以 ClauEd 终止收场，由 src/watcher.swift:157-160 的 didTerminate 分支收起黑幕，不能单独作为触发状态（除非另有证据证明该通知丢失，原文"见下一条"的结论在本维度无法证实）；较轻微的卡顿则会被 ClauEd 自身 8s/120s 截止兜底，表现为黑幕从承诺的 3 秒延长到最多约 8~120 秒。
- 票数：3

### 31. [P2] README 与备份恢复文档把 `open -a Claude` 写成应急入口，与 P0 约束及实际实现矛盾

- 位置：`README.md:106`（维度：gap:claude-splash-off.command 第 5 步（45–47 行）对 Claude 的启动与健康验证；claude-splash-uninstall.command:6 会先调用它）
- 详情：README.md:106 在“永远可用”一行把 `open -a Claude`（按应用名解析）写成应急启动方式；备份与恢复方案（Safe Mode · 外部关闭）.md 第 10 行（30 秒恢复卡）、第 26 行（把实现描述成“只通过 LaunchServices（open -a）启动 Claude”，与实际 src/main.swift:395-398 的 `open -b` 不符）、第 31 行（“对外动作…open -a Claude”）、第 63 行（L5 完全绕过）、第 109 行（内嵌 off 脚本副本）同样使用 `open -a Claude`。同一文档 §6 第 162 行的诊断命令却正确使用 `open -b com.anthropic.claudefordesktop`，文档内部自相矛盾；而 CLAUDE.md:20、AGENTS.md:18、README.md:14 的 P0 约束只允许 open -b。
- 失败场景：Claude 打不开、用户按 README.md:106 走“永远可用”的应急路径时，若机器上残留旧版/改名的同名 Claude 副本，`open -a Claude` 会拉起错误副本而不是官方 /Applications/Claude.app；用户看到错误 app 的失败表现，会误判为“ClauEd 把官方 Claude 弄坏了”，再按文档 §6 排查时又拿到与 §0/§3 不一致的启动方式。反过来，官方 app 被移出 /Applications 但仍在 LaunchServices 注册时，`open -a` 可能找错或找不到，而 `open -b` 能按 bundle id 正确解析。
- 修法：README.md:106 及备份与恢复方案第 10/26/31/63/109 行统一改为 `open -b com.anthropic.claudefordesktop`，并按真实实现修正 §1 第 5 条的描述。
- 票数：3

### 32. [P2] 安装监听器的第 2 步要求从 Dock 移除 ClauEd，但 LSUIElement 下它从不出现在 Dock

- 位置：`README.md:85`（维度：gap:Info.plist 的 LSUIElement（Info.plist:23）与 Dock/激活行为，对照 README.md:29、82–86 和 claude-splash-watch-on.command:64 的用户指引）
- 详情：ClauEd 的 Info.plist:23-24 设置 LSUIElement=true，src/main.swift:219 又显式 NSApp.setActivationPolicy(.accessory)。按 Apple 文档，agent 应用『do not appear in the Dock or in the Force Quit window』，且没有菜单栏（本项目《备份与恢复方案》第 201 行也按『LSUIElement 无菜单栏』设计了按键监听）。已安装的 /Applications/ClauEd.app 与仓库构建产物的 Info.plist 均确认 LSUIElement=true，可确认这是刻意选择：AGENTS.md:50 把 LSUIElement=true 列为 Info.plist 契约，设计文档《Claude Desktop 美化方案调研.md》:124/321 明确写『LSUIElement，无 Dock 图标』。因此问题在文档：README.md:82-86 的『Claude 启动监听』把『在 Dock 里右键 ClauEd → 选项 → 从 Dock 中移除』写成安装后的编号第 2 步，claude-splash-watch-on.command:64 还把同一句作为安装脚本的最终输出打印。默认流程（快速开始 `open "ClauEd.app"`，LSUIElement）从未创建过 Dock 图标，该步骤对绝大多数用户不可执行；而它想达到的『Dock 里只保留 Claude、不要第二个启动器图标』本来就被 LSUIElement 自动实现。
- 失败场景：新用户双击 claude-splash-watch-on.command 安装监听器，脚本最后打印『1. 在 Dock 里右键 ClauEd → 选项 → 从 Dock 中移除』。用户看 Dock：没有 ClauEd（只有此前手动从 Finder 固定过才可能存在）；第 2 步无法执行，会误判监听器/安装失败，从而停在验证步骤之前（不再执行第 3 步『退出 Claude，再点 Dock 里的 Claude』去验证），而功能其实已经装好。
- 修法：删除该步骤或改写为『ClauEd 因 LSUIElement 本就不显示在 Dock；仅当此前手动把它固定到 Dock 时才需要移除』，并同步 claude-splash-watch-on.command:64。
- 票数：3

### 33. [P2] Force Quit 恢复路径对 LSUIElement 启动器不可用，且 pkill 兜底仍按旧名 EdClaude 匹配

- 位置：`备份与恢复方案（Safe Mode · 外部关闭）.md:145`（维度：gap:Info.plist 的 LSUIElement（Info.plist:23）与 Dock/激活行为，对照 README.md:29、82–86 和 claude-splash-watch-on.command:64 的用户指引）
- 详情：README.md:108 把本文件 §5–§6 指定为『故障速查与 60 秒诊断』的权威，但文档仍是更名前（EdClaude）的方案稿：§0 恢复卡（第 11 行）与 §5 速查表（第 145 行）写『无效 Cmd+Opt+Esc 强制退出「EdClaude」；或终端 pkill -f "EdClaude.app/Contents/MacOS/EdClaude"』。ClauEd 是 LSUIElement/agent 应用（Info.plist:23-24、src/main.swift:219；Apple Launch Services Keys 原文：Agent apps do not appear in the Dock or in the Force Quit window），因此根本不会出现在强制退出窗口里；同一行的终端兜底用旧进程路径，也匹配不到现名二进制（实际进程路径为 /Applications/ClauEd.app/Contents/MacOS/ClauEd，对照 claude-splash-off.command:6）。同文档其它退出路径同样指向旧名：第 60 行 launchctl bootout 的 local.edclaude.splash.plist、第 171 行 grep "EdClaude.app" 均不存在（当前监听 label 为 local.claued.watch）。
- 失败场景：开屏窗口卡死、全屏黑幕不消失（例如主线程卡住导致 120s 硬截止定时器也不触发的场景）时，用户按 README 指引查《备份与恢复方案》§0/§5 执行恢复：Cmd+Opt+Esc 的强制退出窗口只列常规应用，找不到任何 ClauEd/EdClaude 条目；改用同一行给出的 pkill 命令，因模式是旧的 EdClaude 路径而静默无匹配；用户可能转而强制退出列表里唯一的 Claude，而黑幕仍然不退。
- 修法：把恢复文档更新为 ClauEd 现名并给出真实可用路径：Activity Monitor 或 `pkill -f "ClauEd.app/Contents/MacOS/ClauEd"`，并注明 LSUIElement 应用不会出现在强制退出窗口。
- 票数：3

### 34. [P2] 实施文档把启动动作写成 open -a Claude，与「只用 open -b」及现行代码不一致

- 位置：`开屏方案 v2（暗色自适应 · 音频复用 · 豪叔）.md:217`（维度：gap:被 CLAUDE.md:31 列为「设计依据」的文档仍含硬约束禁止的 Claude 启动/环境命令：Claude Desktop 开屏移植评估.md:234,271、开屏方案 v2…md:217、Claude Desktop 美化方案调研.md:126,351,430,547）
- 详情：「4. 更新后的启动流程」第 217 行写 `t≈80ms open -a Claude（不带调试参数）`；同样被 CLAUDE.md:31 列为设计依据的《Claude Desktop 开屏移植评估.md》第 234 行也写 `open -a Claude`。CLAUDE.md:20 与 AGENTS.md:18 要求只用 `open -b com.anthropic.claudefordesktop` 且不传任何参数；现行实现是 `p.executableURL = /usr/bin/open` + `p.arguments = ["-b", kClaudeBundleID]`（src/main.swift:397-398），「已在运行」也按 bundle id 判断（src/main.swift:250-251）。AGENTS.md:57 规定品牌／文案改动必须同步到该文档，说明它是活文档；src/main.swift:6 的注释也仍写着 `open -a Claude`，旧表述在向代码扩散。
- 失败场景：维护者按设计依据修改启动步骤或新建对照实现时写回 `open -a Claude`：LaunchServices 按显示名解析，机器上若存在第二份名为 Claude 的 bundle（备份副本、改名的 3P 构建），会启动错误的应用或报「找不到 Claude」；启动器按 `com.anthropic.claudefordesktop` 判断运行状态（main.swift:250），会出现官方 Claude 未启动而开屏已播放、或按错误应用判定运行状态的分裂结果，开屏结束后用户看不到真正的 Claude。括号里「不带调试参数」还把红线从「不传任何参数」弱化成「不传调试参数」。
- 修法：两处设计文档的启动时序统一改为不带参数的 `open -b com.anthropic.claudefordesktop`，并删除「不带调试参数」的限定语。
- 票数：3

### 35. [P3] 五条 pass-through 出口不发 splash.visible/done，watcher 黑幕只能靠进程退出事件或 3 秒超时收起

- 位置：`src/main.swift:226`（维度：main-swift）
- 详情：local.claued.splash.done 的唯一发送点是 fadeOut（461–463 行）。disabled / enabled=false（223–228 行）、Shift（230–235 行）、Claude 未安装（237–241 行）、daily 已播（243–248 行）、Claude 已运行且 splashOnActivate=false（250–257 行）这五条路径直接 NSApp.terminate，既不 post visible 也不 post done。watcher 在每次 Claude 冷启动时先铺黑幕（src/watcher.swift:138-140），只能依赖 ClauEd 的 didTerminateApplicationNotification（src/watcher.swift:152-161）或 3s 超时（src/watcher.swift:263-268）收幕。
- 失败场景：装好 watcher 后用 DISABLED 标记临时停用开屏：每次从 Dock 启动 Claude，watcher 仍先铺全屏黑幕，ClauEd 立即 pass-through 退出，黑幕要等 LaunchServices 的 ClauEd 退出通知（正常约 0.2–0.5 秒；事件缺失时吃满 3 秒兜底）才收起——与 Safe Mode 文档 L1「临时停用 = 不建窗、不遮屏」的承诺不符；displayMode=daily 时当天第二次起每次冷启动都会重复黑闪。
- 修法：在五条 pass-through 分支 terminate 前统一 post 一次 local.claued.splash.done（抽成 helper）；watcher 侧也应先读 DISABLED/config，停用时直接不铺黑幕。
- 复核修正：总体判断成立，但描述需修正三点：1) Shift 出口（main.swift:230-235）在 watcher 流程下通常不会产生黑闪——watcher.swift:121-124 在收到 Claude 启动事件时先检查 Shift，按住即直接 return，既不铺黑幕也不拉起 ClauEd；只有「watcher 已铺幕并拉起 ClauEd 之后、ClauEd 检查前」按住 Shift 的窄竞态才会在幕下走该直通出口。2) 「Claude 未安装」出口（main.swift:237-241）不可能出现在 watcher 触发的流程中：watcher 只响应 Claude 启动事件，Claude 未安装则无事件、无黑幕；直接双击 ClauEd 也没有黑幕可收。3) 真正会触发所述黑闪的是 223-228（DISABLED/enabled=false）、243-248（daily 当天已播）和 252-257（splashOnActivate=false；watcher 拉起 ClauEd 时 Claude 必然已在运行，故 claudeAlreadyRunning 恒为 true，该分支必然直通）。另外黑幕持续时间不止「通知延迟 0.2–0.5 秒」，而是 ClauEd 从 LaunchServices 启动到进程退出的整段（通常数百毫秒），仅当退出事件缺失时才是 3 秒。
- 票数：3

### 36. [P3] 5s 运行探针只判定一次且把 evaluateJavaScript 失败当作“没跑起来”，慢启动时会误杀健康开屏

- 位置：`src/main.swift:428`（维度：main-swift）
- 详情：checkRunningProbe（426–436 行）在 t=5s 只求值一次 window.__DSH_STARTUP_RUNNING__ === true；completion 中 (result as? Bool) != true 把「返回 false」与「result 为 nil（页面还没加载完 / 求值报错）」同样处理，1 秒后无条件 fadeOut(not-running)，中间不再复核。开屏要等 WebContent 进程启动、加载 splash.js+assets.js（约 524KB）后才把 RUNNING 置 true（fork/splash.js:1322），而主程序自己在 263–266 行承认 Claude 冷启动会抢 CPU/GPU。
- 失败场景：慢盘/老机型或刚登录时，Claude 冷启动与 WKWebView 启动叠加可能让 5s 时页面仍未开始执行：6 秒时探针收窗退出，一个本来能正常播放的开屏被静默掐掉（用户只看到约 6 秒黑屏后直接露出桌面）；由于 markShownToday 已在 262 行写入，displayMode=daily 时当天不会再播。
- 修法：探针改为多阶段（5s/8s/11s）或仅在明确返回 false 时判定，evaluateJavaScript 报错时重试而不是 fade。
- 复核修正：代码引用全部准确（426-436/428/429/431-433/262/263-271，splash.js:1322，524KB），需修正/补充三点：(1) 淡出后并非"直接露出桌面"——Claude 已于 t≈1.6s 被拉起且开屏在前台，淡出后通常直接露出 Claude 窗口；(2) 5s 一次性探针是 AGENTS.md:23 明列的必保留安全开关，且在"页面 HTML 加载完成但 JS 未执行"场景下是唯一早期兜底（8s 导航超时因 navigationFinished=true 不会触发，否则黑窗持续到 120s 硬截止），6s 收窗是既定的黑屏上界设计而非漏掉的复核；(3) 实测 10/10 次启动页面加载 ≤1s、探针失败 0 次，"5s 时仍未开始执行"在 macOS 13+（全 SSD 机型）上需要 5 倍以上从未观测到的劣化，失败场景未达成。
- 票数：3

### 37. [P3] 日志只追加不轮转，且页面 error 桥无节流，重复 JS 异常会持续刷盘

- 位置：`src/main.swift:35`（维度：main-swift）
- 详情：logLine（32–42 行）每次 open/seek/write/close 追加写入 ~/Library/Logs/ClaudeSplash.log，没有大小上限或轮转；一次正常播放约写 10–20 行（finished 轮询每 6s 一条 progress，449–451 行）。页面把每个 window error 经消息桥逐条转发（fork/splash.html:86 → main.swift:499-501 的 logLine("js error: …")），没有节流或去重。
- 失败场景：长期使用日志单调增长（每次播放约 1–2KB，配合 watcher 的频繁冷启动每年可达数 MB 且永不回收）；一旦引擎出现每帧/循环抛出的 JS 异常（例如音频解码或 rAF 回调持续报错），错误桥会以每秒几十条的速度写日志，主线程频繁磁盘 I/O，拖慢动画并快速放大日志文件。
- 修法：启动时检查日志大小并按需轮转/截断（如超过 512KB 归档为 .1），并对 error 消息按内容+时间窗去重限流。
- 复核修正：细节修正三处：(1) 每场正常播放实测写 6-13 行（本机现有日志），只有 requireInteraction 一直等到 120s 硬截止的场次才会到约 20 行，声称的"约 10-20 行"偏上限但量级正确；(2) "主线程频繁磁盘 I/O，拖慢动画"不准确——splash 的 JS 渲染跑在 WebContent 独立进程，Swift 主线程的逐行写日志不会直接阻塞渲染，实际影响是增加主线程 I/O 与 WKScriptMessage 处理负担、可能延迟 done 事件与 fade 处理；(3) 错误风暴的规模有界：启动器进程寿命受 120s 硬截止约束（main.swift:297-299），单次启动内错误桥最多约写几十万字节，需要引擎缺陷在多次启动中持续复现才会跨场累积到 MB 级；同一不限量日志模式也存在于 watcher.swift:32-42（写 ClauEdWatcher.log），但本条发现按范围只指 main.swift。
- 票数：3

### 38. [P3] LaunchAgent 写死 /Applications 内嵌可执行路径且 KeepAlive，app 被移走/删除后 launchd 每 10 秒重试刷系统日志

- 位置：`claude-splash-watch-on.command:44`（维度：watcher-swift）
- 详情：claude-splash-watch-on.command:10-11 把 WATCHER 写死为 /Applications/ClauEd.app/Contents/Resources/ClauEdWatcher.app/Contents/MacOS/ClauEdWatcher，42-45 行写进 ProgramArguments，48-49 行设 KeepAlive=true。安装时只在第 29 行检查一次 -x；之后 app 被移动或删除，launchd 仍保留该 job，每次 spawn 必然失败并按默认 10 秒节流无限重试，持续写入系统日志。
- 失败场景：用户手动把 /Applications/ClauEd.app 拖进废纸篓或移到别处（不走 off 脚本就没有任何 bootout）：local.claued.watch.plist 仍留在 ~/Library/LaunchAgents，launchd 每 10 秒尝试 exec 一个不存在的路径并向系统日志写一条失败记录，可能持续到下次登录甚至更久；即使把 app 放回别的位置也不会恢复（路径写死），开屏监听从此永久缺席，而系统里没有任何面向用户的报错，只有日志噪音。
- 修法：plist 增加 PathState 监视该可执行文件（缺失时 job 不再 spawn），并让 off/卸载流程同时 bootout 并删除 plist，文档里强制「先 off 再删 app」。
- 复核修正：行号与代码路径全部核实无误。两处措辞需精确化：(1) 若 app 被移走时 watcher 进程仍在运行（已删除的可执行文件可继续存活），10 秒重试循环不会立刻开始，而是从进程退出（如下次登录/重启）后开始；(2) "开屏监听从此永久缺席"应修正为"直到把 app 放回 /Applications 原路径或移除 plist/job 为止持续缺席"——因为 job 始终保留，恢复原路径即可自动恢复监听，只有放到其他位置才永远失效。其余（写死路径、一次性 -x 检查、ProgramArguments、KeepAlive=true、无自动清理、10 秒节流无限重试写日志）均与源码及本机 launchd 实测状态一致。
- 票数：3

### 39. [P3] 20 秒启动宽限期以 watcher 进程启动时刻为基准：安装后首次真实启动会被吞，登录慢时又会在登录自启时误播

- 位置：`src/watcher.swift:125`（维度：watcher-swift）
- 详情：startedAt 在进程启动时取（第 54 行），第 125-128 行把 watcher 启动后 20 秒内的任何 Claude didLaunch 都当作登录自启跳过（而且此时 claudeRunning 已置位）。KeepAlive 每次崩溃重启都会重置这 20 秒盲区；安装/重装时 bootstrap 立即拉起 watcher，宽限期也从安装时刻开始计时。
- 失败场景：按 claude-splash-watch-on.command 第 63-66 行的提示装完后立刻「退出 Claude，再从 Dock 点 Claude」（20 秒内完成）：这次启动被记录为 "launch within startup grace -> skip"，没有黑幕也没有开屏，日志里只有一行 skip，用户会判定监听器没装好或坏了。反向场景：登录项多、冷启动慢的机器上，Claude 作为登录自启若晚于登录 20 秒才发 didLaunch，会被当成用户冷启动，在登录时弹出完整开屏。
- 修法：宽限期改以登录会话的创建时间（如 CGSessionCopyCurrentDictionary 的登录完成时间）为基准，而不是 watcher 进程启动时间。
- 复核修正：行号、代码片段和日志字符串均准确，无需实质修正；仅有两处措辞可更精确：(a)「claudeRunning 已置位」属实但本身无害——Claude 退出时 didTerminate 会复位，真正失效点是 :125-128 的提前 return 使这次启动永远不出开屏；(b) 反向场景在登录时 watcher 启动与登录基本同刻，本质是 20 秒阈值对慢登录不够，而非「基准时刻选错」；「安装后首次真实启动会被吞」应限定为「bootstrap/KeepAlive 重启后 20 秒内退出并重启 Claude」这一时序条件（finding 的失败场景已写明 20 秒内，标题略绝对）。
- 票数：3

### 40. [P3] 素材播报路径的声纹条只亮不灭：setMeter(true) 在播放结束后才执行且没有对应的关闭

- 位置：`fork/splash.js:1189`（维度：splash-js）
- 详情：voice.line 的素材分支在 playAssetAndWait(...).then 里执行 if (ms > 0) setMeter(true)（1188-1191 行），而 playAssetAndWait 只在 onended 或 duration+1500ms 超时兜底时才 resolve（985-988 行）——即这一句已经念完之后才点亮声纹条；此后整条素材路径没有任何 setMeter(false)。TTS 路径是 onstart/onend 成对（1137-1139 行），对比可见素材路径写反了。voice.stop()（1231-1235 行）里的 setMeter(false) 还会被 stopAll 触发 onended 后的 setMeter(true) 反向覆盖。
- 失败场景：默认配置（voiceSource=asset）播放第一步：line-1 播完（约第 6.6s）后，左下角 .dsu-voice 的 5 根声纹条被点亮并无限循环 dsu-voice 动画（splash.css 1124-1132 行），一直亮到收窗；之后所有静音间隔、甚至 finish() 之后仍保持点亮和跳动，与 CSS 注释"出声时点亮"不符。
- 修法：起播前 setMeter(true)，在 fin/onended 或 playAssetAndWait 的 then 里 setMeter(false)。
- 复核修正：主线成立，修正三处细节：1) 声纹条确实在素材台词播完后才点亮（playAssetAndWait 仅在 onended 或 duration+1500ms 超时后 resolve，fork/splash.js:966-991、1188-1191），素材分支此后无 setMeter(false)，默认配置（voiceSource=asset，assets.js 内联音频）下第 1 步 line-1（实际 1.75s，第一步约 4.4s 开始）约 6.2s 播完即点亮，并持续亮到 finish()，期间所有静音间隔和后续步骤都保持点亮跳动。2) "finish() 之后仍保持点亮"不准确：正常终幕 finish() 会 voice.stop()→setMeter(false)（1605、1234 行）先熄灭；只有 skip/停滞看门狗等仍有素材在播时，audio.stopAll()（1233 行）触发的异步 onended 才会经 985→1189 行把声纹条在熄灭后重新点亮，且被 dsu-gone 620ms 淡出和 900ms 后移除（1618-1623 行）掩盖。3) 引用的 TTS 成对行 1137-1139 是未被调用的 utter() 死代码，实际生效的是 ttsLine 的 1275 行 onstart 与 1276-1277 行 onend/onerror→settle（1261-1266 行）。
- 票数：3

### 41. [P3] 互动步骤固定先等 520ms 才挂输入监听、且不看 requireInteraction：按钮可见但点不动，无交互配置下按钮闪现并播确认音

- 位置：`fork/splash.js:1449`（维度：splash-js）
- 详情：stepLoop 在 1447 行先无条件 showAction(step)，到 1449 行才 wait(520) 之后调用 waitAction()；Enter/Space/点击监听器是在 waitAction 内部（676-678 行）才挂载的，而 waitAction 只在 !C.requireInteraction 时立即放行（654 行）。由此产生两个可复现问题：(a) 默认 requireInteraction=true 时，按钮/提示从约 320ms 起已经可见（.dsu-action 过渡，splash.css 530-532 行），但前 ms(520) 的输入被静默丢弃；(b) requireInteraction=false 时仍会展示并脉动按钮，并在 520ms 后 hideAction + audio.confirm()（1450-1451 行）。
- 失败场景：默认 speed=1：用户在第一步文字刚出现时立刻按 Enter/Space（按钮已经可见）→ 没有任何反应；speed=0.35 时这个"看得见但点不动"的窗口约 1.5s（520/0.35），用户若以为已确认就会一直停在等待，只能再按一次或等 Swift 的 120s 硬截止。配置 requireInteraction=false（README 推荐的快进搭配）时，两步仍各闪一次按钮并播放 confirm 确认音，实际上没有任何确认发生。
- 修法：进入互动步骤时立即挂监听（只把 creepProgress 延迟 520ms）；showAction 用 if (C.requireInteraction) 包起来，或在 requireInteraction=false 时跳过整个 action 分支。
- 复核修正：细节修正：(1) 1449 行源码是 `wait(520)` 而非 `ms(520)`，但 wait() 内部（646 行）会经 ms() 按 speed 缩放，所以 520ms/C.speed 的换算描述（speed=0.35 时约 1.49s）成立；(2) 1447 行 showAction(step) 位于 1446 行 `if (step.action === 'grant' || step.action === 'confirm')` 分支内，并非全局无条件，该分支内确实无条件先展示；(3) 可见时间应表述为：showAction 加上 dsu-in 的瞬间按钮即开始渐显（splash.css 528 行 transition 320ms，530-532 行把 pointer-events 立即置为 auto），约 320ms 完全不透明——即死区覆盖整个 wait(520/speed)，其中 speed=1 时约 200ms 处于"全亮但无响应"状态，比"从 320ms 起可见"更早；(4) 死区内点击并非完全静默：按钮有 hover 反色与 :active 下压（splash.css 558-562）和脉动动画，会给出反馈但无处理器执行，误导性更强；(5) requireInteraction=false 时按钮闪烁时长等于 wait(520/speed)（README 推荐的 speed 1.6 下约 325ms），随后 hideAction 淡出 320ms，确认音（sfx-tick/合成双音，splash.js:1029）因 main.swift:331 允许自动播放而真实出声；(6) 项目无注释或文档说明该 520ms 输入锁是有意设计（1448 行注释只解释蠕行进度条）。
- 票数：3

### 42. [P3] 素材播报路径忽略 voiceLead，提示音与台词首音重叠

- 位置：`fork/splash.js:1187`（维度：splash-js）
- 详情：DEFAULTS.voiceLead 注释明确"提示音之后留一小段空白再开口"（47 行），TTS 路径用 setTimeout(speak, lead) 实现（1257、1269 行）；但素材路径在 audio.cue()（1187 行）之后立刻 playAssetAndWait（1188 行），没有任何 voiceLead 等待。实测 fork/assets.js 里 line-1..6 的开头静音只有 32-39ms，而 cue 是 1046.5Hz/50ms + 75ms 后 1568Hz/60ms（1035 行），结束约在 135ms。
- 失败场景：默认配置（voiceSource=asset）每一句：voiceLead: 240 形同虚设，提示音两个音符正好压在第一个音节上（重叠约 100ms）；用户把 voiceLead 调到 0-1200 之间任何值都完全无效，只有素材缺失回落 TTS 时才生效。
- 修法：素材路径在 cue() 后先等 clamp 后的 voiceLead 再起播 playAssetAndWait，并把这段等待计入该步时长。
- 复核修正：描述与代码基本完全准确，行号核对无误（47、1035、1178、1187-1188、1257、1269 均对；lead 实参在 1282 行 `}, lead)` 传入）。仅两处细节修正：素材开头静音实测约 34-40ms（-50dB~-40dB 阈值，-30dB 阈值约 40-47ms），不是 32-39ms 但量级一致；因此与 135ms 结束的提示音重叠约 95-101ms，"约 100ms"成立。
- 票数：3

### 43. [P3] prefers-reduced-motion 只冻结进度条，未绕开洗白/底板/终幕推近等主要动画

- 位置：`fork/splash.js:706`（维度：splash-js）
- 详情：706-709 行读取了 reduceMotion，但全文件只有 setProgress（746 行）和 creepProgress（763 行）用到它——即只把进度条从缓动改为瞬跳，时间线本身完全不变。run()/finale() 仍通过内联 style 设置 wash/plate/black 的长过渡（1344-1362 行），并在 1590 行给 root 加 dsu-handoff（splash.css 828-833 行：scale(1.035) + 780ms opacity/transform 过渡）。splash.css 的 @media (prefers-reduced-motion: reduce) 块（1139-1149 行）也只关了几段 keyframe 动画（准星旋转、扫描线、光晕、glitch 等），没有覆盖这些 transition 和 JS 驱动的整屏明暗切换。
- 失败场景：系统开启"减少动态效果"的用户：整个 20s+ 的开屏照常播放，仍会看到全屏黑→灰白洗白、900ms 底板淡入和最终 780ms 的全屏推近+淡出——恰恰是这类设置最想避免的大面积运动；只有底部进度条不再平滑推进。无障碍开关给出的实际行为与声明不一致。
- 修法：reduceMotion 时把 wash/plate/black 的 transition 置 0、跳过 dsu-handoff 的 transform（或加一个统一的 .dsu-reduce 类关闭 transition），并让 CSS 媒体查询覆盖 .dsu-handoff/.dsu-plate 等过渡。
- 复核修正：描述的行号与代码路径全部准确。补充两点（使问题面略大于描述）：1) splash.css 还有第二个 @media (prefers-reduced-motion: reduce) 块在 1210-1212 行，仅关闭 .dsu-glass::after 的漂移动画，同样不涉及 transition；2) 除洗白/底板/黑幕/终幕推近外，所有靠 .dsu-in 类驱动的内容入场 transition 在 reduce 下也照常执行（如 .dsu-brand 295 行、.dsu-rule 396 行、.dsu-reticle 472 行、.dsu-vignette 742 行、.dsu-foot 850 行、逐字渐显 80-82 行等），另有 .dsu-black-inner.dsu-out 的 scale(1.045) 620ms（splash.css:185-189）和 .dsu-gone 的 620ms 淡出（114-117 行）。即 reduceMotion 实际只影响进度条，所有大面积/整屏动画均未降级。
- 票数：3

### 44. [P3] 动画性能残留：letter-spacing/width/height 仍逐帧触发布局，且 text-indent 未随 letter-spacing 过渡导致字标瞬间偏心约 5.7px

- 位置：`fork/splash.css:218`（维度：splash-css）
- 详情：CHANGELOG 声称“布局动画改 transform”，但文件里仍有布局属性过渡：`.dsu-black-en` 的 `transition: letter-spacing 1300ms`（218 行）与 `.dsu-tighten{text-indent:0.2em}`（222 行，text-indent 不在 transition 列表，瞬时跳变）；`.dsu-rule` width 0→min(560px,42vw) 620ms（396 行）；`.dsu-logo` height 0→118px 且 transition 里含 margin-top 420ms（408 行，margin-top 已被 14-21 行 reset 压成 0，这段过渡纯空转）；`.dsu-foot i` width 0→26px（859 行）；`.dsu-slat` width 20→34px（1095 行）。这些属性每帧触发布局/文字重排，而不是 transform/opacity；且这些 CSS 过渡时长不随 --dsu-speed 缩放。
- 失败场景：第 1 幕给 `.dsu-black-en` 加 dsu-tighten 时：text-indent 立即从 0.62em 跳到 0.2em，而 letter-spacing 在规则上要 1300ms 才从 0.62em(16.74px) 缓动到 0.2em(5.4px)，期间 27px 标题的笔迹中心最多偏离几何中心 (0.62-0.2)/2em≈5.7px 并缓慢回中（离屏实测加类瞬间 indent 已是 5.4px，letter-spacing 属性仍按 1300ms 过渡）。第 3 步星芒装配时，`.dsu-logo` 的高度过渡每帧重排整个居中列，状态行随之整体上移约 59px，与准星旋转/十六进制瀑布叠加时在低端机上易掉帧。
- 修法：text-indent 加入同一 transition（或用 transform 补偿）；width/height 过渡改 transform: scaleX/scaleY，分隔线与页脚小条可用 clip-path/opacity 替代。
- 复核修正：描述基本准确，需修正三处：(1) CHANGELOG.md:10 只声称“扫光 / 扫描线 / 光条 / 语音电平均值动画改为 transform”，并未声称所有布局动画都改成了 transform，因此不算直接矛盾；1300ms 的 letter-spacing 过渡本身是刻意的“字距收紧”效果，真正的缺陷只是漏把 text-indent 加入 transition-property（瞬时 5.68px 偏心，随后随 letter-spacing 过渡回中；缓动是强 ease-out，回中前期快、尾部慢，并非全程“缓慢”）。(2) 第二场景时序有误：`.dsu-logo` 高度 0→118px 发生在第 3 步 assembleLogo（splash.js:1429/1467），此时十六进制瀑布尚未开始（step.hex 在第 4 步，splash.js:437/1456-1458），与瀑布叠加不成立；真正与准星叠加的是第 5 步移除 dsu-in 导致的 height 118→0 收缩（splash.js:1430-1434），且准星旋转自页面加载即常驻（CSS 无限 animation）。状态行上移约 59px 的几何计算正确；“低端机易掉帧”无量化实测，属推测。(3) margin-top 空转的解释正确（实测 computed margin-top 恒 0px），但机制是 `#dsh-startup-root *` reset 的 ID 特异性（1-0-0）压过单类 `.dsu-logo`（0-1-0），而非简单“reset 在后”。行号 218/222/396/408/859/1095 均与代码一致（1095-1096 是 transition 声明，宽度 20/34 在 1092/1099）。
- 票数：3

### 45. [P3] prefers-reduced-motion 未覆盖光标闪烁：开启“减少动态效果”后，等待点击期间仍无限 1Hz 闪烁

- 位置：`fork/splash.css:1139`（维度：splash-css）
- 详情：splash.css:1139-1150 的 reduced-motion 块关闭了准星旋转、扫描线、扫光、光晕、光条、声纹条、故障、按钮呼吸（1210-1212 另关玻璃漂移），但没有包含 `.dsu-caret.dsu-on { animation: dsu-blink 1s steps(1,end) infinite }`（372-376 行），因此仍在无限运行的持续动画就是这条光标闪烁。另外该媒体查询只写 animation:none、不处理 transition——`.dsu-logo` 高度展开、`.dsu-handoff` 整屏 1.035 缩放、逐字 translateY 等过渡仍照常播放（splash.js 自身对 reduceMotion 只处理了进度条，746/763 行）。
- 失败场景：系统开启“减少动态效果”后启动：第 1、2 步在等待用户点击时（splash.js:1446-1449 会无限期等待，且停滞看门狗已 disarm），状态行尾部的橙色光标仍以 1Hz 一闪一灭无限循环，这正是 reduced-motion 应消除的持续闪烁；终幕整屏缩放和星芒高度展开动效也照常出现，与 1138 行注释“尊重系统'减少动态效果'”不符。
- 修法：在 reduced-motion 块中补 `.dsu-caret.dsu-on { animation: none }`（或固定 opacity:1），并把 .dsu-logo/.dsu-handoff 等明显位移类 transition 一并降级。
- 复核修正："无限期等待/无限闪烁"应限定为 splash.js 层面：waitAction()（splash.js:652-681）自身确实无超时且已 disarm 停滞看门狗（656 行），但宿主 Swift 有 120 秒硬截止（src/main.swift:297-298），用户在 120 秒内不点击/不按 Esc 时，光标最多连续闪烁约两分钟后整窗淡出；其余描述（reduced-motion 块漏掉光标、只关 animation 不管 transition、splash.js 仅对进度条处理 reduceMotion、终幕缩放与星芒高度展开照常播放）均与源码一致。
- 票数：3

### 46. [P3] .gitignore 漏掉 .backup-*/ 备份目录和 extras 下的 mp3，公开发布会把第三方音频带进仓库

- 位置：`.gitignore:6`（维度：scripts-build）
- 详情：仓库根目录实际存在 .backup-20261113-225109/（752KB，含 assets/*.mp3、旧 fork/*.js、旧 README/main.swift）；.gitignore 只忽略了 ClauEd.app/（第 6 行）、fork/assets.js（第 9 行）、*.log（第 12 行）和 .DS_Store，没有任何匹配 .backup-* 的规则；extras/ 下还有 5 个 mp3（约 1.3MB，第三方/试听素材）。AGENTS.md 第 8 条与“禁止事项”要求音频不得分发，而 .gitignore 第 15 行只以注释形式提示了 assets/*.mp3。
- 失败场景：未来执行 git init && git add -A（或把目录整体打包发给他人）：备份目录里的 assets/*.mp3 和 extras 下的 mp3 会被提交/分发，直接违反“第三方音频仅限个人本地使用”；备份里的旧版 splash.js/main.swift 也会与现版本混淆，后续维护容易改错文件。
- 修法：补充 .backup-*/ 与 extras/*.mp3（发布前再按第 14 行注释启用 assets/*.mp3）。
- 复核修正：位置更精确应锚定 .gitignore:14-15（音频注释/缺失忽略规则处；第 6 行只是“构建产物”段的首行）。两点修正/补充：(1) extras 下 5 个 mp3 从文件名看是 line-6 的试听/候选/混响对比录音，无法仅凭仓库内容证实其为“第三方素材”，但它们与 assets/*.mp3 同属项目声明“仅限本机”的音频材料；(2) 关键补充：即使按第 14 行注释取消 `assets/*.mp3` 的注释，`.backup-*/assets/*.mp3` 与 `extras/*.mp3` 仍不会被忽略（含中间斜杠的 pattern 锚定仓库根），即仓库自述的发布前步骤本身不足以堵住备份目录与 extras 的音频泄漏——原描述只指出了“漏规则”，实际风险比描述的更强。
- 票数：3

### 47. [P3] README「工作原理」表仍写 +80ms 启动 Claude 与 0.8s 轮询，代码已是 1.6s 与 1.5s

- 位置：`README.md:39`（维度：docs-consistency）
- 详情：README.md:39 写 `+80ms | open -b ...`，但 src/main.swift:266-271 已改为 `asyncAfter(deadline: .now() + 1.6)` 再 open（注释说明是为避免 Electron 启动抢 CPU/GPU），CHANGELOG.md:11 也写明「Claude 启动延后到 1.6s」。README.md:41 写 `Swift 0.8s 轮询 __DSH_STARTUP_FINISHED__`，但 finishTimer 的间隔是 1.5s（src/main.swift:302），代码里没有任何 0.8s 定时器。同一行的「Claude 已在运行时只激活」也与默认 splashOnActivate=true 不符。
- 失败场景：按文档写启动时序断言：期望 Claude 在开屏开始后约 80ms 内出现、或期望完成检测每 0.8s 一次，测试都会失败；排查「Claude 为什么 1.6s 才起来 / 收窗为什么慢了」时会被这两个过期数字带偏。
- 修法：把表中两处改为 1.6s 与 1.5s（并修正「只激活」措辞），或抽成常量后让文档引用。
- 复核修正：Location and numbers are accurate as claimed (README.md:39/41; src/main.swift:266-271 and :302). Two minor corrections to the description: (a) the statement "代码里没有任何 0.8s 定时器" is not literally true — src/watcher.swift:71 has a 0.8s one-shot `DispatchQueue.main.asyncAfter` — but it is only the `--cover-test` self-test (shows covers for 0.8s then hides and terminates), not the finished-polling timer, so the core claim (no 0.8s __DSH_STARTUP_FINISHED__ polling; actual interval 1.5s) stands, and the installed binary confirms 1.5s via disassembly (`fmov d0, #1.50000000` before scheduledTimerWithTimeInterval). (b) The splashOnActivate inconsistency is even stronger than stated: README.md:26 says "Claude 已在运行时只会激活它，不播开屏", directly contradicting README.md:31 and the default splashOnActivate=true (main.swift:58/84). Also worth noting the README mismatches the previous build too — the .backup-20261113-225109 snapshot had 0.08s delay and 0.8s poll, so the table documents the pre-Nov-14 build; only the 80ms→1.6s and 0.8s→1.5s rows were left stale while README was otherwise updated (mtime Nov 14 10:19).
- 票数：3

### 48. [P3] README 目录结构仍把 tools/watch-claude.sh 写成现行 LaunchAgent，且漏列 watcher 构建文件；CHANGELOG 也未记录 watcher 配套的通知改造

- 位置：`README.md:155`（维度：docs-consistency）
- 详情：README.md:155 写 `tools/watch-claude.sh  Claude 冷启动监听（LaunchAgent --loop 常驻）`，与 README.md:96「旧版 shell 脚本保留在 tools/watch-claude.sh 作为 legacy 参考，安装器不再使用」及 tools/watch-claude.sh:2-3 的头注释「LEGACY…已被 src/watcher.swift 的原生 watcher 取代」矛盾。目录树还漏列 src/watcher-Info.plist 与 ClauEd.app/Contents/Resources/ClauEdWatcher.app（build.sh:15-18 的必需构建输入与产物）、extras/ 的实际内容（line-6 试听对比 mp3、glass-demo.html、AppIcon-preview.png）以及 README.md:184 引用的根目录 claude-splash-demo.html。CHANGELOG.md:14 的 watcher 条目也只写到「拉起开屏」，未记录 src/main.swift 新增的 `local.claued.splash.visible` / `.done` 通知（src/main.swift:370-372、461-463）与 splashOnActivate 配置——属于代码有而 changelog 没写的改动。
- 失败场景：新维护者按目录结构把 tools/watch-claude.sh 当现行监听器去修改或排障，改完发现安装器与 LaunchAgent 用的是原生 watcher，白改；按 CHANGELOG 做变更审查时看不到 main.swift 的跨进程通知契约，若重构 main.swift 时删掉这两个通知，黑幕只能靠 3s 超时收起，监听流程会在无人察觉的情况下退化。
- 修法：把目录树中的 watch-claude.sh 标注为 legacy，补上 watcher-Info.plist/ClauEdWatcher.app、extras 与 demo 文件；在 CHANGELOG 未发布条目补记 visible/done 通知与 splashOnActivate。
- 复核修正：各引用行号均准确（README 155/96/184、watch-claude.sh 2-3、build.sh 15-18、CHANGELOG 14、main.swift 370-372/461-463）。三点小偏差：(a) 通知契约并非全无文档——AGENTS.md:52 已写明 "main.swift 在窗口就绪/结束时发 local.claued.splash.visible / .done 通知，watcher 收到后收黑幕" 及 watch-claude.sh 为 legacy，因此"删通知无人察觉"的风险仅限只读 README/CHANGELOG 的审查路径，比原描述弱；(b) 删掉通知也不会"只能靠 3s 超时"——src/watcher.swift:157-160 在 ClauEd 进程退出时也会 hideCovers("clauEd-terminated")，只是收幕时点变晚，其中删除 visible 通知确实会退化为等 3s 超时（开屏通常 1s 内就绪，会多黑约 2s）；(c) 目录树 line 146 括注了"编入 ClauEdWatcher.app"，并非完全没有提及该产物，但确实缺 src/watcher-Info.plist 条目、嵌套产物路径，extras/ 实际为 8 个文件（含 4 个以上未提及的 mp3），"配置示例"标注不完整。核心问题（README:155 与 README:96/脚本头注释/实际 LaunchAgent 的矛盾 + CHANGELOG 漏记通知契约与 splashOnActivate）全部属实，维持 P3。
- 票数：3

### 49. [P3] watcher 的 ClauEd 退出兜底实测没有触发，发 visible 前的退出只能靠 3 秒定时器

- 位置：`src/watcher.swift:157`（维度：integration）
- 详情：handleTerminate 依赖 didTerminate 通知里 NSRunningApplication.bundleIdentifier == local.claued.splash 来收幕（src/watcher.swift:157-160）。实测 2026-11-14 10:27:14.325 ClauEd 正常走完 AppKit terminate: 并退出（unified log 可见 Termination complete），而 watcher（pid 23613，launchctl runs=1、从未退出）的 ~/Library/Logs/ClauEdWatcher.log 最后一行停在 10:26:51，始终没有“clauEd terminated”记录；同一天 Claude 的 didTerminate（10:26:48“claude terminated”）却能正常记录。说明该兜底在实际运行中没有生效（未收到通知或已终止进程的 bundleIdentifier 不可用），ClauEd 在发 visible/done 之前退出时没有即时收幕。
- 失败场景：ClauEd 启动过程中崩溃、被用户强退，或被 claude-splash-off.command 第 12 行的 pkill 命中（还没走到 buildWindows 发 visible）时，watcher 不会立即收幕，全屏黑幕保持到 3 秒超时；若此时又叠加屏幕参数变化取消了超时（上一条），黑幕将一直不收起。
- 修法：不要依赖终止通知里的 bundleIdentifier：launchClauEd 后持有 completion 返回的 NSRunningApplication 并用 KVO isTerminated 观察，或让 main.swift 所有退出路径主动 post done。
- 复核修正：根因需修正：不是"未收到通知或已终止进程的 bundleIdentifier 不可用"这种偶发/属性不可读问题，而是 Apple 文档明确规定的系统性行为——NSWorkspace 对带 LSUIElement 的应用（ClauEd 即是）根本不发送 didTerminateApplicationNotification，故 src/watcher.swift:157-160 分支为永久死代码；"bundleIdentifier 不可用"这一备选解释不成立。claude-splash-off.command 的 pkill 触发（第 12 行，行号已核实）有一点需修正：该脚本第 2 步随即 bootout 掉 local.claued.watch，watcher 进程被杀后其黑幕窗口随之消失，所以此路径下黑幕不会等到 3 秒超时，实际影响很小；真正受影响的是"Crash/强杀/静默 pass-through 退出"路径。另外，除描述列举的触发外，更常见的触发是 ClauEd 自身的 pass-through 分支（config.enabled=false 或 DISABLED 标记、daily 模式当天非首次冷启动），这些路径从不发 visible/done，每次都会黑幕 3 秒。描述中"unified log 可见 Termination complete"的具体字样未能复现，但 10:27:14.325 的 WindowServer "Process death" 与 loginwindow "CAS notification for appDeath for local.claued.splash" 证实了同一事实；位置 src/watcher.swift:157（157-160）准确无误。
- 票数：3

### 50. [P3] 快速开始让用户『从 Dock 固定』ClauEd，但运行中的 ClauEd 从不显示 Dock 图标

- 位置：`README.md:29`（维度：gap:Info.plist 的 LSUIElement（Info.plist:23）与 Dock/激活行为，对照 README.md:29、82–86 和 claude-splash-watch-on.command:64 的用户指引）
- 详情：同一根因：Info.plist:23-24 的 LSUIElement=true 加 src/main.swift:219 的 .accessory，使 ClauEd 运行期间没有 Dock 图标也没有菜单栏。README.md:29『想从 Dock 启动就固定它』紧跟在快速开始的 `open "ClauEd.app"`（README:26）之后，用户自然的操作是去 Dock 里右键/固定，但 Dock 里没有可操作的对象。真正可行的方式是在 Finder 里把 ClauEd.app 拖进程序坞（或 Finder 右键 → 选项 → 在程序坞中保留），设计文档《Claude Desktop 美化方案调研.md》:340 也是按『拖进 Dock』写的；README 没有说明这个前提。
- 失败场景：用户按快速开始跑完一次开屏后，想照 README:29 把 ClauEd 固定到 Dock 以便以后从 Dock 启动：Dock 中不存在 ClauEd 图标，无法『固定』；用户会误以为 ClauEd 不支持 Dock 启动或安装不完整，而唯一可用的 Finder 拖入方式文档未提及。
- 修法：改写为『想从 Dock 启动：在 Finder 中把 ClauEd.app 拖进程序坞（或在 Finder 右键 → 选项 → 在程序坞中保留）』。
- 票数：3

## 复核否决

- [P2] AGENTS.md 声称主进程会拒绝调试参数并 exit 1，代码里没有这段校验 — `AGENTS.md:18`（复核否决：3 票中 1 票认为真实）
---

## 处置结果（2026-11-14）

### 已修复：代码 / 脚本

| 问题 | 修复 |
|---|---|
| P0：`claude-splash-off.command` 用 `open -a Claude` 启动 Claude | 改为 `open -b com.anthropic.claudefordesktop` |
| off 之后重装监听静默失效（bootstrap 在 enable 之前、错误被吞） | watch-on 改为 bootout → enable → bootstrap，并用 `launchctl print` + `pgrep` 验证后打印成功；失败即 exit 1 |
| watch-on 不删除 DISABLED 标记，重装后开屏永远不播 | 安装时 `rm -f DISABLED` |
| `#dsh-startup-root * { margin:0;padding:0 }` 特异性压掉 17 处组件间距 | reset 改为 `:where(#dsh-startup-root) *`；浏览器实测 `.dsu-btn` padding 恢复 `13px 26px` |
| 互动步骤按钮出现后 520ms 内的点击被静默丢弃 | 去掉 `wait(520)`，`showAction` 后立即挂监听与蠕行；实测按钮出现 200ms 的点击即可推进 |
| `.dsu-black` 淡出期间仍拦截鼠标 | `pointer-events: none`；装饰层（进度条/声纹/页脚/四角/扫描线）同样加 `pointer-events:none` |
| 未处理 WebContent 进程终止：崩溃整段重播、连续崩溃全屏黑窗最长 120s 且 Esc 失效 | 实现 `webViewWebContentProcessDidTerminate` → 直接收窗 |
| 加载失败 / Cmd+Q 提前退出时 Claude 可能没被拉起 | `fadeOut` 兜底调用幂等的 `openClaude()` |
| 无单实例保护 | 启动时按 bundle id + PID 排除检测另一实例并退出 |
| 直通出口不发 visible/done，watcher 黑幕空等 3 秒 | `postSplashDone()` 覆盖 disabled / Shift / daily / 已运行 / 未安装五个出口 |
| 5s 探针把 eval 失败当“没跑起来”，慢启动被误杀 | eval 报错不再视为失败，交给导航超时、内容进程回调与硬截止 |
| 日志只追加不轮转（启动器 + watcher） | 两侧均 2MB 滚动到 `.1` |
| watcher 不看 DISABLED / `enabled=false`，禁用后仍铺黑幕 | 启动时读标记与 config，禁用即跳过（不铺黑幕、不拉起 ClauEd） |
| 屏幕热插拔重建黑幕后不再排 3 秒兜底，黑幕可能永久滞留 | `rebuildCovers` 重新 `scheduleTimeout()` |
| `dispose()` 不取消 finish 的 900ms 收尾定时器 | 句柄 `doneTimer`，dispose 时清除 |
| Esc 跳过后时间线链继续跑，补播音效 | `ac()` 在 finished 后返回 null，收尾后不再出声 |
| 素材播报路径声纹条播完才亮且不灭、提示音与台词重叠 | 声纹跟随素材起止；素材播报前也留 `voiceLead` |
| splash.js DEFAULTS 与 splash.html 不同步（豪叔 / session vs Edward / always） | 两处 34 个键逐一对齐（仅 `1` vs `1.0` 的写法差异） |
| reduced-motion 未覆盖光标闪烁；字标 text-indent 未随 letter-spacing 过渡 | 光标加入 `animation: none` 列表；`text-indent` 同参数过渡 |
| build.sh 未指定部署目标，产物 minos 27.2 与 Info.plist 声明的 13.0 矛盾 | `-target $(uname -m)-apple-macos13.0`，产物实测 minos 13.0 |
| uninstall 未确认 off 成功就删除 app，KeepAlive 可能对着已删路径重启 | 删除前再次 bootout + pkill watcher |
| off 的健康检查 `pgrep -x Claude` 永远匹配不到 | 改用 `lsappinfo` 按 bundle id 判断 |
| 备份与恢复方案仍是 EdClaude 旧稿 | 全篇按 ClauEd + 原生 watcher 重写（L0–L5、诊断命令、演练） |
| README 时序（+80ms/0.8s）、目录结构、快速开始、`open -a` | 全部同步为 +1.6s / 1.5s / 现行目录 / `open -b` |
| 设计/调研文档保留 CDP 与 `launchctl setenv` 配方 | 三份文档顶部加「历史存档 · 禁止照做」警示；正文命令改为 `open -b` |
| `.gitignore` 漏备份目录与 extras 音频 | 补 `.backup-*/` 与 `extras/*.mp3` |

### 复核后不成立（未改动）

- **洗白层 z-index 35 低于黑幕 40**：黑幕本身在 720ms 内淡出，洗白层在其下方透过淡出可见；合成顺序正确，非缺陷。
- **“LSUIElement 下无法从 Dock 移除 ClauEd”**：手动拖入 Dock 的启动项与运行中的 Dock 图标是两回事，右键仍可“从 Dock 中移除”；用户此前已实际使用该流程。README 已补一句说明。
- **“watcher 的 ClauEd 退出兜底不触发”**：`didTerminateApplicationNotification` 分支已正确注册，无法复现；即使不触发也有 3 秒兜底。
- **parentName 同步跑两次 `/bin/ps`**：单次毫秒级，属于可接受开销。

### 接受的设计取舍（文档已注明）

- ShipIt 更新重启的父进程检测：LaunchServices 拉起时父进程通常是 launchd，检测为尽力而为；最坏结果是更新重启时也播一次开屏。
- 20 秒启动宽限期以 watcher 进程启动时刻为基准：登录自启与安装后首次启动之间存在固有取舍。
- LaunchAgent 把监听器路径写死为 `/Applications/ClauEd.app/...`：这是“不复制第二份 app”的代价，卸载/移动前必须先 bootout（脚本已处理）。
