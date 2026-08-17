import AppKit
import Foundation
import WebKit

struct PRTSSearchResult {
    let title: String
    let pageID: Int
}

struct PRTSModelPage {
    let modelID: String
    let viewerScriptURL: URL
}

struct PRTSModel: Decodable {
    let file: String
    let skin: String?
}

struct PRTSMetadata: Decodable {
    let prefix: String
    let name: String
    let skin: [String: [String: PRTSModel]]

    var buildSkins: [String] {
        skin.compactMap { name, models in models["基建"] == nil ? nil : name }
            .sorted { lhs, rhs in
                if lhs == "默认" { return true }
                if rhs == "默认" { return false }
                return lhs.localizedStandardCompare(rhs) == .orderedAscending
            }
    }
}

enum PRTSImportError: LocalizedError {
    case badResponse
    case noSearchResults
    case modelNotFound
    case buildModelNotFound
    case viewerFailed(String)
    case incompleteFrames

    var errorDescription: String? {
        switch self {
        case .badResponse:
            return "PRTS 返回了无法识别的数据，请稍后重试。"
        case .noSearchResults:
            return "没有找到匹配的 PRTS 干员页面。"
        case .modelNotFound:
            return "所选页面没有可用的干员模型。"
        case .buildModelNotFound:
            return "所选皮肤没有基建模型。"
        case .viewerFailed(let message):
            return "PRTS 模型处理失败：\(message)"
        case .incompleteFrames:
            return "生成的动画帧不完整，未写入桌宠库。"
        }
    }
}

final class PRTSService {
    static let shared = PRTSService()

    private let decoder = JSONDecoder()

    private init() {}

    func search(_ query: String) async throws -> [PRTSSearchResult] {
        var components = URLComponents(string: "https://prts.wiki/api.php")!
        components.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "list", value: "search"),
            URLQueryItem(name: "srsearch", value: query),
            URLQueryItem(name: "srnamespace", value: "0"),
            URLQueryItem(name: "srlimit", value: "20"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "formatversion", value: "2")
        ]
        let data = try await request(components.url!)
        let response = try decoder.decode(SearchEnvelope.self, from: data)
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let results = response.query.search
            .filter { !$0.title.contains("/") }
            .map { PRTSSearchResult(title: $0.title, pageID: $0.pageid) }
            .sorted { lhs, rhs in
                if lhs.title == trimmed { return true }
                if rhs.title == trimmed { return false }
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
        guard !results.isEmpty else { throw PRTSImportError.noSearchResults }
        return results
    }

    func modelPage(for title: String) async throws -> PRTSModelPage {
        var components = URLComponents(string: "https://prts.wiki/api.php")!
        components.queryItems = [
            URLQueryItem(name: "action", value: "parse"),
            URLQueryItem(name: "page", value: title),
            URLQueryItem(name: "prop", value: "text"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "formatversion", value: "2")
        ]
        let data = try await request(components.url!)
        let response = try decoder.decode(ParseEnvelope.self, from: data)
        let html = response.parse.text
        let modelPatterns = [
            #"id="spine-root"[^>]*data-id="([^"]+)""#,
            #"data-id="([^"]+)"[^>]*id="spine-root""#
        ]
        guard let modelID = modelPatterns.compactMap({ capture($0, in: html) }).first,
              let script = capture(#"src="(https://static\.prts\.wiki/widgets/production/SpineViewer\.[^"]+\.js)""#, in: html),
              let scriptURL = URL(string: script) else {
            throw PRTSImportError.modelNotFound
        }
        return PRTSModelPage(modelID: modelID, viewerScriptURL: scriptURL)
    }

    func metadata(for modelID: String) async throws -> PRTSMetadata {
        let url = URL(string: "https://torappu.prts.wiki/assets/char_spine/")!
            .appendingPathComponent(modelID, isDirectory: true)
            .appendingPathComponent("meta.json")
        let data = try await request(url)
        let metadata = try decoder.decode(PRTSMetadata.self, from: data)
        guard !metadata.buildSkins.isEmpty else { throw PRTSImportError.buildModelNotFound }
        return metadata
    }

    private func request(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 45)
        request.setValue("ArkCodexDeskpet-macOS/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw PRTSImportError.badResponse
        }
        return data
    }

    private func capture(_ pattern: String, in text: String) -> String? {
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }
}

