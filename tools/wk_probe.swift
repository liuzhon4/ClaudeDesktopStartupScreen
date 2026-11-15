// 离屏 WKWebView 探针：验证壳页面在真实 WebKit 里能跑起来（不显示任何窗口）。
// 用法：swift tools/wk_probe.swift "fork/splash.html"
import Cocoa
import WebKit

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)

guard CommandLine.arguments.count > 1 else {
    print("usage: swift tools/wk_probe.swift <splash.html>")
    exit(2)
}
let url = URL(fileURLWithPath: CommandLine.arguments[1])

let cfg = WKWebViewConfiguration()
cfg.userContentController.addUserScript(
    WKUserScript(
        source: "window.__DSH_STARTUP__ = {theme:'dark', speed:3, voice:false, sound:false};",
        injectionTime: .atDocumentStart,
        forMainFrameOnly: true
    )
)

let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 1200, height: 800), configuration: cfg)
let win = NSWindow(contentRect: web.frame, styleMask: .borderless, backing: .buffered, defer: false)
win.contentView = web
// 不 orderFront —— 纯离屏验证，不打扰屏幕

web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())

var ticks = 0
var audioChecked = false

Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
    ticks += 1
    web.evaluateJavaScript("""
    (function(){
      var r = document.getElementById('dsh-startup-root');
      return JSON.stringify({
        running: window.__DSH_STARTUP_RUNNING__ === true,
        root: !!r,
        cls: r ? r.className : null,
        marks: r ? r.querySelectorAll('.dsu-mark path').length : -1,
        plate: !!document.querySelector('.dsu-plate'),
        audioTable: typeof window.__CLAUDE_SPLASH_AUDIO__,
        audioKeys: window.__CLAUDE_SPLASH_AUDIO__ ? Object.keys(window.__CLAUDE_SPLASH_AUDIO__).length : 0
      });
    })()
    """) { result, error in
        print("tick \(ticks):", result ?? error ?? "nil")

        if !audioChecked, let s = result as? String, s.contains("\"running\":true") {
            audioChecked = true
            web.callAsyncJavaScript("""
            const t = window.__CLAUDE_SPLASH_AUDIO__;
            if (!t || !t['line-1']) return 'no-line-1 (asset-free build)';
            const ctx = new (window.AudioContext || window.webkitAudioContext)();
            const bin = atob(t['line-1']);
            const u = new Uint8Array(bin.length);
            for (let i = 0; i < bin.length; i++) u[i] = bin.charCodeAt(i);
            const buf = await ctx.decodeAudioData(u.buffer.slice(0));
            return 'decoded line-1 ' + buf.duration.toFixed(2) + 's, ctx=' + ctx.state;
            """, arguments: [:], in: nil, in: .page) { result in
                switch result {
                case .success(let value): print("audio:", value)
                case .failure(let error): print("audio error:", error)
                }
            }
        }

        if ticks >= 6 {
            timer.invalidate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { app.terminate(nil) }
        }
    }
}

app.run()
