import AppKit
import Foundation

struct PetPackageCandidate {
    let name: String
    let url: URL
}

enum PetImportError: LocalizedError {
    case invalidPackage
    case alreadyExists(String)

    var errorDescription: String? {
        switch self {
        case .invalidPackage:
            return "所选文件夹不是有效的桌宠包，或动画帧不完整。"
        case .alreadyExists(let name):
            return "桌宠“\(name)”已经存在。"
        }
    }
}

final class PetLibrary {
    static let shared = PetLibrary()

    let userDirectory: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        userDirectory = appSupport
            .appendingPathComponent("ArkCodexDeskpet", isDirectory: true)
            .appendingPathComponent("pets", isDirectory: true)
        try? FileManager.default.createDirectory(at: userDirectory, withIntermediateDirectories: true)
    }

    private func bundledDirectory() -> URL? {
        if let resourceURL = Bundle.main.resourceURL {
            let packaged = resourceURL.appendingPathComponent("pets", isDirectory: true)
            if FileManager.default.fileExists(atPath: packaged.path) {
                return packaged
            }
        }
        if let swiftPackage = Bundle.module.url(forResource: "pets", withExtension: nil) {
            return swiftPackage
        }
        let source = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/ArkCodexDeskpet/pets", isDirectory: true)
        return FileManager.default.fileExists(atPath: source.path) ? source : nil
    }

    func petURL(named name: String) -> URL? {
        let imported = userDirectory.appendingPathComponent(name, isDirectory: true)
        if isValidPackage(imported) {
            return imported
        }
        guard let bundledDirectory = bundledDirectory() else { return nil }
        let bundled = bundledDirectory.appendingPathComponent(name, isDirectory: true)
        return isValidPackage(bundled) ? bundled : nil
    }

    func names() -> [String] {
        var names = Set<String>()
        for root in [bundledDirectory(), userDirectory].compactMap({ $0 }) {
            guard let entries = try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for entry in entries where isValidPackage(entry) {
                names.insert(entry.lastPathComponent)
            }
        }
        return names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    func candidates(in roots: [URL]) -> [PetPackageCandidate] {
        var candidates: [PetPackageCandidate] = []
        var seen = Set<String>()
        for root in roots {
            if isValidPackage(root) {
                let key = root.standardizedFileURL.path
                if seen.insert(key).inserted {
                    candidates.append(PetPackageCandidate(name: root.lastPathComponent, url: root))
                }
                continue
            }
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            for case let url as URL in enumerator {
                let depth = url.pathComponents.count - root.pathComponents.count
                if depth > 4 {
                    enumerator.skipDescendants()
                    continue
                }
                guard url.lastPathComponent == "manifest.json" else { continue }
                let packageURL = url.deletingLastPathComponent()
                guard isValidPackage(packageURL) else { continue }
                let key = packageURL.standardizedFileURL.path
                if seen.insert(key).inserted {
                    candidates.append(PetPackageCandidate(name: packageURL.lastPathComponent, url: packageURL))
                }
                enumerator.skipDescendants()
            }
        }
        return candidates.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func install(_ candidate: PetPackageCandidate, replacing: Bool = false) throws {
        guard isValidPackage(candidate.url) else { throw PetImportError.invalidPackage }
        let destination = userDirectory.appendingPathComponent(candidate.name, isDirectory: true)
        if FileManager.default.fileExists(atPath: destination.path), !replacing {
            throw PetImportError.alreadyExists(candidate.name)
        }

        let temporary = userDirectory.appendingPathComponent(".import-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.copyItem(at: candidate.url, to: temporary)
        do {
            guard isValidPackage(temporary) else { throw PetImportError.invalidPackage }
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: temporary, to: destination)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }

    private func isValidPackage(_ url: URL) -> Bool {
        let manifestURL = url.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data),
              manifest.fps > 0,
              !manifest.states.isEmpty else { return false }

        let frames = url.appendingPathComponent("frames", isDirectory: true)
        for (state, info) in manifest.states {
            guard info.count > 0, info.bbox.count == 4 else { return false }
            let stateDirectory = frames.appendingPathComponent(state, isDirectory: true)
            let first = stateDirectory.appendingPathComponent("frame_0000.png")
            let last = stateDirectory.appendingPathComponent(String(format: "frame_%04d.png", info.count - 1))
            guard FileManager.default.fileExists(atPath: first.path),
                  FileManager.default.fileExists(atPath: last.path) else { return false }
        }
        return true
    }
}

final class PetSearchController: NSObject, NSSearchFieldDelegate {
    private let candidates: [PetPackageCandidate]
    private var filtered: [PetPackageCandidate]
    private let searchField = NSSearchField(frame: .zero)
    private let popUp = NSPopUpButton(frame: .zero, pullsDown: false)

    init(candidates: [PetPackageCandidate]) {
        self.candidates = candidates
        filtered = candidates
        super.init()
    }

    func runModal() -> PetPackageCandidate? {
        let alert = NSAlert()
        alert.messageText = "选择要添加的桌宠"
        alert.informativeText = "输入名称搜索已发现的兼容桌宠包。"
        alert.addButton(withTitle: "添加")
        alert.addButton(withTitle: "取消")

        searchField.placeholderString = "搜索桌宠名称"
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false
        popUp.translatesAutoresizingMaskIntoConstraints = false
        let stack = NSStackView(views: [searchField, popUp])
        stack.orientation = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 380, height: 70))
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor),
            searchField.heightAnchor.constraint(equalToConstant: 26),
            popUp.heightAnchor.constraint(equalToConstant: 26)
        ])
        alert.accessoryView = container
        updateResults(query: "")
        alert.window.initialFirstResponder = searchField

        guard alert.runModal() == .alertFirstButtonReturn,
              popUp.indexOfSelectedItem >= 0,
              popUp.indexOfSelectedItem < filtered.count else { return nil }
        return filtered[popUp.indexOfSelectedItem]
    }

    func controlTextDidChange(_ notification: Notification) {
        updateResults(query: searchField.stringValue)
    }

    private func updateResults(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        filtered = trimmed.isEmpty
            ? candidates
            : candidates.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
        popUp.removeAllItems()
        for candidate in filtered {
            popUp.addItem(withTitle: "\(candidate.name) — \(candidate.url.deletingLastPathComponent().lastPathComponent)")
        }
        if filtered.isEmpty {
            popUp.addItem(withTitle: "没有匹配的桌宠")
            popUp.isEnabled = false
        } else {
            popUp.isEnabled = true
            popUp.selectItem(at: 0)
        }
    }
}