private struct SearchEnvelope: Decodable {
    let query: SearchQuery
}

private struct SearchQuery: Decodable {
    let search: [SearchItem]
}

private struct SearchItem: Decodable {
    let title: String
    let pageid: Int
}

private struct ParseEnvelope: Decodable {
    let parse: ParsePayload
}

private struct ParsePayload: Decodable {
    let text: String
}

@MainActor
final class PRTSProgressWindow {
    private let panel: NSPanel
    private let label = NSTextField(labelWithString: "正在连接 PRTS…")
    private let indicator = NSProgressIndicator()

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 120),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        panel.title = "添加 PRTS 桌宠"
        panel.isReleasedWhenClosed = false

        let content = NSView()
        panel.contentView = content
        label.translatesAutoresizingMaskIntoConstraints = false
        label.lineBreakMode = .byTruncatingTail
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.style = .bar
        indicator.isIndeterminate = true
        indicator.startAnimation(nil)
        content.addSubview(label)
        content.addSubview(indicator)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            label.topAnchor.constraint(equalTo: content.topAnchor, constant: 22),
            indicator.leadingAnchor.constraint(equalTo: label.leadingAnchor),
            indicator.trailingAnchor.constraint(equalTo: label.trailingAnchor),
            indicator.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 18)
        ])
    }

    func show(_ text: String) {
        update(text)
        panel.center()
        panel.orderFrontRegardless()
    }

    func update(_ text: String) { label.stringValue = text }
    func close() { panel.orderOut(nil) }
}

