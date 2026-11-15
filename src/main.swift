import Cocoa
import WebKit

// ============================================================================
// Claude Splash — 外挂开屏启动器
// 只做四件事：显示全屏壳窗口 → open -b com.anthropic.claudefordesktop（不带任何参数）
// → 播放动画 → 淡出。不修改 Claude 的任何文件；Claude 已在运行则只激活不重启；
// 任何失败只关自己的窗口。
// ============================================================================

private let kClaudeBundleID = "com.anthropic.claudefordesktop"
private let kClauEdBundleID = "local.claued.splash"

// MARK: - 日志

private let logPath: String = {
    let dir = ("~/Library/Logs" as NSString).expandingTildeInPath
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    return dir + "/ClaudeSplash.log"
}()

private let logDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return f
}()

private let dayDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    return f
}()

private func logLine(_ message: String) {
    let line = "[\(logDateFormatter.string(from: Date()))] \(message)\n"
    guard let data = line.data(using: .utf8) else { return }
    /* 日志只追加不轮转，长期使用会无限增长：超过 2MB 就滚到 .1（只留一代） */
    if let attrs = try? FileManager.default.attributesOfItem(atPath: logPath),
       let size = attrs[.size] as? Int, size > 2_000_000 {
        try? FileManager.default.removeItem(atPath: logPath + ".1")
        try? FileManager.default.moveItem(atPath: logPath, toPath: logPath + ".1")
    }
    if let h = FileHandle(forWritingAtPath: logPath) {
        h.seekToEndOfFile()
        h.write(data)
        h.closeFile()
    } else {
        FileManager.default.createFile(atPath: logPath, contents: data)
    }
}

// MARK: - 配置

private struct SplashConfig {
    var enabled = true
    var displayMode = "always"        // always | daily
    var themeOverride = "auto"        // auto | light | dark
    var darkWash = "soft"             // soft | faithful
    var speed: Double = 1.0
    var requireInteraction = true
    var voice = true
    var sound = true
    var identity = "OPERATOR"
    var identityId = "auto"           // auto/date = 当天日期 YYYYMMDD，其余为静态代号
    var accessLevel = "auto"          // auto = 最近 Code 会话的模型名，其余为手动覆盖
    var splashOnActivate = true
}

