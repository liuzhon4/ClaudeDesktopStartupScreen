import Cocoa
import Foundation

// ============================================================================
// ClauEdWatcher — Claude 冷启动监听
// 监听 NSWorkspace 的 didLaunch / didTerminate；Claude 冷启动时：
//   1. 立刻在每个屏幕铺一层全屏黑幕（screenSaver 层级，盖住 Claude 窗口）
//   2. 拉起 ClauEd.app 播放开屏
//   3. 收到 ClauEd 的 splash.visible / splash.done 或超时后收起黑幕
// 只读应用启动状态，不修改 Claude、不改 Dock。
// ============================================================================

private let kClaudeBundleID = "com.anthropic.claudefordesktop"
private let kClauEdBundleID = "local.claued.splash"
private let kSplashVisible = Notification.Name("local.claued.splash.visible")
private let kSplashDone = Notification.Name("local.claued.splash.done")
private let kCoverTimeout: TimeInterval = 3.0
private let kStartupGrace: TimeInterval = 20.0

private let logPath: String = {
    let dir = ("~/Library/Logs" as NSString).expandingTildeInPath
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    return dir + "/ClauEdWatcher.log"
}()

private let logFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    return f
}()

private func log(_ message: String) {
    let line = "[\(logFormatter.string(from: Date()))] \(message)\n"
    guard let data = line.data(using: .utf8) else { return }
    /* 常驻进程，日志无轮转会无限增长：超过 2MB 滚到 .1（只留一代） */
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

/// 与启动器保持同一套开关：DISABLED 标记或 config.json 里 enabled=false 时，
/// watcher 不应铺黑幕、也不应拉起开屏（否则会先黑屏 3 秒再直通，体验更差）。
private func splashDisabled() -> Bool {
    let dir = ("~/Library/Application Support/ClaudeSplash" as NSString).expandingTildeInPath
    if FileManager.default.fileExists(atPath: dir + "/DISABLED") { return true }
    guard let data = FileManager.default.contents(atPath: dir + "/config.json"),
          let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    else { return false }
    if let enabled = obj["enabled"] as? Bool { return !enabled }
    return false
}

final class CoverWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class Watcher: NSObject, NSApplicationDelegate {
    private var covers: [NSWindow] = []
    private var claudeRunning = false
    private var coverShown = false
    private var coverTimeout: DispatchWorkItem?
    private let startedAt = Date()
    private var observers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        log("watcher started pid=\(ProcessInfo.processInfo.processIdentifier)")

        claudeRunning = !NSRunningApplication
            .runningApplications(withBundleIdentifier: kClaudeBundleID).isEmpty
        log("initial claudeRunning=\(claudeRunning) clauEdRunning=\(clauEdIsRunning())")

        buildCovers()
        installObservers()

        if CommandLine.arguments.contains("--cover-test") {
            log("cover test requested")
            showCovers()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                self.hideCovers("cover-test")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { NSApp.terminate(nil) }
            }
        }
    }

    private func installObservers() {
        let wc = NSWorkspace.shared.notificationCenter
        observers.append(wc.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            else { return }
            self?.handleLaunch(app)
        })
        observers.append(wc.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            else { return }
            self?.handleTerminate(app)
        })

        let dc = DistributedNotificationCenter.default()
        dc.addObserver(forName: kSplashVisible, object: nil, queue: .main) { [weak self] _ in
            self?.hideCovers("splash-visible")
        }
        dc.addObserver(forName: kSplashDone, object: nil, queue: .main) { [weak self] _ in
            self?.hideCovers("splash-done")
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.rebuildCovers()
        }
    }

    // MARK: - Claude 事件

    private func handleLaunch(_ app: NSRunningApplication) {
        guard app.bundleIdentifier == kClaudeBundleID else { return }
        log("claude launch pid=\(app.processIdentifier)")
        if claudeRunning {
            log("duplicate launch notification -> ignore")
            return
        }
        claudeRunning = true

        if NSEvent.modifierFlags.contains(.shift) {
            log("shift held -> skip")
            return
        }
        if splashDisabled() {
            log("splash disabled by config -> skip")
            return
        }
        if Date().timeIntervalSince(startedAt) < kStartupGrace {
            log("launch within startup grace -> skip")
            return
        }
        if let parent = parentName(of: app.processIdentifier), parent.contains("ShipIt") {
            log("shipit parent (\(parent)) -> skip")
            return
        }
        if clauEdIsRunning() {
            log("clauEd already running -> keep existing splash")
            return
        }

        showCovers()
        launchClauEd()
        scheduleTimeout()
    }

    /// watcher 自己也在这个 app bundle 里，NSRunningApplication 会把它算作 ClauEd；
    /// 必须排除当前进程，否则永远认为开屏已经在跑。
    private func clauEdIsRunning() -> Bool {
        let me = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication
            .runningApplications(withBundleIdentifier: kClauEdBundleID)
            .contains { $0.processIdentifier != me }
    }

    private func handleTerminate(_ app: NSRunningApplication) {
        if app.bundleIdentifier == kClaudeBundleID {
            log("claude terminated")
            claudeRunning = false
            hideCovers("claude-terminated")
        } else if app.bundleIdentifier == kClauEdBundleID {
            log("clauEd terminated")
            hideCovers("clauEd-terminated")
        }
    }

    // MARK: - 拉起 ClauEd

    private func clauEdAppURL() -> URL {
        var url = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        while url.path != "/" {
            url = url.deletingLastPathComponent()
            if url.pathExtension == "app" && url.lastPathComponent == "ClauEd.app" {
                return url
            }
        }
        return URL(fileURLWithPath: "/Applications/ClauEd.app")
    }

    private func launchClauEd() {
        let url = clauEdAppURL()
        log("opening \(url.path)")
        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: url, configuration: config) { [weak self] _, error in
            if let error = error {
                log("open ClauEd failed: \(error.localizedDescription)")
                self?.hideCovers("launch-failed")
            } else {
                log("ClauEd opened")
            }
        }
    }

    private func parentName(of pid: pid_t) -> String? {
        guard let ppidText = run("/bin/ps", ["-o", "ppid=", "-p", String(pid)]),
              let ppid = Int32(ppidText) else { return nil }
        return run("/bin/ps", ["-o", "comm=", "-p", String(ppid)])
    }

    private func run(_ path: String, _ args: [String]) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        p.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - 黑幕

    private func buildCovers() {
        for screen in NSScreen.screens {
            let w = CoverWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            w.level = .screenSaver
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            w.backgroundColor = .black
            w.isOpaque = true
            w.hasShadow = false
            w.ignoresMouseEvents = true
            w.hidesOnDeactivate = false
            w.animationBehavior = .none
            /* 程序化创建的 NSWindow 默认 isReleasedWhenClosed=true；
               ARC 下 rebuildCovers() 里的 close() 会再释放一次，屏幕参数变化时崩溃 */
            w.isReleasedWhenClosed = false
            w.setFrame(screen.frame, display: false)
            w.orderOut(nil)
            covers.append(w)
        }
        log("covers created: \(covers.count)")
    }

    private func rebuildCovers() {
        let wasShown = coverShown
        hideCovers("screen-change")
        for w in covers { w.close() }
        covers.removeAll()
        buildCovers()
        if wasShown {
            showCovers()
            /* hideCovers 取消了原来的 3 秒兜底；重建后必须重挂，否则开屏失败时
               黑幕会永远留在屏幕上 */
            scheduleTimeout()
        }
    }

    private func showCovers() {
        let screens = NSScreen.screens
        for (index, screen) in screens.enumerated() where index < covers.count {
            covers[index].setFrame(screen.frame, display: false)
            covers[index].orderFrontRegardless()
        }
        coverShown = true
        log("covers shown on \(screens.count) screen(s)")
    }

    private func hideCovers(_ reason: String) {
        guard coverShown else { return }
        coverShown = false
        coverTimeout?.cancel()
        coverTimeout = nil
        for w in covers { w.orderOut(nil) }
        log("covers hidden: \(reason)")
    }

    private func scheduleTimeout() {
        coverTimeout?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.hideCovers("timeout") }
        coverTimeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + kCoverTimeout, execute: work)
    }
}

let app = NSApplication.shared
let watcher = Watcher()
app.delegate = watcher
app.setActivationPolicy(.accessory)
app.run()
