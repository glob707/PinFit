import AppKit
import CoreImage
import SwiftUI

// MARK: - Загрузка

enum FetchError: LocalizedError {
    case badLink, page, download

    var errorDescription: String? {
        switch self {
        case .badLink: return "Нужна ссылка вида https://pin.it/… или https://pinterest.com/pin/…"
        case .page: return "Не удалось открыть страницу пина."
        case .download: return "Картинку скачать не удалось: пин приватный или ссылка устарела."
        }
    }
}

enum Fetcher {
    static let ua = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    static func request(_ url: URL) -> URLRequest {
        var r = URLRequest(url: url, timeoutInterval: 25)
        r.setValue(ua, forHTTPHeaderField: "User-Agent")
        return r
    }

    /// Пин-страница / pin.it → og:image → попытка взять /originals/ → иначе то, что отдал Pinterest.
    static func fetch(_ url: URL) async throws -> (CGImage, URL) {
        var imageURL = url
        if !(url.host ?? "").contains("pinimg.com") {
            imageURL = (try? await ogImage(url)) ?? url
        }
        var candidates: [URL] = []
        if (imageURL.host ?? "").contains("pinimg.com") {
            let s = imageURL.absoluteString.replacingOccurrences(
                of: #"pinimg\.com/\d+x/"#, with: "pinimg.com/originals/", options: .regularExpression)
            if let u = URL(string: s) { candidates.append(u) }
        }
        candidates.append(imageURL)
        for c in candidates {
            if let img = try? await download(c) { return (img, c) }
        }
        throw FetchError.download
    }

    static func ogImage(_ url: URL) async throws -> URL {
        let (data, _) = try await URLSession.shared.data(for: request(url))
        let html = String(decoding: data, as: UTF8.self)
        let patterns = [
            #"<meta[^>]+property=["']og:image["'][^>]+content=["']([^"']+)"#,
            #"<meta[^>]+content=["']([^"']+)["'][^>]+property=["']og:image["']"#,
        ]
        for p in patterns {
            if let re = try? NSRegularExpression(pattern: p),
               let m = re.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               let r = Range(m.range(at: 1), in: html),
               let u = URL(string: String(html[r]).replacingOccurrences(of: "&amp;", with: "&")) {
                return u
            }
        }
        throw FetchError.page
    }

    static func download(_ url: URL) async throws -> CGImage {
        let (data, resp) = try await URLSession.shared.data(for: request(url))
        guard (resp as? HTTPURLResponse)?.statusCode == 200, let img = decode(data) else { throw FetchError.download }
        return img
    }

    /// Декодирует с учётом EXIF-ориентации, без изменения размера.
    static func decode(_ data: Data) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(w, h),
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }
}

// MARK: - Нейросетевой апскейл (Real-ESRGAN ncnn-vulkan, лежит в Resources/realesrgan)

enum Upscaler {
    final class Box: @unchecked Sendable { var p: Process? }

    /// Вход уменьшается так, чтобы после ×4 выйти примерно на 1.25× от нужного размера, и дальше подгонка сожмёт с запасом.
    static func run(source: CGImage, needed: CGFloat, model: String) async -> CGImage? {
        guard let res = Bundle.main.resourceURL?.appendingPathComponent("realesrgan") else { return nil }
        let exe = res.appendingPathComponent("realesrgan-ncnn-vulkan")
        guard FileManager.default.isExecutableFile(atPath: exe.path) else { return nil }

        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("pinfit-\(UUID().uuidString)")
        guard (try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)) != nil else { return nil }
        defer { try? FileManager.default.removeItem(at: tmp) }
        let inURL = tmp.appendingPathComponent("in.png"), outURL = tmp.appendingPathComponent("out.png")

        let f = min(1, 1.25 * needed / 4)
        guard let input = f < 1 ? scaled(source, f) : source, writePNG(input, to: inURL) else { return nil }