func supportDir() -> URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    let dir = base.appendingPathComponent("ClaudeSplash", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

func defaultConfigObject() -> [String: Any] {
    return [
        "enabled": true,
        "displayMode": "always",
        "themeOverride": "auto",
        "darkWash": "soft",
        "speed": 1.0,
        "requireInteraction": true,
        "voice": true,
        "sound": true,
        "identity": "OPERATOR",
        "identityId": "auto",
        "accessLevel": "auto",
        "voiceGreeting": "Welcome to Anthropic's Claude. It's been a while.",
        "welcomeTemplate": "欢迎 {identity} 访问",
        "labelIdentity": "用户名称",
        "labelIdentityId": "会话编号",
        "labelAccessLevel": "访问等级",
        "splashOnActivate": true
    ]
}

private func writeDefaultConfigIfNeeded(_ url: URL) {
    guard !FileManager.default.fileExists(atPath: url.path) else { return }
    guard let data = try? JSONSerialization.data(withJSONObject: defaultConfigObject(), options: [.prettyPrinted, .sortedKeys]) else { return }
    try? data.write(to: url, options: .atomic)
}

func readConfigObject() -> [String: Any] {
    let url = supportDir().appendingPathComponent("config.json")
    writeDefaultConfigIfNeeded(url)
    guard let data = try? Data(contentsOf: url),
          let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    else { return defaultConfigObject() }
    return obj
}

private func loadConfig() -> SplashConfig {
    var cfg = SplashConfig()
    let obj = readConfigObject()
    if let v = obj["enabled"] as? Bool { cfg.enabled = v }
    if let v = obj["displayMode"] as? String { cfg.displayMode = v }
    if let v = obj["themeOverride"] as? String { cfg.themeOverride = v }
    if let v = obj["darkWash"] as? String { cfg.darkWash = v }
    if let v = obj["speed"] as? Double { cfg.speed = v }
    if let v = obj["speed"] as? Int { cfg.speed = Double(v) }
    if let v = obj["requireInteraction"] as? Bool { cfg.requireInteraction = v }
    if let v = obj["voice"] as? Bool { cfg.voice = v }
    if let v = obj["sound"] as? Bool { cfg.sound = v }
    if let v = obj["identity"] as? String { cfg.identity = v }
    if let v = obj["identityId"] as? String { cfg.identityId = v }
    if let v = obj["accessLevel"] as? String { cfg.accessLevel = v }
    if let v = obj["splashOnActivate"] as? Bool { cfg.splashOnActivate = v }

    /* 枚举值校验：配置写错时回到安全的默认行为 */
    if cfg.displayMode != "always" && cfg.displayMode != "daily" { cfg.displayMode = "always" }
    if cfg.themeOverride != "auto" && cfg.themeOverride != "light" && cfg.themeOverride != "dark" {
        cfg.themeOverride = "auto"
    }
    if cfg.darkWash != "soft" && cfg.darkWash != "faithful" { cfg.darkWash = "soft" }
    return cfg
}

// MARK: - 每日一次

private func dayString() -> String {
    dayDateFormatter.string(from: Date())
}

private func stateURL() -> URL { supportDir().appendingPathComponent("state.json") }

private func shouldSkipForDaily(_ cfg: SplashConfig) -> Bool {
    guard cfg.displayMode == "daily" else { return false }
    guard let data = try? Data(contentsOf: stateURL()),
          let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
          let last = obj["lastShown"] as? String
    else { return false }
    return last == dayString()
}

private func markShownToday() {
    let dict: [String: Any] = ["lastShown": dayString()]
    if let data = try? JSONSerialization.data(withJSONObject: dict) {
        try? data.write(to: stateURL())
    }
}

// MARK: - 主题解析：Claude 自己的偏好 → 系统外观 → 手动覆盖

private func mtime(_ url: URL) -> Date {
    (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
}

private func claudeUserThemeMode() -> String? {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let candidates = [
        "Library/Application Support/Claude-3p/config.json",
        "Library/Application Support/Claude/config.json"
    ]
    .map { home.appendingPathComponent($0) }
    .filter { FileManager.default.fileExists(atPath: $0.path) }
    .sorted { mtime($0) > mtime($1) }

    guard let url = candidates.first,
          let data = try? Data(contentsOf: url),
          let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    else { return nil }
    return obj["userThemeMode"] as? String
}

private func resolveTheme(_ cfg: SplashConfig) -> String {
    if cfg.themeOverride == "light" || cfg.themeOverride == "dark" { return cfg.themeOverride }
    if let mode = claudeUserThemeMode() {
        if mode == "dark" { return "dark" }
        if mode == "light" { return "light" }
    }
    let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    return dark ? "dark" : "light"
}

// MARK: - 会话代号与访问等级（模型）

private let compactDayFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyyMMdd"
    return f
}()

/// identityId = auto/date → 当天日期（本地时区）；其余原样返回
private func resolveIdentityId(_ cfg: SplashConfig) -> String {
    let raw = cfg.identityId.trimmingCharacters(in: .whitespacesAndNewlines)
    if raw.caseInsensitiveCompare("auto") == .orderedSame || raw.caseInsensitiveCompare("date") == .orderedSame {
        return compactDayFormatter.string(from: Date())
    }
    return cfg.identityId
}

private struct SessionModel {
    let model: String
    let effort: String?
}

/// 最近聚焦的 Code 会话：只读 local_*.json 的 model/effort/lastFocusedAt/isArchived，
/// 不读 title 或任何会话内容。
private func latestSessionModel() -> SessionModel? {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let roots = ["Claude-3p", "Claude"].map {
        home.appendingPathComponent("Library/Application Support/\($0)/claude-code-sessions")
    }
    let fm = FileManager.default
    var bestFocus = -Double.infinity
    var best: SessionModel?
    for root in roots where fm.fileExists(atPath: root.path) {
        guard let en = fm.enumerator(at: root,
                                     includingPropertiesForKeys: [.contentModificationDateKey],
                                     options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
        for case let url as URL in en {
            let name = url.lastPathComponent
            guard name.hasPrefix("local_"), name.hasSuffix(".json") else { continue }
            guard let data = try? Data(contentsOf: url),
                  let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  obj["isArchived"] as? Bool != true,
                  let model = obj["model"] as? String, !model.isEmpty
            else { continue }
            let focus = (obj["lastFocusedAt"] as? NSNumber)?.doubleValue ?? 0
            if focus > bestFocus {
                bestFocus = focus
                best = SessionModel(model: model, effort: obj["effort"] as? String)
            }
        }
    }
    return best
}

/// claude-fable-5[1m] + max → FABLE 5 · MAX
private func prettyModel(_ s: SessionModel) -> String {
    var m = s.model.replacingOccurrences(of: "[1m]", with: "", options: .caseInsensitive)
    for prefix in ["anthropic/", "claude-"] where m.lowercased().hasPrefix(prefix) {
        m = String(m.dropFirst(prefix.count))
    }
    m = m.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
    var out = m.split(separator: " ").joined(separator: " ").uppercased()
    if let e = s.effort?.trimmingCharacters(in: .whitespacesAndNewlines), !e.isEmpty {
        out += " · " + e.uppercased()
    }
    if out.count > 30 {
        out = String(out.prefix(30)).trimmingCharacters(in: .whitespaces)
    }
    return out.isEmpty ? "PRO" : out
}

/// accessLevel = auto → 最近 Code 会话的模型名；读不到回退 PRO；其余视为手动覆盖
private func resolveAccessLevel(_ cfg: SplashConfig) -> String {
    let raw = cfg.accessLevel.trimmingCharacters(in: .whitespacesAndNewlines)
    guard raw.caseInsensitiveCompare("auto") == .orderedSame else { return cfg.accessLevel }
    guard let s = latestSessionModel() else { return "PRO" }
    return prettyModel(s)
}

// MARK: - JS 注入

private func splashInjection(theme: String, config: SplashConfig,
                             identityId: String, accessLevel: String) -> String {
    var obj = readConfigObject()
    obj["theme"] = theme
    obj["speed"] = max(0.35, min(3.0, config.speed))
    obj["requireInteraction"] = config.requireInteraction
    obj["voice"] = config.voice
    obj["sound"] = config.sound
    obj["identity"] = config.identity
    obj["identityId"] = identityId
    obj["accessLevel"] = accessLevel
    obj["darkWash"] = config.darkWash
    guard let data = try? JSONSerialization.data(withJSONObject: obj),
          var json = String(data: data, encoding: .utf8)
    else { return "{}" }
    json = json.replacingOccurrences(of: "\u{2028}", with: "\\u2028")
        .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
    return json
}

private func activateApp() {
    if #available(macOS 14.0, *) {
        NSApp.activate()
    } else {
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - 窗口

final class SplashWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - AppDelegate

final class AppDelegate: NSObject, NSApplicationDelegate, WKScriptMessageHandler, WKNavigationDelegate {
    private var window: NSWindow?
    private var settingsController: SettingsWindowController?
    private var auxiliaryWindows: [NSWindow] = []
    private var webView: WKWebView?
    private var keyMonitor: Any?
    private var finishTimer: Timer?
    private var pollTicks = 0
    private var fadingOut = false
    private var navigationFinished = false
    private var config = SplashConfig()
    private var resolvedIdentityId = ""
    private var resolvedAccessLevel = ""
    private var claudeAlreadyRunning = false
    private var claudeLaunchRequested = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let settingsRequested = ProcessInfo.processInfo.arguments.contains("--settings")
            || NSEvent.modifierFlags.contains(.option)
        if settingsRequested {
            postSplashDone()
            NSApp.setActivationPolicy(.regular)
            let controller = SettingsWindowController()
            settingsController = controller
            controller.show()
            return
        }

        /* 单实例保护：二进制被直接重复拉起时，不叠第二个 screenSaver 级全屏窗 */
        let me = ProcessInfo.processInfo.processIdentifier
        if NSRunningApplication.runningApplications(withBundleIdentifier: kClauEdBundleID)
            .contains(where: { $0.processIdentifier != me }) {
            logLine("another ClauEd instance is running -> exit")
            NSApp.terminate(nil)
            return
        }

        config = loadConfig()

        let disabledMarker = supportDir().appendingPathComponent("DISABLED").path
        if !config.enabled || FileManager.default.fileExists(atPath: disabledMarker) {
            logLine("disabled -> pass-through")
            postSplashDone()
            openClaude()
            NSApp.terminate(nil)
            return
        }

        if NSEvent.modifierFlags.contains(.shift) {
            logLine("shift held -> pass-through")
            postSplashDone()
            openClaude()
            NSApp.terminate(nil)
            return
        }

        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: kClaudeBundleID) != nil else {
            logLine("Claude not installed -> exit")
            postSplashDone()
            NSApp.terminate(nil)
            return
        }

        if shouldSkipForDaily(config) {
            logLine("daily already shown -> pass-through")
            postSplashDone()
            openClaude()
            NSApp.terminate(nil)
            return
        }

        claudeAlreadyRunning = !NSRunningApplication
            .runningApplications(withBundleIdentifier: kClaudeBundleID).isEmpty
        if claudeAlreadyRunning && !config.splashOnActivate {
            logLine("Claude already running -> activate & exit")
            postSplashDone()
            activateClaude()
            NSApp.terminate(nil)
            return
        }

        let theme = resolveTheme(config)
        resolvedIdentityId = resolveIdentityId(config)
        resolvedAccessLevel = resolveAccessLevel(config)
        logLine("show theme=\(theme) speed=\(config.speed) alreadyRunning=\(claudeAlreadyRunning) identityId=\(resolvedIdentityId) accessLevel=\(resolvedAccessLevel)")
        buildWindows(theme: theme)
        markShownToday()
        if !claudeAlreadyRunning {
            /* 让开屏先拿到第一帧再启动 Claude：Electron 启动会抢 CPU/GPU，
               过去 80ms 就 open 是首幕卡顿的主要来源 */
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
                self?.openClaude()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    activateApp()
                }
            }
        }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            if event.keyCode == 53 {                      // Esc：立即跳过
                self.requestSkip()
                return nil
            }
            if event.modifierFlags.contains(.command),
               let ch = event.charactersIgnoringModifiers?.lowercased(), ch == "q" {
                self.fadeOut(reason: "cmd-q")
                return nil
            }
            return event
        }

        // 5s 探针：时间线没跑起来就收窗；120s 硬截止（要覆盖交互等待与慢速播放）
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
            self?.checkRunningProbe()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) { [weak self] in
            guard let self = self, !self.navigationFinished, !self.fadingOut else { return }
            logLine("navigation timeout -> fade")
            self.fadeOut(reason: "nav-timeout")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 120.0) { [weak self] in
            self?.fadeOut(reason: "hard-deadline")
        }

        // 完成轮询：不依赖消息桥（引擎的 done 事件在 window 上派发，桥已双保险，这里再兜底）
        finishTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.pollFinished()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        finishTimer?.invalidate()
    }

    // MARK: 界面

    private func buildWindows(theme: String) {
        guard let screen = NSScreen.main else { return }

        let win = SplashWindow(contentRect: screen.frame, styleMask: .borderless,
                               backing: .buffered, defer: false)
        win.level = .screenSaver
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        win.backgroundColor = .black
        win.isOpaque = true
        win.hasShadow = false
        win.isMovable = false
        win.hidesOnDeactivate = false
        win.animationBehavior = .none

        let webConfig = WKWebViewConfiguration()
        webConfig.userContentController.add(self, name: "done")
        webConfig.userContentController.add(self, name: "error")
        webConfig.mediaTypesRequiringUserActionForPlayback = []

        let injection = "window.__DSH_STARTUP__ = \(splashInjection(theme: theme, config: config, identityId: resolvedIdentityId, accessLevel: resolvedAccessLevel));"
        webConfig.userContentController.addUserScript(
            WKUserScript(source: injection, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        )

        let web = WKWebView(frame: screen.frame, configuration: webConfig)
        web.autoresizingMask = [.width, .height]
        web.navigationDelegate = self
        if #available(macOS 13.3, *), ProcessInfo.processInfo.environment["CLAUDESPLASH_DEBUG"] == "1" {
            web.isInspectable = true
        }

        if let url = Bundle.main.url(forResource: "splash", withExtension: "html") {
            web.loadFileURL(url, allowingReadAccessTo: Bundle.main.resourceURL!)
        } else {
            logLine("splash.html missing -> fade")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.fadeOut(reason: "missing-html")
            }
        }

        win.contentView = web
        win.makeKeyAndOrderFront(nil)
        win.orderFrontRegardless()
        activateApp()
        DistributedNotificationCenter.default().post(
            name: Notification.Name("local.claued.splash.visible"), object: nil
        )

        window = win
        webView = web

        // 副屏铺黑，避免露出桌面
        for s in NSScreen.screens where s.frame != screen.frame {
            let aux = NSWindow(contentRect: s.frame, styleMask: .borderless,
                               backing: .buffered, defer: false)
            aux.level = .screenSaver
            aux.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            aux.backgroundColor = .black
            aux.isOpaque = true
            aux.hasShadow = false
            aux.ignoresMouseEvents = true
            aux.hidesOnDeactivate = false
            aux.orderFrontRegardless()
            auxiliaryWindows.append(aux)
        }
    }

    // MARK: Claude

    private func openClaude() {
        guard !claudeLaunchRequested else { return }
        claudeLaunchRequested = true
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-b", kClaudeBundleID]
        do { try p.run() } catch {
            logLine("open Claude failed: \(error.localizedDescription)")
        }
    }

    /// 告诉监听器：黑幕可以收了。所有不播放开屏的直通出口都要发一次，
    /// 否则 watcher 只能等满 3 秒超时，用户会先看到一块没必要的黑屏。
    private func postSplashDone() {
        DistributedNotificationCenter.default().post(
            name: Notification.Name("local.claued.splash.done"), object: nil
        )
    }

    private func activateClaude() {
        guard let app = NSRunningApplication
            .runningApplications(withBundleIdentifier: kClaudeBundleID)
            .first
        else { return }
        if #available(macOS 14.0, *) {
            app.activate()
        } else {
            app.activate(options: [.activateIgnoringOtherApps])
        }
    }

    // MARK: 跳过 / 收窗

    private func requestSkip() {
        logLine("skip requested")
        webView?.evaluateJavaScript(
            "window.__DSH_STARTUP_API__ && window.__DSH_STARTUP_API__.skip()",
            completionHandler: nil
        )
    }

    private func checkRunningProbe() {
        guard let web = webView, !fadingOut else { return }
        web.evaluateJavaScript("window.__DSH_STARTUP_RUNNING__ === true") { [weak self] result, error in
            guard let self = self, !self.fadingOut else { return }
            if error != nil {
                /* 上下文还不可用（页面仍在加载）：不能当成"没跑起来"，否则慢机器会被误杀。
                   真正的失败由导航超时、内容进程终止回调和硬截止兜底。 */
                logLine("running probe eval failed (not fatal)")
                return
            }
            if (result as? Bool) == false {
                logLine("running probe failed -> fade")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.fadeOut(reason: "not-running")
                }
            }
        }
    }

    private func pollFinished() {
        guard let web = webView, !fadingOut else { return }
        pollTicks += 1
        web.evaluateJavaScript(
            "JSON.stringify({finished: !!window.__DSH_STARTUP_FINISHED__, step: (document.querySelector('.dsu-stepcount')||{}).textContent || null})"
        ) { [weak self] result, _ in
            guard let self = self, !self.fadingOut else { return }
            let s = (result as? String) ?? "nil"
            if s.contains("\"finished\":true") {
                logLine("finished poll (\(s)) -> fade")
                self.fadeOut(reason: "finished-poll")
            } else if self.pollTicks % 4 == 0 {
                logLine("progress: \(s)")
            }
        }
    }

    private func fadeOut(reason: String) {
        if fadingOut { return }
        fadingOut = true
        finishTimer?.invalidate()
        finishTimer = nil
        logLine("fade out: \(reason)")
        /* 提前退出（Cmd+Q、加载失败、内容进程崩溃）也要保证 Claude 被拉起：
           正常路径 1.6s 后由定时器拉起，这里兜住更早退出的情况（openClaude 幂等）。 */
        if !claudeAlreadyRunning { openClaude() }
        postSplashDone()

        webView?.evaluateJavaScript(
            "window.__DSH_STARTUP_API__ && window.__DSH_STARTUP_API__.dispose && window.__DSH_STARTUP_API__.dispose()",
            completionHandler: nil
        )

        guard let win = window else {
            finishAndQuit()
            return
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.45
            win.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            self?.finishAndQuit()
        }
    }

    private func finishAndQuit() {
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        auxiliaryWindows.forEach { $0.orderOut(nil) }
        if claudeAlreadyRunning { activateClaude() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApp.terminate(nil)
        }
    }

    // MARK: WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        switch message.name {
        case "done":
            logLine("done event")
            fadeOut(reason: "done")
        case "error":
            logLine("js error: \(message.body)")
        default:
            break
        }
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        navigationFinished = true
        webView.evaluateJavaScript(
            "JSON.stringify({theme: window.__DSH_STARTUP__ && window.__DSH_STARTUP__.theme, speed: window.__DSH_STARTUP__ && window.__DSH_STARTUP__.speed, interact: window.__DSH_STARTUP__ && window.__DSH_STARTUP__.requireInteraction})"
        ) { result, _ in
            logLine("didFinish config: \(result ?? "nil")")
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        logLine("nav failed: \(error.localizedDescription)")
        fadeOut(reason: "nav-failed")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        logLine("provisional nav failed: \(error.localizedDescription)")
        fadeOut(reason: "provisional-nav-failed")
    }

    /* 不实现这个回调时，WebKit 会自动 reload，崩溃一次就从第一幕整段重播（语音也重来）；
       连续崩溃后停在黑窗上，Esc 的 evaluateJavaScript 还会静默失效。直接收窗最稳。 */
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        logLine("web content process terminated -> fade")
        fadeOut(reason: "web-process-terminated")
    }
}

// MARK: - main

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