@MainActor
final class PRTSFrameImporter: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    var onProgress: ((String) -> Void)?

    private var webView: WKWebView?
    private var renderWindow: NSWindow?
    private var continuation: CheckedContinuation<PetPackageCandidate, Error>?
    private var timeoutWorkItem: DispatchWorkItem?
    private var workDirectory: URL?
    private var petDirectory: URL?
    private var petName = ""
    private var stateMetadata: [String: [String: Any]] = [:]
    private var frameCounts: [String: Int] = [:]
    private var finished = false

    func generate(
        operatorName: String,
        modelPage: PRTSModelPage,
        metadata: PRTSMetadata,
        skinName: String
    ) async throws -> PetPackageCandidate {
        guard let model = metadata.skin[skinName]?["基建"] else {
            throw PRTSImportError.buildModelNotFound
        }
        let rawName = skinName == "默认" ? operatorName : "\(operatorName) · \(skinName)"
        petName = rawName.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("ark-prts-\(UUID().uuidString)", isDirectory: true)
        let pet = work.appendingPathComponent(petName, isDirectory: true)
        try FileManager.default.createDirectory(at: pet.appendingPathComponent("frames", isDirectory: true), withIntermediateDirectories: true)
        workDirectory = work
        petDirectory = pet

        let fileURL = metadata.prefix + model.file
        let config: [String: Any] = [
            "modelID": modelPage.modelID,
            "fileURL": fileURL,
            "skin": model.skin.map { $0 as Any } ?? NSNull()
        ]
        let configData = try JSONSerialization.data(withJSONObject: config)
        let configJSON = String(decoding: configData, as: UTF8.self)

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            startWebView(configJSON: configJSON, viewerScriptURL: modelPage.viewerScriptURL)
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard !finished,
              let body = message.body as? [String: Any],
              let type = body["type"] as? String else { return }
        do {
            switch type {
            case "ready":
                onProgress?("模型已载入，正在生成透明动画帧…")
            case "frame":
                try receiveFrame(body)
            case "state":
                try receiveState(body)
            case "complete":
                try finishPackage()
            case "error":
                let detail = body["message"] as? String ?? "未知错误"
                finish(.failure(PRTSImportError.viewerFailed(detail)))
            default:
                break
            }
        } catch {
            finish(.failure(error))
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(.failure(error))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(.failure(error))
    }

    private func startWebView(configJSON: String, viewerScriptURL: URL) {
        let controller = WKUserContentController()
        controller.add(self, name: "prts")
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        let webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 1000, height: 1000),
            configuration: configuration
        )
        webView.navigationDelegate = self
        self.webView = webView

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 1000),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = webView
        window.alphaValue = 0.01
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.orderFront(nil)
        renderWindow = window

        let html = captureHTML(configJSON: configJSON, viewerScriptURL: viewerScriptURL.absoluteString)
        webView.loadHTMLString(html, baseURL: URL(string: "https://prts.wiki/"))

        let timeout = DispatchWorkItem { [weak self] in
            self?.finish(.failure(PRTSImportError.viewerFailed("处理超时，请检查网络后重试。")))
        }
        timeoutWorkItem = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 180, execute: timeout)
    }

    private func receiveFrame(_ body: [String: Any]) throws {
        guard let petDirectory,
              let state = body["state"] as? String,
              let index = body["index"] as? Int,
              let total = body["total"] as? Int,
              let dataURL = body["data"] as? String,
              let comma = dataURL.firstIndex(of: ","),
              let data = Data(base64Encoded: String(dataURL[dataURL.index(after: comma)...])) else {
            throw PRTSImportError.incompleteFrames
        }
        let stateDirectory = petDirectory
            .appendingPathComponent("frames", isDirectory: true)
            .appendingPathComponent(state, isDirectory: true)
        try FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
        let destination = stateDirectory.appendingPathComponent(String(format: "frame_%04d.png", index))
        try data.write(to: destination, options: .atomic)
        frameCounts[state, default: 0] += 1
        if index == 0 || index + 1 == total || index % 10 == 0 {
            onProgress?("正在生成 \(displayName(for: state))：\(index + 1)/\(total)")
        }
    }

    private func receiveState(_ body: [String: Any]) throws {
        guard let state = body["state"] as? String,
              let count = body["count"] as? Int,
              let duration = body["duration"] as? Double,
              let bbox = body["bbox"] as? [Int],
              bbox.count == 4,
              frameCounts[state] == count else {
            throw PRTSImportError.incompleteFrames
        }
        let croppedBounds = try cropFrames(for: state, count: count, bounds: bbox)
        stateMetadata[state] = [
            "duration": Int((duration * 1000).rounded()),
            "count": count,
            "bbox": croppedBounds,
            "source": "PRTS Spine model"
        ]
    }

    private func cropFrames(for state: String, count: Int, bounds: [Int]) throws -> [Int] {
        guard let petDirectory else { throw PRTSImportError.incompleteFrames }
        let padding = 8
        let minX = max(0, bounds[0] - padding)
        let minY = max(0, bounds[1] - padding)
        let maxX = min(999, bounds[2] + padding)
        let maxY = min(999, bounds[3] + padding)
        guard maxX >= minX, maxY >= minY else { throw PRTSImportError.incompleteFrames }

        let width = maxX - minX + 1
        let height = maxY - minY + 1
        let cropRect = CGRect(x: minX, y: 1000 - maxY - 1, width: width, height: height)
        let directory = petDirectory.appendingPathComponent("frames/\(state)", isDirectory: true)
        for index in 0..<count {
            let url = directory.appendingPathComponent(String(format: "frame_%04d.png", index))
            guard let source = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil),
                  let cropped = source.cropping(to: cropRect),
                  let png = NSBitmapImageRep(cgImage: cropped).representation(using: .png, properties: [:]) else {
                throw PRTSImportError.incompleteFrames
            }
            try png.write(to: url, options: .atomic)
        }
        return [0, 0, width - 1, height - 1]
    }

    private func finishPackage() throws {
        guard let petDirectory,
              stateMetadata["idle"] != nil,
              !stateMetadata.isEmpty else {
            throw PRTSImportError.incompleteFrames
        }
        let manifest: [String: Any] = [
            "fps": 20,
            "size": 1000,
            "states": stateMetadata
        ]
        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: petDirectory.appendingPathComponent("manifest.json"), options: .atomic)
        finish(.success(PetPackageCandidate(name: petName, url: petDirectory)))
    }

    private func finish(_ result: Result<PetPackageCandidate, Error>) {
        guard !finished else { return }
        finished = true
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "prts")
        webView?.stopLoading()
        renderWindow?.orderOut(nil)
        webView = nil
        renderWindow = nil
        if case .failure = result, let workDirectory {
            try? FileManager.default.removeItem(at: workDirectory)
        }
        let continuation = continuation
        self.continuation = nil
        continuation?.resume(with: result)
    }

    private func displayName(for state: String) -> String {
        ["idle": "待机", "interact": "互动", "move": "移动", "sit": "坐下", "sleep": "睡眠"][state] ?? state
    }

    private func captureHTML(configJSON: String, viewerScriptURL: String) -> String {
        """
        <!doctype html>
        <html><head><meta charset="utf-8"><style>html,body{margin:0;background:transparent}</style></head>
        <body>
        <canvas id="capture" width="1000" height="1000"></canvas>
        <div id="spine-root" data-id="placeholder"></div>
        <script>
        const CONFIG = \(configJSON);
        const FPS = 20;
        const wanted = [
          {name:'Relax', state:'idle'},
          {name:'Interact', state:'interact'},
          {name:'Move', state:'move'},
          {name:'Sit', state:'sit'},
          {name:'Sleep', state:'sleep'}
        ];
        const send = value => webkit.messageHandlers.prts.postMessage(value);
        window.onerror = (message, source, line) => send({type:'error', message:String(message), source, line});
        window.addEventListener('unhandledrejection', event => send({type:'error', message:String(event.reason)}));
        const renderedFrame = () => new Promise(resolve => requestAnimationFrame(resolve));

        window.addEventListener('spine_api_ready', async () => {
          try {
            const canvas = document.getElementById('capture');
            const spine = new window.SpineApi(canvas);
            const skin = CONFIG.skin === null ? undefined : CONFIG.skin;
            const current = await spine.load(
              'pet', CONFIG.fileURL + '.skel', CONFIG.fileURL + '.atlas',
              {x:-500, y:-200, scale:1}, skin
            );
            spine.play('pet');
            await renderedFrame();
            const available = new Map(current.skeleton.data.animations.map(animation => [animation.name.toLowerCase(), animation]));
            send({type:'ready'});

            for (const requested of wanted) {
              const animation = available.get(requested.name.toLowerCase());
              if (!animation || animation.duration <= 0) continue;
              current.state.clearTracks();
              current.skeleton.setToSetupPose();
              spine.setAnimation(animation.name, false);
              current.state.timeScale = 0;
              const entry = current.state.getCurrent(0);
              const count = Math.max(1, Math.round(animation.duration * FPS));
              let minX = 1000, minY = 1000, maxX = -1, maxY = -1;

              for (let index = 0; index < count; index++) {
                entry.trackTime = Math.min(animation.duration - 0.001, index / FPS);
                await renderedFrame();
                const gl = spine.context.gl;
                const pixels = new Uint8Array(1000 * 1000 * 4);
                gl.readPixels(0, 0, 1000, 1000, gl.RGBA, gl.UNSIGNED_BYTE, pixels);
                for (let y = 0; y < 1000; y += 2) {
                  for (let x = 0; x < 1000; x += 2) {
                    if (pixels[(y * 1000 + x) * 4 + 3] > 10) {
                      if (x < minX) minX = x;
                      if (x > maxX) maxX = x;
                      if (y < minY) minY = y;
                      if (y > maxY) maxY = y;
                    }
                  }
                }
                send({
                  type:'frame', state:requested.state, index, total:count,
                  data:canvas.toDataURL('image/png')
                });
              }
              const bbox = maxX >= 0 ? [minX, minY, maxX, maxY] : [0, 0, 999, 999];
              send({type:'state', state:requested.state, count, duration:animation.duration, bbox});
            }
            send({type:'complete'});
          } catch (error) {
            send({type:'error', message:String(error), stack:error.stack || ''});
          }
        });
        </script>
        <script type="module" crossorigin src="\(viewerScriptURL)"></script>
        </body></html>
        """
    }
}