        let box = Box()
        let ok: Bool = await withTaskCancellationHandler {
            await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
                let p = Process()
                p.executableURL = exe
                p.arguments = ["-i", inURL.path, "-o", outURL.path, "-n", model, "-s", "4", "-f", "png",
                               "-m", res.appendingPathComponent("models").path]
                p.standardOutput = FileHandle.nullDevice
                p.standardError = FileHandle.nullDevice
                p.terminationHandler = { c.resume(returning: $0.terminationStatus == 0) }
                box.p = p
                do { try p.run() } catch { c.resume(returning: false) }
            }
        } onCancel: { box.p?.terminate() }

        guard ok, let data = try? Data(contentsOf: outURL) else { return nil }
        return Fetcher.decode(data)
    }

    static func scaled(_ img: CGImage, _ f: CGFloat) -> CGImage? {
        let w = max(1, Int((CGFloat(img.width) * f).rounded())), h = max(1, Int((CGFloat(img.height) * f).rounded()))
        guard let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        c.interpolationQuality = .high
        c.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        return c.makeImage()
    }

    static func writePNG(_ img: CGImage, to url: URL) -> Bool {
        guard let d = NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:]) else { return false }
        return (try? d.write(to: url)) != nil
    }
}

// MARK: - Подгонка под экран

enum Renderer {
    /// cover — заполнить экран, лишнее обрезать (focus двигает кадр); contain — вписать целиком на размытый фон.
    static func render(_ src: CGImage, size: CGSize, mode: Model.Mode, focus: CGFloat) -> CGImage? {
        let tw = Int(size.width), th = Int(size.height)
        let w = CGFloat(src.width), h = CGFloat(src.height)

        func canvas() -> CGContext? {
            let c = CGContext(data: nil, width: tw, height: th, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            c?.interpolationQuality = .high
            return c
        }

        guard let c1 = canvas() else { return nil }
        let cover = max(CGFloat(tw) / w, CGFloat(th) / h)
        let dw = w * cover, dh = h * cover
        // В CGContext начало координат снизу, поэтому по вертикали 0 = верх картинки → (1 - focus).
        c1.draw(src, in: CGRect(x: (CGFloat(tw) - dw) * focus, y: (CGFloat(th) - dh) * (1 - focus), width: dw, height: dh))
        guard let coverImg = c1.makeImage() else { return nil }
        if mode == .cover { return coverImg }

        let rect = CGRect(x: 0, y: 0, width: tw, height: th)
        let blurred = CIImage(cgImage: coverImg).clampedToExtent().applyingGaussianBlur(sigma: 45).cropped(to: rect)
        guard let bg = CIContext().createCGImage(blurred, from: rect), let c2 = canvas() else { return coverImg }
        c2.draw(bg, in: rect)
        c2.setFillColor(CGColor(gray: 0, alpha: 0.25))
        c2.fill(rect)
        let fit = min(CGFloat(tw) / w, CGFloat(th) / h)
        let fw = w * fit, fh = h * fit
        c2.draw(src, in: CGRect(x: (CGFloat(tw) - fw) / 2, y: (CGFloat(th) - fh) / 2, width: fw, height: fh))
        return c2.makeImage()
    }
}

// MARK: - Модель

@MainActor
final class Model: ObservableObject {
    enum Phase { case idle, loading, ready }
    enum Axis { case none, horizontal, vertical }
    enum Mode: String, CaseIterable, Identifiable {
        case cover, contain
        var id: String { rawValue }
        var title: String { self == .cover ? "Заполнить" : "Вписать" }
    }

    enum Enhance: String, CaseIterable, Identifiable {
        case off, photo, art
        var id: String { rawValue }
        var title: String { self == .off ? "ИИ: выкл" : (self == .photo ? "ИИ: фото" : "ИИ: арт") }
        var modelName: String? { self == .photo ? "realesrgan-x4plus" : (self == .art ? "realesrgan-x4plus-anime" : nil) }
    }

    @Published var link = ""
    @Published var phase: Phase = .idle
    @Published var mode: Mode = .cover { didSet { rerender() } }
    @Published var focus: Double = 0.5 { didSet { rerender() } }
    @Published var preview: NSImage?
    @Published var enhance: Enhance = .photo { didSet { if oldValue != enhance { startEnhance() } } }
    @Published var enhancing = false
    @Published var sourceSize: CGSize = .zero
    @Published var message: String?
    @Published var status: String?
    @Published var savedURL: URL?

    let target: CGSize = Model.screenPixels()

    private var source: CGImage?
    private var enhanced: CGImage?
    private var enhanceTask: Task<Void, Never>?
    private var result: CGImage?
    private var lastClip = ""
    private var name = "pin"

    static func screenPixels() -> CGSize {
        guard let s = NSScreen.main else { return CGSize(width: 2560, height: 1664) }
        return s.convertRectToBacking(s.frame).size
    }

