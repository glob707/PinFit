import SwiftUI

@main
struct PinFitApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(width: 800, height: 780)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}

// MARK: - Палитра

enum Palette {
    static let bg1 = Color(red: 0.10, green: 0.06, blue: 0.11)
    static let bg2 = Color(red: 0.15, green: 0.06, blue: 0.16)
    static let accent = Color(red: 1.0, green: 0.36, blue: 0.48)
    static let accent2 = Color(red: 0.72, green: 0.38, blue: 1.0)
    static let ok = Color(red: 0.30, green: 0.85, blue: 0.55)
    static let warn = Color(red: 1.0, green: 0.76, blue: 0.28)
    static let card = Color.white.opacity(0.05)
    static let stroke = Color.white.opacity(0.09)
}

// MARK: - Главный экран

struct ContentView: View {
    @StateObject private var m = Model()

    var body: some View {
        ZStack {
            LinearGradient(colors: [Palette.bg1, Palette.bg2], startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle().fill(Palette.accent.opacity(0.16)).frame(width: 420).blur(radius: 110).offset(x: -300, y: -300)
            Circle().fill(Palette.accent2.opacity(0.16)).frame(width: 380).blur(radius: 110).offset(x: 320, y: 320)

            VStack(spacing: 16) {
                Header(target: m.target)
                LinkBar(m: m)
                PreviewCard(m: m)
                Controls(m: m)
                Footer(m: m)
            }
            .padding(.horizontal, 28)
            .padding(.top, 34)
            .padding(.bottom, 24)
        }
        .ignoresSafeArea()
        .onAppear { m.checkClipboard() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            m.checkClipboard()
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: m.phase)
    }
}

// MARK: - Шапка

struct Header: View {
    let target: CGSize

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LinearGradient(colors: [Palette.accent, Palette.accent2], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 56, height: 56)
                    .shadow(color: Palette.accent.opacity(0.5), radius: 14, y: 6)
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("PinFit").font(.system(size: 26, weight: .bold, design: .rounded))
                Text("Картинка с Pinterest под ваш экран")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Text("Экран \(Int(target.width))×\(Int(target.height))")
                .font(.caption.monospaced())
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(Palette.card))
                .overlay(Capsule().stroke(Palette.stroke))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Ссылка

struct LinkBar: View {
    @ObservedObject var m: Model

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "link").foregroundStyle(.secondary)
            TextField("pin.it/… или pinterest.com/pin/…", text: $m.link)
                .textFieldStyle(.plain)
                .onSubmit { m.load() }
            Button { m.pasteAndLoad() } label: { Label("Вставить", systemImage: "doc.on.clipboard") }
                .buttonStyle(GhostButton(compact: true))
            Button("Загрузить") { m.load() }
                .buttonStyle(PrimaryButton(compact: true))
                .disabled(m.link.trimmingCharacters(in: .whitespaces).isEmpty || m.phase == .loading)
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.card))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Palette.stroke))
    }
}

// MARK: - Превью

struct PreviewCard: View {
    @ObservedObject var m: Model

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Palette.card)
            if let img = m.preview {
                Image(nsImage: img)
                    .resizable().scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .shadow(color: .black.opacity(0.4), radius: 14, y: 6)
                    .padding(10)
                    .opacity(m.phase == .loading ? 0.4 : 1)
            } else if m.phase != .loading {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.down.doc").font(.system(size: 34)).foregroundStyle(Palette.accent)
                    Text("Скопируйте ссылку на пин — я подхвачу её сам")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            if m.phase == .loading { ProgressView("Загружаю…").controlSize(.regular) }
        }
        .overlay(alignment: .bottom) {
            if m.enhancing {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Улучшаю нейросетью…").font(.caption)
                }
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Capsule().fill(.black.opacity(0.65)))
                .padding(.bottom, 18)
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: m.enhancing)
        .frame(height: 400)
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Palette.stroke))
    }
}

// MARK: - Управление

struct Controls: View {
    @ObservedObject var m: Model

    private var scaleTint: Color { m.scale > 1.5 ? Palette.warn : (m.scale > 1 ? Palette.accent : Palette.ok) }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Chip(icon: "photo", title: "Оригинал",
                     value: m.sourceSize.width > 0 ? "\(Int(m.sourceSize.width))×\(Int(m.sourceSize.height))" : "—", tint: Palette.accent2)
                Chip(icon: "arrow.up.left.and.arrow.down.right", title: "Масштаб",
                     value: m.sourceSize.width > 0 ? String(format: "×%.2f", m.scale) : "—", tint: scaleTint)
                VStack(spacing: 8) {
                    Picker("", selection: $m.mode) {
                        ForEach(Model.Mode.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("", selection: $m.enhance) {
                        ForEach(Model.Enhance.allCases) { Text($0.title).tag($0) }
                    }
                }
                .pickerStyle(.segmented).labelsHidden()
                .frame(width: 240)
                .disabled(m.phase != .ready)
            }
            if m.cropAxis != .none {
                HStack(spacing: 10) {
                    Text(m.cropAxis == .vertical ? "Кадр: верх" : "Кадр: лево").font(.caption).foregroundStyle(.secondary)
                    Slider(value: $m.focus, in: 0...1)
                    Text(m.cropAxis == .vertical ? "низ" : "право").font(.caption).foregroundStyle(.secondary)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: m.cropAxis)
    }
}

struct Chip: View {
    let icon: String, title: String, value: String, tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon).foregroundStyle(tint)
                Text(title).foregroundStyle(.secondary)
            }.font(.caption)
            Text(value).font(.system(size: 20, weight: .semibold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.6)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.card))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Palette.stroke))
    }
}

// MARK: - Низ

struct Footer: View {
    @ObservedObject var m: Model

    var body: some View {
        HStack(spacing: 12) {
            if let msg = m.message {
                Label(msg, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(Palette.warn).lineLimit(2)
            } else if let s = m.status {
                Label(s, systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(Palette.ok)
            }
            Spacer()
            if m.savedURL != nil {
                Button("В Finder") { m.reveal() }.buttonStyle(GhostButton())
            }
            Button { m.save() } label: { Label("Сохранить", systemImage: "square.and.arrow.down") }
                .buttonStyle(GhostButton())
                .disabled(m.phase != .ready || m.enhancing)
            Button { m.setWallpaper() } label: { Label("Поставить обоями", systemImage: "sparkles") }
                .buttonStyle(PrimaryButton())
                .disabled(m.phase != .ready || m.enhancing)
        }
    }
}

struct PrimaryButton: ButtonStyle {
    var compact = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 13 : 14, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, compact ? 14 : 22).padding(.vertical, compact ? 6 : 11)
            .background(Capsule().fill(LinearGradient(colors: [Palette.accent, Palette.accent2], startPoint: .leading, endPoint: .trailing)))
            .shadow(color: Palette.accent.opacity(enabled ? 0.45 : 0), radius: 12, y: 5)
            .opacity(enabled ? 1 : 0.55)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

struct GhostButton: ButtonStyle {
    var compact = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 13 : 14, weight: .medium))
            .padding(.horizontal, compact ? 12 : 18).padding(.vertical, compact ? 6 : 10)
            .background(Capsule().fill(Palette.card))
            .overlay(Capsule().stroke(Palette.stroke))
            .opacity(enabled ? 1 : 0.5)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}
