import AppKit
import CoreText
import Foundation

struct StateInfo: Decodable {
    let count: Int
    let bbox: [Int]
}

struct Manifest: Decodable {
    let fps: Int
    let states: [String: StateInfo]
}

struct PetSettings: Codable {
    var pet = "予愿安洁莉娜"
    var scale = 0.55
    var speed = 1.0
    var miniMode = false
    var locked = false
    var positionX: CGFloat?
    var positionY: CGFloat?
    var scaleMigrationVersion: Int?
    var dragMigrationVersion: Int?
}

final class SettingsStore {
    private let url: URL
    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = appSupport.appendingPathComponent("ArkCodexDeskpet", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        url = folder.appendingPathComponent("settings.json")
    }
    func load() -> PetSettings {
        guard let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(PetSettings.self, from: data) else { return PetSettings() }
        return value
    }
    func save(_ settings: PetSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

final class CodexMonitor {
    func status() -> String {
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions")
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey]) else { return "Codex 待机" }
        var latest: URL?
        var latestDate = Date.distantPast
        for case let url as URL in enumerator where url.lastPathComponent.hasPrefix("rollout-") && url.pathExtension == "jsonl" {
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            if date > latestDate { latest = url; latestDate = date }
        }
        guard let file = latest else { return "Codex 待机" }
        let active = Date().timeIntervalSince(latestDate) < 10
        guard active, let text = try? String(contentsOf: file, encoding: .utf8) else { return "Codex 待机" }
        let task = text.split(separator: "\n").reversed().compactMap { line -> String? in
            guard let data = line.data(using: .utf8), let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let payload = value["payload"] as? [String: Any] else { return nil }
            if payload["type"] as? String == "user_message", let message = payload["message"] as? String, !message.contains("environment_context") { return message }
            return nil
        }.first
        guard let task else { return "Codex 运行中" }
        let compact = task.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return "Codex 运行中 · " + String(compact.prefix(36))
    }
}

final class ResizeHandleView: NSView {
    var onBegin: (() -> Void)?
    var onChange: (() -> Void)?
    var onEnd: (() -> Void)?
    private var trackingArea: NSTrackingArea?
    private var hovering = false

    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        NSCursor.resizeLeftRight.set()
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        NSCursor.arrow.set()
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) { onBegin?() }
    override func mouseDragged(with event: NSEvent) { onChange?() }
    override func mouseUp(with event: NSEvent) { onEnd?() }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let color = NSColor.white.withAlphaComponent(hovering ? 0.9 : 0.42)
        color.setStroke()
        let path = NSBezierPath()
        path.lineWidth = hovering ? 2.0 : 1.5
        path.lineCapStyle = .round
        for offset: CGFloat in [7, 12, 17] {
            path.move(to: NSPoint(x: bounds.maxX - offset, y: 4))
            path.line(to: NSPoint(x: bounds.maxX - 4, y: offset))
        }
        path.stroke()
    }
}

final class PetImageView: NSImageView {
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }
}

func petStatusDisplayText(_ status: String) -> String {
    status.contains("运行中") ? "Codex 正在处理" : status
}

func statusContentCenterY(body: NSRect, textHeight: CGFloat, dotDiameter: CGFloat) -> CGFloat {
    body.midY + (textHeight - dotDiameter) / 4
}

final class PetStatusBubble: NSView {
    private let font = NSFont.systemFont(ofSize: 12.5, weight: .medium)
    private var displayText = "Codex 待机"
    private var active = false