    /// По какой оси картинка вылезает за экран в режиме «Заполнить».
    var cropAxis: Axis {
        guard mode == .cover, sourceSize.width > 0 else { return .none }
        let a = sourceSize.width / sourceSize.height, t = target.width / target.height
        return abs(a - t) < 0.001 ? .none : (a > t ? .horizontal : .vertical)
    }

    /// Масштаб, который нужен для режима «Заполнить»: по нему решаем, нужен ли апскейл.
    var coverScale: CGFloat {
        guard sourceSize.width > 0 else { return 1 }
        return max(target.width / sourceSize.width, target.height / sourceSize.height)
    }

    /// Во сколько раз пришлось увеличить (>1) или уменьшить (<1) оригинал.
    var scale: CGFloat {
        guard sourceSize.width > 0 else { return 1 }
        let sx = target.width / sourceSize.width, sy = target.height / sourceSize.height
        return mode == .cover ? max(sx, sy) : min(sx, sy)
    }

    // MARK: Загрузка

    func checkClipboard() {
        guard phase != .loading,
              let s = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              s != lastClip, let host = URL(string: s)?.host?.lowercased(),
              host.contains("pinterest.") || host == "pin.it" || host.hasSuffix("pinimg.com") else { return }
        lastClip = s
        link = s
        load()
    }

    func pasteAndLoad() {
        if let s = NSPasteboard.general.string(forType: .string) {
            link = s.trimmingCharacters(in: .whitespacesAndNewlines)
            load()
        }
    }

    func load() {
        let raw = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: raw), url.scheme?.hasPrefix("http") == true else {
            message = FetchError.badLink.localizedDescription
            return
        }
        phase = .loading
        message = nil
        status = nil
        Task {
            do {
                let (img, used) = try await Fetcher.fetch(url)
                source = img
                sourceSize = CGSize(width: img.width, height: img.height)
                name = used.deletingPathExtension().lastPathComponent
                focus = 0.5
                phase = .ready
                startEnhance()
            } catch {
                message = error.localizedDescription
                phase = source == nil ? .idle : .ready
            }
        }
    }

    /// Сначала сразу показываем обычный ресайз, потом, когда нейросеть закончит, заменяем его улучшенным.
    private func startEnhance() {
        enhanceTask?.cancel()
        enhanceTask = nil
        enhanced = nil
        enhancing = false
        message = nil
        rerender()
        guard let source else { return }
        let needed = coverScale
        guard needed > 1 else { return }
        guard let model = enhance.modelName else {
            if needed > 1.5 { message = "Оригинал сильно меньше экрана — без ИИ картинка будет мягкой." }
            return
        }
        enhancing = true
        enhanceTask = Task {
            let out = await Upscaler.run(source: source, needed: needed, model: model)
            guard !Task.isCancelled else { return }
            enhancing = false
            if let out {
                enhanced = out
                rerender()
            } else {
                message = "Нейросеть не отработала — показан обычный ресайз."
            }
        }
    }

    private func rerender() {
        guard let src = enhanced ?? source else { return }
        result = Renderer.render(src, size: target, mode: mode, focus: CGFloat(focus))
        if let r = result { preview = NSImage(cgImage: r, size: NSSize(width: r.width, height: r.height)) }
        savedURL = nil
        status = nil
    }

    // MARK: Результат

    @discardableResult
    func save() -> URL? {
        guard let result else { return nil }
        message = nil
        do {
            let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("PinFit Wallpapers")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let f = DateFormatter()
            f.dateFormat = "yyyyMMdd-HHmmss"
            let file = dir.appendingPathComponent("\(name)_\(result.width)x\(result.height)_\(f.string(from: .now)).png")
            guard let data = NSBitmapImageRep(cgImage: result).representation(using: .png, properties: [:]) else { return nil }
            try data.write(to: file)
            savedURL = file
            status = "Сохранено в Документы/PinFit Wallpapers"
            return file
        } catch {
            message = "Не удалось сохранить: \(error.localizedDescription)"
            return nil
        }
    }

    func setWallpaper() {
        // Имя файла уникально (с временем), иначе macOS может не обновить обои при том же пути.
        guard let file = save(), let screen = NSScreen.main else { return }
        do {
            try NSWorkspace.shared.setDesktopImageURL(file, for: screen, options: [:])
            status = "Поставлено обоями"
        } catch {
            message = "Не удалось поставить обои: \(error.localizedDescription)"
        }
    }

    func reveal() {
        if let u = savedURL { NSWorkspace.shared.activateFileViewerSelecting([u]) }
    }
}
