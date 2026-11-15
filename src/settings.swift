import Cocoa

final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var textFields: [String: NSTextField] = [:]
    private var checkboxes: [String: NSButton] = [:]
    private var popups: [String: NSPopUpButton] = [:]
    private let popupValues: [String: [String]] = [
        "displayMode": ["always", "daily"],
        "themeOverride": ["auto", "light", "dark"],
        "darkWash": ["soft", "faithful"]
    ]

    func show() {
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 680),
                           styleMask: [.titled, .closable, .miniaturizable, .resizable],
                           backing: .buffered, defer: false)
        win.title = "ClauEd 设置"
        win.minSize = NSSize(width: 540, height: 480)
        win.isReleasedWhenClosed = false
        win.isRestorable = false
        win.delegate = self
        win.center()

        let content = NSView()
        win.contentView = content
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let grid = NSGridView()
        grid.columnSpacing = 12
        grid.rowSpacing = 10
        grid.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = grid

        var values = defaultConfigObject()
        for (key, value) in readConfigObject() { values[key] = value }

        addSection("基本", to: grid)
        addCheckbox("enabled", "启用开屏", to: grid, values: values)
        addPopup("displayMode", "播放频率", ["总是播放", "每天一次"], to: grid, values: values)
        addPopup("themeOverride", "主题", ["自动", "亮色", "暗色"], to: grid, values: values)
        addPopup("darkWash", "暗色过场", ["暗房亮起", "原版过曝"], to: grid, values: values)
        addTextField("speed", "播放速度", to: grid, values: values)
        addCheckbox("requireInteraction", "前两步等待确认", to: grid, values: values)
        addCheckbox("voice", "人声播报", to: grid, values: values)
        addCheckbox("sound", "界面音效", to: grid, values: values)
        addCheckbox("splashOnActivate", "Claude 已运行时也播放", to: grid, values: values)

        addSection("身份卡与终幕", to: grid)
        addTextField("identity", "用户名称", to: grid, values: values)
        addTextField("identityId", "会话编号", to: grid, values: values)
        addTextField("accessLevel", "访问等级", to: grid, values: values)
        addTextField("welcomeTemplate", "终幕欢迎文案", to: grid, values: values)
        addTextField("voiceGreeting", "终幕英文语音", to: grid, values: values)
        addTextField("labelIdentity", "用户名称标签", to: grid, values: values)
        addTextField("labelIdentityId", "会话编号标签", to: grid, values: values)
        addTextField("labelAccessLevel", "访问等级标签", to: grid, values: values)

        let help = NSTextField(wrappingLabelWithString: "用户名称、会话编号、访问等级留空可隐藏对应内容。会话编号填 auto/date 使用当天日期；访问等级填 auto 读取最近 Code 会话的模型名，填固定文本则完全不读取会话元数据。{identity} 会在欢迎文案和语音中替换为用户名称；终幕语音使用系统 TTS。")
        help.font = .systemFont(ofSize: 11)
        help.textColor = .secondaryLabelColor
        grid.addRow(with: [NSView(), help])
        grid.bottomAnchor.constraint(equalTo: help.bottomAnchor, constant: 12).isActive = true

        let save = NSButton(title: "保存", target: self, action: #selector(saveConfig))
        save.keyEquivalent = "\r"
        let cancel = NSButton(title: "取消", target: self, action: #selector(close))
        cancel.keyEquivalent = "\u{1b}"
        let restore = NSButton(title: "恢复默认", target: self, action: #selector(restoreDefaults))
        let buttons = NSStackView(views: [restore, NSView(), cancel, save])
        buttons.orientation = .horizontal
        buttons.spacing = 12
        buttons.distribution = .gravityAreas
        buttons.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(scroll)
        content.addSubview(buttons)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 22),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -22),
            scroll.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            scroll.bottomAnchor.constraint(equalTo: buttons.topAnchor, constant: -18),
            buttons.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 22),
            buttons.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -22),
            buttons.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -18),
            grid.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            grid.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            grid.topAnchor.constraint(equalTo: scroll.contentView.topAnchor)
        ])

        window = win
        win.makeKeyAndOrderFront(nil)
        win.orderFrontRegardless()
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func addSection(_ title: String, to grid: NSGridView) {
        let label = NSTextField(labelWithString: title)
        label.font = .boldSystemFont(ofSize: 13)
        label.textColor = .secondaryLabelColor
        grid.addRow(with: [label, NSView()])
    }

    private func rowLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.alignment = .right
        label.widthAnchor.constraint(equalToConstant: 145).isActive = true
        return label
    }

    private func addTextField(_ key: String, _ title: String, to grid: NSGridView,
                              values: [String: Any]) {
        let field = NSTextField(string: stringValue(values[key]))
        field.widthAnchor.constraint(equalToConstant: 350).isActive = true
        textFields[key] = field
        grid.addRow(with: [rowLabel(title), field])
    }

    private func addCheckbox(_ key: String, _ title: String, to grid: NSGridView,
                             values: [String: Any]) {
        let box = NSButton(checkboxWithTitle: "", target: nil, action: nil)
        box.state = values[key] as? Bool == true ? .on : .off
        checkboxes[key] = box
        grid.addRow(with: [rowLabel(title), box])
    }

    private func addPopup(_ key: String, _ title: String, _ titles: [String],
                          to grid: NSGridView, values: [String: Any]) {
        let popup = NSPopUpButton()
        popup.addItems(withTitles: titles)
        let current = stringValue(values[key])
        if let index = popupValues[key]?.firstIndex(of: current) { popup.selectItem(at: index) }
        popups[key] = popup
        grid.addRow(with: [rowLabel(title), popup])
    }

    private func stringValue(_ value: Any?) -> String {
        if let number = value as? NSNumber { return number.stringValue }
        return value as? String ?? ""
    }

    private func apply(_ values: [String: Any]) {
        for (key, field) in textFields { field.stringValue = stringValue(values[key]) }
        for (key, box) in checkboxes { box.state = values[key] as? Bool == true ? .on : .off }
        for (key, popup) in popups {
            let current = stringValue(values[key])
            if let index = popupValues[key]?.firstIndex(of: current) { popup.selectItem(at: index) }
        }
    }

    @objc private func restoreDefaults() {
        apply(defaultConfigObject())
    }

    @objc private func close() {
        window?.close()
    }

    @objc private func saveConfig() {
        guard let speedText = textFields["speed"]?.stringValue
            .trimmingCharacters(in: .whitespacesAndNewlines),
              let speed = Double(speedText), (0.35...3.0).contains(speed)
        else {
            let alert = NSAlert()
            alert.messageText = "播放速度无效"
            alert.informativeText = "请输入 0.35 到 3.0 之间的数字。"
            alert.runModal()
            return
        }

        var output = readConfigObject()
        for (key, field) in textFields where key != "speed" {
            output[key] = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        output["speed"] = (speed * 100).rounded() / 100
        for (key, box) in checkboxes { output[key] = box.state == .on }
        for (key, popup) in popups {
            if let values = popupValues[key] { output[key] = values[popup.indexOfSelectedItem] }
        }

        do {
            var data = try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
            data.append(0x0a)
            try data.write(to: supportDir().appendingPathComponent("config.json"), options: .atomic)
            window?.close()
        } catch {
            let alert = NSAlert()
            alert.messageText = "保存失败"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.terminate(nil)
    }
}