    var stringValue: String {
        get { displayText }
        set {
            displayText = petStatusDisplayText(newValue)
            toolTip = newValue == displayText ? nil : newValue
            active = newValue.contains("运行中")
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.16
        layer?.shadowRadius = 7
        layer?.shadowOffset = NSSize(width: 0, height: -2)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: NSSize {
        let width = CTLineGetTypographicBounds(textLine(), nil, nil, nil)
        return NSSize(width: min(360, ceil(width) + 39), height: 40)
    }

    override func layout() {
        super.layout()
        if #available(macOS 14.0, *) {
            layer?.shadowPath = bubblePath().cgPath
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let path = bubblePath()
        NSColor(calibratedWhite: 0.98, alpha: 0.94).setFill()
        path.fill()
        NSColor(calibratedRed: 0.13, green: 0.55, blue: 0.53, alpha: 0.58).setStroke()
        path.lineWidth = 1
        path.stroke()

        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let line = textLine()
        let textBounds = CTLineGetImageBounds(line, context)
        let dotDiameter: CGFloat = 7
        let contentCenterY = statusContentCenterY(
            body: bubbleBody,
            textHeight: textBounds.height,
            dotDiameter: dotDiameter
        )
        let dot = NSBezierPath(ovalIn: NSRect(
            x: 12,
            y: contentCenterY - dotDiameter / 2,
            width: dotDiameter,
            height: dotDiameter
        ))
        (active
            ? NSColor(calibratedRed: 0.12, green: 0.67, blue: 0.49, alpha: 1)
            : NSColor(calibratedRed: 0.24, green: 0.58, blue: 0.65, alpha: 1)
        ).setFill()
        dot.fill()

        context.saveGState()
        context.textPosition = CGPoint(x: 27, y: contentCenterY - textBounds.midY)
        CTLineDraw(line, context)
        context.restoreGState()
    }

    private var bubbleBody: NSRect {
        NSRect(x: 1, y: 8, width: max(0, bounds.width - 2), height: max(0, bounds.height - 9))
    }

    private func textLine() -> CTLine {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(calibratedWhite: 0.12, alpha: 0.92)
        ]
        return CTLineCreateWithAttributedString(NSAttributedString(string: displayText, attributes: attributes))
    }

    private func bubblePath() -> NSBezierPath {
        let minX = bubbleBody.minX
        let maxX = bubbleBody.maxX
        let minY = bubbleBody.minY
        let maxY = bubbleBody.maxY
        let radius = min(10, (maxY - minY) / 2)
        let centerX = bounds.midX
        let path = NSBezierPath()
        path.move(to: NSPoint(x: minX + radius, y: minY))
        path.line(to: NSPoint(x: centerX - 6, y: minY))
        path.line(to: NSPoint(x: centerX, y: 2))
        path.line(to: NSPoint(x: centerX + 6, y: minY))
        path.line(to: NSPoint(x: maxX - radius, y: minY))
        path.appendArc(withCenter: NSPoint(x: maxX - radius, y: minY + radius), radius: radius, startAngle: -90, endAngle: 0)
        path.line(to: NSPoint(x: maxX, y: maxY - radius))
        path.appendArc(withCenter: NSPoint(x: maxX - radius, y: maxY - radius), radius: radius, startAngle: 0, endAngle: 90)
        path.line(to: NSPoint(x: minX + radius, y: maxY))
        path.appendArc(withCenter: NSPoint(x: minX + radius, y: maxY - radius), radius: radius, startAngle: 90, endAngle: 180)
        path.line(to: NSPoint(x: minX, y: minY + radius))
        path.appendArc(withCenter: NSPoint(x: minX + radius, y: minY + radius), radius: radius, startAngle: 180, endAngle: 270)
        path.close()
        return path
    }
}

final class PetContentView: NSView {
    var resizeHandle: NSView?
    var onMouseDown: (() -> Void)?
    var onMouseDragged: (() -> Void)?
    var onMouseUp: (() -> Void)?
    var onRightMouseDown: ((NSEvent) -> Void)?

    override func hitTest(_ point: NSPoint) -> NSView? {
        if let resizeHandle, resizeHandle.frame.contains(point) {
            return resizeHandle.hitTest(convert(point, to: resizeHandle))
        }
        return bounds.contains(point) ? self : nil
    }

    override func mouseDown(with event: NSEvent) { onMouseDown?() }
    override func mouseDragged(with event: NSEvent) { onMouseDragged?() }
    override func mouseUp(with event: NSEvent) { onMouseUp?() }
    override func rightMouseDown(with event: NSEvent) { onRightMouseDown?(event) }
}

func draggedWindowOrigin(from origin: NSPoint, mouseStart: NSPoint, mouseNow: NSPoint) -> NSPoint {
    NSPoint(x: origin.x + mouseNow.x - mouseStart.x, y: origin.y + mouseNow.y - mouseStart.y)
}

final class PetPanel: NSPanel {
    private let store = SettingsStore()
    private let monitor = CodexMonitor()
    var settings: PetSettings
    var manifest: Manifest!
    private var framesURL: URL!
    private var state = "idle"
    private var frameIndex = 0
    private var timer: Timer?
    private var statusTimer: Timer?
    private var imageView = PetImageView()
    private var statusBubble = PetStatusBubble()
    private var dragOrigin: NSPoint?
    private var dragStartMouse: NSPoint?
    private var isDragging = false
    private let resizeHandle = ResizeHandleView()
    private var resizeStartScale = 0.55
    private var resizeStartFrame = NSRect.zero
    private var resizeStartMouse = NSPoint.zero

