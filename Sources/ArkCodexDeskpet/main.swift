import AppKit
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
    var scale = 1.0
    var speed = 1.0
    var miniMode = false
    var locked = true
    var positionX: CGFloat?
    var positionY: CGFloat?
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

final class PetPanel: NSPanel {
    private let store = SettingsStore()
    private let monitor = CodexMonitor()
    var settings: PetSettings
    var manifest: Manifest!
    private var framesURL: URL!
    private var state = "idle"
    private var frame = 0
    private var timer: Timer?
    private var statusTimer: Timer?
    private var imageView = NSImageView()
    private var statusLabel = NSTextField(labelWithString: "Codex 待机")
    private var dragOrigin: NSPoint?
    private var mouseOrigin: NSPoint?
    private var isDragging = false

    init() {
        settings = store.load()
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
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
        let view = NSView()
        view.wantsLayer = true
        contentView = view
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.textColor = .white
        statusLabel.font = .systemFont(ofSize: 13, weight: .medium)
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.wantsLayer = true
        statusLabel.layer?.backgroundColor = NSColor(calibratedWhite: 0.10, alpha: 0.78).cgColor
        statusLabel.layer?.cornerRadius = 7
        statusLabel.cell?.wraps = false
        view.addSubview(imageView)
        view.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor), imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor), imageView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4), statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4), statusLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 3), statusLabel.heightAnchor.constraint(equalToConstant: 28),
            imageView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 2)
        ])
    }

    private func petsDirectory() -> URL? {
        let source = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Sources/ArkCodexDeskpet/pets")
        if FileManager.default.fileExists(atPath: source.path) { return source }
        return Bundle.module.url(forResource: "pets", withExtension: nil)
    }

    private func loadPet(named name: String) {
        guard let root = petsDirectory() else { fatalError("Pet assets are missing") }
        let petURL = root.appendingPathComponent(name)
        guard let data = try? Data(contentsOf: petURL.appendingPathComponent("manifest.json")), let loaded = try? JSONDecoder().decode(Manifest.self, from: data) else { fatalError("Invalid manifest for \(name)") }
        manifest = loaded
        framesURL = petURL.appendingPathComponent("frames")
        settings.pet = name
        state = manifest.states["idle"] == nil ? manifest.states.keys.sorted().first! : "idle"
        frame = 0
    }

    private func applyAppearance() {
        guard let info = manifest.states[state] else { return }
        let width = max(120, CGFloat(info.bbox[2] - info.bbox[0] + 1) * settings.scale)
        let imageHeight = max(120, CGFloat(info.bbox[3] - info.bbox[1] + 1) * settings.scale)
        let statusHeight: CGFloat = settings.miniMode ? 0 : 33
        setContentSize(NSSize(width: width, height: imageHeight + statusHeight))
        statusLabel.isHidden = settings.miniMode
        if let x = settings.positionX, let y = settings.positionY { setFrameOrigin(NSPoint(x: x, y: y))
        } else if let screen = NSScreen.main { setFrameOrigin(NSPoint(x: screen.visibleFrame.midX - width / 2, y: screen.visibleFrame.minY + 24)) }
        showFrame()
    }

    private func startTimers() {
        timer?.invalidate(); statusTimer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: max(0.02, 1.0 / Double(manifest.fps) / settings.speed), repeats: true) { [weak self] _ in self?.nextFrame() }
        statusTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refreshStatus() }
        refreshStatus()
    }

    private func frameURL() -> URL { framesURL.appendingPathComponent(state).appendingPathComponent(String(format: "frame_%04d.png", frame)) }
    private func showFrame() { imageView.image = NSImage(contentsOf: frameURL()) }
    private func nextFrame() {
        guard let info = manifest.states[state] else { return }
        frame = (frame + 1) % info.count
        showFrame()
    }
    private func refreshStatus() { statusLabel.stringValue = monitor.status() }

    func setState(_ next: String) {
        guard manifest.states[next] != nil else { return }
        state = next; frame = 0; applyAppearance()
    }
    func toggleLocked() { settings.locked.toggle(); store.save(settings) }
    func toggleMini() { settings.miniMode.toggle(); store.save(settings); applyAppearance() }
    func scale(by delta: Double) { settings.scale = min(2.0, max(0.3, settings.scale + delta)); store.save(settings); applyAppearance() }
    func savePosition() { settings.positionX = frame.origin.x; settings.positionY = frame.origin.y; store.save(settings) }
    func availablePets() -> [String] { (try? FileManager.default.contentsOfDirectory(atPath: petsDirectory()!.path))?.filter { FileManager.default.fileExists(atPath: petsDirectory()!.appendingPathComponent($0).appendingPathComponent("manifest.json").path) }.sorted() ?? [] }
    func selectPet(_ name: String) { savePosition(); loadPet(named: name); store.save(settings); applyAppearance(); startTimers() }

    override func mouseDown(with event: NSEvent) { mouseOrigin = event.locationInWindow; dragOrigin = frame.origin; isDragging = false }
    override func mouseDragged(with event: NSEvent) {
        guard !settings.locked, let origin = dragOrigin, let mouse = mouseOrigin else { return }
        let point = NSEvent.mouseLocation
        let delta = NSPoint(x: point.x - (frame.origin.x + mouse.x), y: point.y - (frame.origin.y + mouse.y))
        setFrameOrigin(NSPoint(x: origin.x + delta.x, y: origin.y + delta.y)); isDragging = true
        if manifest.states["move"] != nil && state != "move" {
            state = "move"
            frame = 0
            showFrame()
        }
    }
    override func mouseUp(with event: NSEvent) { if isDragging { setState("idle"); savePosition() } else { setState("interact") } }
    override func rightMouseDown(with event: NSEvent) { AppDelegate.shared?.openMenu(for: self, event: event) }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var shared: AppDelegate?
    private var pet: PetPanel!
    private var statusItem: NSStatusItem!
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
        add(menu, "Show Pet", #selector(showPet))
        add(menu, pet.settings.locked ? "Unlock Drag" : "Lock Drag", #selector(toggleLock))
        add(menu, pet.settings.miniMode ? "Show Status" : "Hide Status", #selector(toggleMini))
        add(menu, "Larger", #selector(larger)); add(menu, "Smaller", #selector(smaller))
        let states = NSMenu(title: "Animation")
        for state in ["idle", "interact", "move", "sit", "sleep"] where pet.manifest.states[state] != nil { let item = NSMenuItem(title: state.capitalized, action: #selector(selectState(_:)), keyEquivalent: ""); item.representedObject = state; item.target = self; states.addItem(item) }
        let animationItem = NSMenuItem(title: "Animation", action: nil, keyEquivalent: ""); animationItem.submenu = states; menu.addItem(animationItem)
        let pets = NSMenu(title: "Pet Library")
        for name in pet.availablePets() { let item = NSMenuItem(title: name, action: #selector(selectPet(_:)), keyEquivalent: ""); item.representedObject = name; item.target = self; item.state = name == pet.settings.pet ? .on : .off; pets.addItem(item) }
        let library = NSMenuItem(title: "Pet Library", action: nil, keyEquivalent: ""); library.submenu = pets; menu.addItem(library)
        menu.addItem(.separator())
        add(menu, "Quit Ark Codex Deskpet", #selector(quit))
        return menu
    }
    private func add(_ menu: NSMenu, _ title: String, _ selector: Selector) { let item = NSMenuItem(title: title, action: selector, keyEquivalent: ""); item.target = self; menu.addItem(item) }
    @objc private func showPet() { pet.orderFrontRegardless() }
    @objc private func toggleLock() { pet.toggleLocked() }
    @objc private func toggleMini() { pet.toggleMini() }
    @objc private func larger() { pet.scale(by: 0.1) }
    @objc private func smaller() { pet.scale(by: -0.1) }
    @objc private func selectState(_ sender: NSMenuItem) { if let state = sender.representedObject as? String { pet.setState(state) } }
    @objc private func selectPet(_ sender: NSMenuItem) { if let name = sender.representedObject as? String { pet.selectPet(name) } }
    @objc private func quit() { NSApp.terminate(nil) }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