    init() {
        settings = store.load()
        let needsScaleMigration = settings.scaleMigrationVersion == nil
        if needsScaleMigration {
            settings.scale = min(settings.scale, 0.55)
            settings.scaleMigrationVersion = 1
        }
        let needsDragMigration = settings.dragMigrationVersion == nil
        if needsDragMigration {
            settings.locked = false
            settings.dragMigrationVersion = 1
        }
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        if needsScaleMigration || needsDragMigration { store.save(settings) }
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        setupViews()
        loadPet(named: settings.pet)
        startTimers()
        applyAppearance()
        orderFrontRegardless()
    }

    private func setupViews() {
        let view = PetContentView()
        view.wantsLayer = true
        contentView = view
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        statusBubble.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(imageView)
        view.addSubview(statusBubble)
        resizeHandle.translatesAutoresizingMaskIntoConstraints = false
        resizeHandle.toolTip = "拖动调整桌宠大小"
        resizeHandle.onBegin = { [weak self] in self?.beginResize() }
        resizeHandle.onChange = { [weak self] in self?.continueResize() }
        resizeHandle.onEnd = { [weak self] in self?.endResize() }
        view.addSubview(resizeHandle)
        view.resizeHandle = resizeHandle
        view.onMouseDown = { [weak self] in self?.beginDrag() }
        view.onMouseDragged = { [weak self] in self?.continueDrag() }
        view.onMouseUp = { [weak self] in self?.endDrag() }
        view.onRightMouseDown = { [weak self] event in
            guard let self else { return }
            AppDelegate.shared?.openMenu(for: self, event: event)
        }
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor), imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor), imageView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            statusBubble.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusBubble.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 4),
            statusBubble.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -4),
            statusBubble.topAnchor.constraint(equalTo: view.topAnchor),
            statusBubble.heightAnchor.constraint(equalToConstant: 40),
            imageView.topAnchor.constraint(equalTo: statusBubble.bottomAnchor, constant: 1),
            resizeHandle.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            resizeHandle.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            resizeHandle.widthAnchor.constraint(equalToConstant: 28),
            resizeHandle.heightAnchor.constraint(equalToConstant: 28)
        ])
    }

    private func loadPet(named name: String) {
        guard let petURL = PetLibrary.shared.petURL(named: name) else { fatalError("Pet assets are missing") }
        guard let data = try? Data(contentsOf: petURL.appendingPathComponent("manifest.json")), let loaded = try? JSONDecoder().decode(Manifest.self, from: data) else { fatalError("Invalid manifest for \(name)") }
        manifest = loaded
        framesURL = petURL.appendingPathComponent("frames")
        settings.pet = name
        state = manifest.states["idle"] == nil ? manifest.states.keys.sorted().first! : "idle"
        frameIndex = 0
    }

    private func applyAppearance() {
        let size = contentSize(for: settings.scale)
        setContentSize(size)
        statusBubble.isHidden = settings.miniMode
        if let x = settings.positionX, let y = settings.positionY {
            setFrameOrigin(clampedOrigin(NSPoint(x: x, y: y), size: size))
        } else if let screen = NSScreen.main {
            setFrameOrigin(NSPoint(x: screen.visibleFrame.midX - size.width / 2, y: screen.visibleFrame.minY + 24))
        }
        showFrame()
    }

    private func clampedOrigin(_ origin: NSPoint, size: NSSize) -> NSPoint {
        let center = NSPoint(x: origin.x + size.width / 2, y: origin.y + size.height / 2)
        let screen = NSScreen.screens.first { $0.frame.contains(center) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return origin }
        return NSPoint(
            x: min(max(origin.x, visible.minX), visible.maxX - size.width),
            y: min(max(origin.y, visible.minY), visible.maxY - size.height)
        )
    }

    private func contentSize(for scale: Double) -> NSSize {
        guard let info = manifest.states[state] else { return NSSize(width: 120, height: 120) }
        let width = max(100, CGFloat(info.bbox[2] - info.bbox[0] + 1) * scale)
        let imageHeight = max(100, CGFloat(info.bbox[3] - info.bbox[1] + 1) * scale)
        let statusHeight: CGFloat = settings.miniMode ? 0 : 41
        return NSSize(width: width, height: imageHeight + statusHeight)
    }

    private func beginResize() {
        resizeStartScale = settings.scale
        resizeStartFrame = frame
        resizeStartMouse = NSEvent.mouseLocation
    }

    private func continueResize() {
        let mouse = NSEvent.mouseLocation
        let horizontal = mouse.x - resizeStartMouse.x
        let vertical = resizeStartMouse.y - mouse.y
        let naturalWidth = max(1, resizeStartFrame.width / resizeStartScale)
        let naturalHeight = max(1, resizeStartFrame.height / resizeStartScale)
        let horizontalScale = horizontal / naturalWidth
        let verticalScale = vertical / naturalHeight
        let delta = abs(horizontalScale) >= abs(verticalScale) ? horizontalScale : verticalScale
        let newScale = min(1.5, max(0.2, resizeStartScale + delta))
        let size = contentSize(for: newScale)
        let origin = NSPoint(x: resizeStartFrame.minX, y: resizeStartFrame.maxY - size.height)
        settings.scale = newScale
        setFrame(NSRect(origin: origin, size: size), display: true)
        showFrame()
    }

    private func endResize() {
        settings.positionX = frame.origin.x
        settings.positionY = frame.origin.y
        store.save(settings)
    }

    private func startTimers() {
        timer?.invalidate(); statusTimer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: max(0.02, 1.0 / Double(manifest.fps) / settings.speed), repeats: true) { [weak self] _ in self?.nextFrame() }
        statusTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refreshStatus() }
        refreshStatus()
    }

    private func frameURL() -> URL { framesURL.appendingPathComponent(state).appendingPathComponent(String(format: "frame_%04d.png", frameIndex)) }
    private func showFrame() { imageView.image = NSImage(contentsOf: frameURL()) }
    private func nextFrame() {
        guard let info = manifest.states[state] else { return }
        frameIndex = (frameIndex + 1) % info.count
        showFrame()
    }
    private func refreshStatus() { statusBubble.stringValue = monitor.status() }

    func setState(_ next: String) {
        guard manifest.states[next] != nil else { return }
        state = next; frameIndex = 0; applyAppearance()
    }
    func toggleLocked() { settings.locked.toggle(); store.save(settings) }
    func toggleMini() { settings.miniMode.toggle(); store.save(settings); applyAppearance() }
    func scale(by delta: Double) { settings.scale = min(1.5, max(0.2, settings.scale + delta)); store.save(settings); applyAppearance() }
    func savePosition() { settings.positionX = frame.origin.x; settings.positionY = frame.origin.y; store.save(settings) }
    func availablePets() -> [String] { PetLibrary.shared.names() }
    func selectPet(_ name: String) { savePosition(); loadPet(named: name); store.save(settings); applyAppearance(); startTimers() }

    private func beginDrag() {
        dragOrigin = frame.origin
        dragStartMouse = NSEvent.mouseLocation
        isDragging = false
    }

    private func continueDrag() {
        guard !settings.locked, let origin = dragOrigin, let startMouse = dragStartMouse else { return }
        let point = NSEvent.mouseLocation
        let delta = NSPoint(x: point.x - startMouse.x, y: point.y - startMouse.y)
        setFrameOrigin(draggedWindowOrigin(from: origin, mouseStart: startMouse, mouseNow: point))
        isDragging = abs(delta.x) > 2 || abs(delta.y) > 2
        if manifest.states["move"] != nil && state != "move" {
            state = "move"
            frameIndex = 0
            showFrame()
        }
    }

    private func endDrag() {
        if isDragging {
            savePosition()
            setState("idle")
        } else {
            setState("interact")
        }
        dragOrigin = nil
        dragStartMouse = nil
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var shared: AppDelegate?
    private var pet: PetPanel!
    private var statusItem: NSStatusItem!
    private var activePRTSImporter: PRTSFrameImporter?
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        pet = PetPanel()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Ark Codex Deskpet")
        statusItem.menu = makeMenu()
    }
    func applicationWillTerminate(_ notification: Notification) { pet?.savePosition() }
    func openMenu(for panel: PetPanel, event: NSEvent) { let menu = makeMenu(); NSMenu.popUpContextMenu(menu, with: event, for: panel.contentView!) }
    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        add(menu, "显示桌宠", #selector(showPet))
        add(menu, pet.settings.locked ? "解锁移动" : "锁定位置", #selector(toggleLock))
        add(menu, pet.settings.miniMode ? "显示状态" : "隐藏状态", #selector(toggleMini))
        add(menu, "放大", #selector(larger)); add(menu, "缩小", #selector(smaller))
        let stateNames = ["idle": "待机", "interact": "互动", "move": "移动", "sit": "坐下", "sleep": "睡眠"]
        let states = NSMenu(title: "动画")
        for state in ["idle", "interact", "move", "sit", "sleep"] where pet.manifest.states[state] != nil { let item = NSMenuItem(title: stateNames[state] ?? state, action: #selector(selectState(_:)), keyEquivalent: ""); item.representedObject = state; item.target = self; states.addItem(item) }
        let animationItem = NSMenuItem(title: "动画", action: nil, keyEquivalent: ""); animationItem.submenu = states; menu.addItem(animationItem)
        let pets = NSMenu(title: "桌宠库")
        for name in pet.availablePets() { let item = NSMenuItem(title: name, action: #selector(selectPet(_:)), keyEquivalent: ""); item.representedObject = name; item.target = self; item.state = name == pet.settings.pet ? .on : .off; pets.addItem(item) }
        let library = NSMenuItem(title: "桌宠库", action: nil, keyEquivalent: ""); library.submenu = pets; menu.addItem(library)
        add(menu, "从 PRTS 联网添加…", #selector(addPRTSPet))
        add(menu, "从本地文件夹导入…", #selector(addPet))
        menu.addItem(.separator())
        add(menu, "退出 Ark Codex Deskpet", #selector(quit))
        return menu
    }
    private func add(_ menu: NSMenu, _ title: String, _ selector: Selector) { let item = NSMenuItem(title: title, action: selector, keyEquivalent: ""); item.target = self; menu.addItem(item) }
    @objc private func showPet() { pet.orderFrontRegardless() }
    @objc private func toggleLock() { pet.toggleLocked(); statusItem.menu = makeMenu() }
    @objc private func toggleMini() { pet.toggleMini(); statusItem.menu = makeMenu() }
    @objc private func larger() { pet.scale(by: 0.1) }
    @objc private func smaller() { pet.scale(by: -0.1) }
    @objc private func selectState(_ sender: NSMenuItem) { if let state = sender.representedObject as? String { pet.setState(state) } }
    @objc private func selectPet(_ sender: NSMenuItem) { if let name = sender.representedObject as? String { pet.selectPet(name) } }
    @objc private func addPRTSPet() {
        Task { @MainActor [weak self] in
            await self?.runPRTSImport()
        }
    }

    @MainActor
    private func runPRTSImport() async {
        guard let query = promptForPRTSQuery() else { return }
        let progress = PRTSProgressWindow()
        do {
            progress.show("正在搜索 PRTS 干员…")
            let results = try await PRTSService.shared.search(query)
            progress.close()
            guard let selected = choosePRTSResult(results) else { return }

            progress.show("正在读取“\(selected.title)”的模型信息…")
            async let pageRequest = PRTSService.shared.modelPage(for: selected.title)
            let page = try await pageRequest
            let metadata = try await PRTSService.shared.metadata(for: page.modelID)
            progress.close()
            guard let skin = choosePRTSSkin(metadata.buildSkins) else { return }

            progress.show("正在载入“\(selected.title)”的“\(skin)”基建模型…")
            let importer = PRTSFrameImporter()
            activePRTSImporter = importer
            importer.onProgress = { [weak progress] text in progress?.update(text) }
            let candidate = try await importer.generate(
                operatorName: selected.title,
                modelPage: page,
                metadata: metadata,
                skinName: skin
            )
            activePRTSImporter = nil
            defer { try? FileManager.default.removeItem(at: candidate.url.deletingLastPathComponent()) }

            progress.update("正在写入本地桌宠库…")
            guard installCandidate(candidate) else {
                progress.close()
                return
            }
            pet.selectPet(candidate.name)
            statusItem.menu = makeMenu()
            progress.close()
            showMessage(title: "PRTS 桌宠已添加", text: "已下载、生成并切换到“\(candidate.name)”。")
        } catch {
            activePRTSImporter = nil
            progress.close()
            showMessage(title: "PRTS 导入失败", text: error.localizedDescription)
        }
    }

    private func promptForPRTSQuery() -> String? {
        let field = NSSearchField(frame: NSRect(x: 0, y: 0, width: 360, height: 28))
        field.placeholderString = "输入干员名称，例如：浊心斯卡蒂"
        let alert = NSAlert()
        alert.messageText = "从 PRTS 搜索干员"
        alert.informativeText = "将从 PRTS Wiki 下载所选干员的基建模型，仅用于个人学习与桌宠展示。"
        alert.accessoryView = field
        alert.addButton(withTitle: "搜索")
        alert.addButton(withTitle: "取消")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let query = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            showMessage(title: "请输入干员名称", text: "名称不能为空。")
            return nil
        }
        return query
    }

    private func choosePRTSResult(_ results: [PRTSSearchResult]) -> PRTSSearchResult? {
        let popUp = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 360, height: 28), pullsDown: false)
        popUp.addItems(withTitles: results.map(\.title))
        let alert = NSAlert()
        alert.messageText = "选择 PRTS 干员"
        alert.informativeText = "请选择要生成桌宠的干员页面。"
        alert.accessoryView = popUp
        alert.addButton(withTitle: "下一步")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn,
              popUp.indexOfSelectedItem >= 0,
              popUp.indexOfSelectedItem < results.count else { return nil }
        return results[popUp.indexOfSelectedItem]
    }

    private func choosePRTSSkin(_ skins: [String]) -> String? {
        let popUp = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 360, height: 28), pullsDown: false)
        popUp.addItems(withTitles: skins)
        let alert = NSAlert()
        alert.messageText = "选择时装"
        alert.informativeText = "只显示包含基建模型的时装。"
        alert.accessoryView = popUp
        alert.addButton(withTitle: "下载并添加")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn,
              popUp.indexOfSelectedItem >= 0,
              popUp.indexOfSelectedItem < skins.count else { return nil }
        return skins[popUp.indexOfSelectedItem]
    }

    private func installCandidate(_ candidate: PetPackageCandidate) -> Bool {
        do {
            try PetLibrary.shared.install(candidate)
            return true
        } catch PetImportError.alreadyExists {
            let confirmation = NSAlert()
            confirmation.messageText = "替换已有桌宠？"
            confirmation.informativeText = "“\(candidate.name)”已经存在。替换会更新本地素材。"
            confirmation.addButton(withTitle: "替换")
            confirmation.addButton(withTitle: "取消")
            guard confirmation.runModal() == .alertFirstButtonReturn else { return false }
            do {
                try PetLibrary.shared.install(candidate, replacing: true)
                return true
            } catch {
                showMessage(title: "导入失败", text: error.localizedDescription)
                return false
            }
        } catch {
            showMessage(title: "导入失败", text: error.localizedDescription)
            return false
        }
    }

    @objc private func addPet() {
        let panel = NSOpenPanel()
        panel.title = "选择桌宠包来源"
        panel.message = "选择一个桌宠包，或包含多个桌宠包的文件夹。"
        panel.prompt = "扫描"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }

        let candidates = PetLibrary.shared.candidates(in: panel.urls)
        guard !candidates.isEmpty else {
            showMessage(title: "没有找到兼容桌宠", text: "所选文件夹中没有有效的 manifest.json 和完整动画帧。")
            return
        }
        let picker = PetSearchController(candidates: candidates)
        guard let candidate = picker.runModal() else { return }
        guard installCandidate(candidate) else { return }
        pet.selectPet(candidate.name)
        statusItem.menu = makeMenu()
        showMessage(title: "桌宠已添加", text: "已导入并切换到“\(candidate.name)”。")
    }

    private func showMessage(title: String, text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
    @objc private func quit() { NSApp.terminate(nil) }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
