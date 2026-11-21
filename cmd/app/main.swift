import Cocoa
import SwiftUI
import Carbon
import QuartzCore

// MARK: - Models and Config

struct ConfigData: Codable {
    var model: String = "small"
    var language: String = "es"
    var remove_fillers: Bool = true
    var auto_paste: Bool = true
    var hotkey: String = "shift+option"
    var waveform_colors: [String] = ["#A855F7", "#EC4899", "#3B82F6", "#06B6D4"]

    enum CodingKeys: String, CodingKey {
        case model, language, remove_fillers, auto_paste, hotkey, waveform_colors
    }
}

struct HistoryItem: Identifiable, Codable {
    let id: String
    let timestamp: String
    let text: String
    let duration_sec: Double

    var formattedDate: String {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoFormatter.date(from: timestamp) {
            let df = DateFormatter()
            df.dateFormat = "dd/MM HH:mm"
            return df.string(from: date)
        }
        return timestamp
    }
}

struct ColorTheme: Identifiable {
    let id = UUID()
    let name: String
    let colors: [String]
}

let predefinedThemes: [ColorTheme] = [
    ColorTheme(name: "Cyberpunk", colors: ["#A855F7", "#EC4899", "#3B82F6", "#06B6D4"]),
    ColorTheme(name: "Siri / Apple", colors: ["#6366F1", "#3B82F6", "#10B981", "#34D399"]),
    ColorTheme(name: "Sunset", colors: ["#F97316", "#EC4899", "#8B5CF6", "#EF4444"]),
    ColorTheme(name: "Emerald", colors: ["#22C55E", "#4ADE80", "#10B981", "#86EFAC"]),
    ColorTheme(name: "Monocromo", colors: ["#FFFFFF", "#CBD5E1", "#94A3B8", "#64748B"])
]

class AppState: ObservableObject {
    static let shared = AppState()

    @Published var config = ConfigData()
    @Published var history: [HistoryItem] = []
    @Published var selectedTab = 0
    @Published var isListening = false
    @Published var hasAccessibilityPermission = true
    @Published var copiedId: String? = nil
    @Published var searchText: String = ""

    let configURL: URL
    let historyURL: URL

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(".aurae")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.configURL = dir.appendingPathComponent("config.json")
        self.historyURL = dir.appendingPathComponent("history.jsonl")

        loadConfig()
        loadHistory()
    }

    func loadConfig() {
        guard let data = try? Data(contentsOf: configURL),
              let decoded = try? JSONDecoder().decode(ConfigData.self, from: data) else {
            saveConfig()
            return
        }
        self.config = decoded
    }

    func saveConfig() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(config) {
            try? data.write(to: configURL)
        }
    }

    func loadHistory() {
        guard let content = try? String(contentsOf: historyURL, encoding: .utf8) else {
            self.history = []
            return
        }
        var items: [HistoryItem] = []
        let lines = content.components(separatedBy: "\n")
        let decoder = JSONDecoder()
        for line in lines where !line.trimmingCharacters(in: .whitespaces).isEmpty {
            if let d = line.data(using: .utf8), let item = try? decoder.decode(HistoryItem.self, from: d) {
                items.append(item)
            }
        }
        self.history = items.reversed()
    }

    func clearHistory() {
        try? FileManager.default.removeItem(at: historyURL)
        self.history = []
    }

    func updateHotkey(_ newHotkey: String) {
        config.hotkey = newHotkey
        saveConfig()
    }

    func updateTheme(_ theme: ColorTheme) {
        config.waveform_colors = theme.colors
        saveConfig()
    }

    func hexToNSColor(_ hex: String) -> NSColor {
        var cString = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if cString.hasPrefix("#") { cString.removeFirst() }
        if cString.count != 6 { return NSColor.systemPurple }
        var rgbValue: UInt64 = 0
        Scanner(string: cString).scanHexInt64(&rgbValue)
        return NSColor(
            red: CGFloat((rgbValue & 0xFF0000) >> 16) / 255.0,
            green: CGFloat((rgbValue & 0x00FF00) >> 8) / 255.0,
            blue: CGFloat(rgbValue & 0x0000FF) / 255.0,
            alpha: 1.0
        )
    }

    func hexToColor(_ hex: String) -> Color {
        Color(hexToNSColor(hex))
    }
}

// MARK: - HUD Overlay (Floating Pill with Waveform)

class HUDOverlay {
    var window: NSPanel?
    var waveBars: [CALayer] = []
    let barWidth: CGFloat = 3.5
    let barSpacing: CGFloat = 4.0
    let baseHeights: [CGFloat] = [6, 10, 8, 5]
    let maxHeights: [CGFloat] = [18, 22, 19, 15]
    let durations: [Double] = [0.32, 0.45, 0.28, 0.38]

    init() {
        setupWindow()
    }

    func setupWindow() {
        guard let screen = NSScreen.main else { return }
        let width: CGFloat = 90
        let height: CGFloat = 32
        let x = (screen.frame.width - width) / 2
        let y: CGFloat = 82 // Perfectly balanced above Dock

        let panel = NSPanel(
            contentRect: NSRect(x: x, y: y, width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let visualEffect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        visualEffect.material = .hudWindow
        visualEffect.state = .active
        visualEffect.blendingMode = .behindWindow
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = height / 2
        visualEffect.layer?.masksToBounds = true
        visualEffect.layer?.borderWidth = 0.5
        visualEffect.layer?.borderColor = NSColor.white.withAlphaComponent(0.25).cgColor

        let container = NSView(frame: visualEffect.bounds)
        container.wantsLayer = true

        let totalBarsWidth = (CGFloat(baseHeights.count) * barWidth) + (CGFloat(baseHeights.count - 1) * barSpacing)
        let startX = (width - totalBarsWidth) / 2

        for i in 0..<baseHeights.count {
            let bar = CALayer()
            let bx = startX + CGFloat(i) * (barWidth + barSpacing)
            let by = (height - baseHeights[i]) / 2
            bar.frame = CGRect(x: bx, y: by, width: barWidth, height: baseHeights[i])
            bar.cornerRadius = barWidth / 2
            container.layer?.addSublayer(bar)
            waveBars.append(bar)
        }

        visualEffect.addSubview(container)
        panel.contentView = visualEffect
        panel.alphaValue = 0.0

        self.window = panel
    }

    func updateColors() {
        let colors = AppState.shared.config.waveform_colors
        for (i, bar) in waveBars.enumerated() {
            let hex = i < colors.count ? colors[i] : "#A855F7"
            let nsColor = AppState.shared.hexToNSColor(hex)
            bar.backgroundColor = nsColor.cgColor
            bar.shadowColor = nsColor.cgColor
            bar.shadowRadius = 4
            bar.shadowOpacity = 0.8
            bar.shadowOffset = .zero
        }
    }

    func showListening() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let window = self.window else { return }
            self.updateColors()
            NSSound(named: "Pop")?.play()

            for (i, bar) in self.waveBars.enumerated() {
                bar.removeAllAnimations()
                let anim = CABasicAnimation(keyPath: "bounds.size.height")
                anim.duration = self.durations[i]
                anim.fromValue = self.baseHeights[i]
                anim.toValue = self.maxHeights[i]
                anim.autoreverses = true
                anim.repeatCount = .infinity
                anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                bar.add(anim, forKey: "wave")
            }

            window.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.12
                window.animator().alphaValue = 1.0
            }
        }
    }

    func showProcessing() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            NSSound(named: "Tink")?.play()

            for bar in self.waveBars {
                bar.removeAllAnimations()
                let anim = CABasicAnimation(keyPath: "opacity")
                anim.duration = 0.2
                anim.fromValue = 1.0
                anim.toValue = 0.4
                anim.autoreverses = true
                anim.repeatCount = .infinity
                bar.add(anim, forKey: "pulse")
            }
        }
    }

    func hide() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let window = self.window else { return }
            for bar in self.waveBars {
                bar.removeAllAnimations()
            }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.18
                window.animator().alphaValue = 0.0
            }, completionHandler: {
                window.orderOut(nil)
            })
        }
    }
}

// MARK: - Global Listener

class PushToTalkListener {
    static let shared = PushToTalkListener()

    var isRecording = false
    var isOptionDown = false
    var isSpaceDown = false
    var recProcess: Process?
    let audioPath = "/tmp/aurae_ptt.wav"
    let auraeBin: String
    let hud = HUDOverlay()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var permissionTimer: Timer?

    init() {
        let bundleInside = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/aurae-engine").path
        let bundleSibling = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("aurae").path
        let currentDirBin = "\(FileManager.default.currentDirectoryPath)/bin/aurae"
        let usrLocalBin = "/usr/local/bin/aurae"

        if FileManager.default.fileExists(atPath: bundleInside) {
            self.auraeBin = bundleInside
        } else if FileManager.default.fileExists(atPath: bundleSibling) {
            self.auraeBin = bundleSibling
        } else if FileManager.default.fileExists(atPath: currentDirBin) {
            self.auraeBin = currentDirBin
        } else if FileManager.default.fileExists(atPath: usrLocalBin) {
            self.auraeBin = usrLocalBin
        } else {
            self.auraeBin = "aurae"
        }
    }

    func start() {
        checkAndSetupTap()
    }

    func checkAndSetupTap() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let accessEnabled = AXIsProcessTrustedWithOptions(options)
        DispatchQueue.main.async {
            AppState.shared.hasAccessibilityPermission = accessEnabled
        }

        if accessEnabled {
            setupEventTap()
        } else {
            print("⚠️ Permiso de Accesibilidad requerido en Ajustes del Sistema.")
            DispatchQueue.main.async { [weak self] in
                self?.permissionTimer?.invalidate()
                self?.permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
                    if AXIsProcessTrusted() {
                        print("✅ Permiso de Accesibilidad detectado. Iniciando EventTap...")
                        AppState.shared.hasAccessibilityPermission = true
                        timer.invalidate()
                        self?.permissionTimer = nil
                        self?.setupEventTap()
                    }
                }
            }
        }
    }

    func setupEventTap() {
        if eventTap != nil { return }

        let eventMask = (1 << CGEventType.keyDown.rawValue) |
                        (1 << CGEventType.keyUp.rawValue) |
                        (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passRetained(event) }
                let listener = Unmanaged<PushToTalkListener>.fromOpaque(refcon).takeUnretainedValue()
                return listener.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        ) else {
            print("❌ Error creando EventTap de teclado. Reintentando en 1.5s...")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.setupEventTap()
            }
            return
        }

        self.eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        print("🎧 [Aurae Listener] EventTap global activo y escuchando.")
        DispatchQueue.main.async {
            AppState.shared.hasAccessibilityPermission = true
        }
    }

    func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passRetained(event)
        }

        let flags = event.flags
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let mode = AppState.shared.config.hotkey

        var isComboActive = false

        switch mode {
        case "option+space":
            isOptionDown = flags.contains(.maskAlternate)
            if type == .keyDown && keyCode == 49 { isSpaceDown = true }
            if type == .keyUp && keyCode == 49 { isSpaceDown = false }
            if type == .flagsChanged && !isOptionDown { isSpaceDown = false }
            isComboActive = isOptionDown && isSpaceDown

        case "control+space":
            let isCtrlDown = flags.contains(.maskControl)
            if type == .keyDown && keyCode == 49 { isSpaceDown = true }
            if type == .keyUp && keyCode == 49 { isSpaceDown = false }
            if type == .flagsChanged && !isCtrlDown { isSpaceDown = false }
            isComboActive = isCtrlDown && isSpaceDown

        case "control+option":
            isComboActive = flags.contains(.maskControl) && flags.contains(.maskAlternate)

        default: // "shift+option"
            isComboActive = flags.contains(.maskShift) && flags.contains(.maskAlternate)
        }

        if isComboActive {
            if !isRecording {
                startRecording()
                if keyCode == 49 { return nil } // swallow space if used
            }
        } else {
            if isRecording {
                stopRecording()
                if keyCode == 49 { return nil }
            }
        }

        return Unmanaged.passRetained(event)
    }

    func startRecording() {
        guard !isRecording else { return }
        isRecording = true
        DispatchQueue.main.async { AppState.shared.isListening = true }

        hud.showListening()
        try? FileManager.default.removeItem(atPath: audioPath)

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/rec")
        p.arguments = ["-q", "-c", "1", "-r", "16000", audioPath]
        try? p.run()
        self.recProcess = p
    }

    func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        DispatchQueue.main.async { AppState.shared.isListening = false }

        hud.showProcessing()
        recProcess?.interrupt()
        recProcess?.waitUntilExit()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            if let attrs = try? FileManager.default.attributesOfItem(atPath: self.audioPath),
               let size = attrs[.size] as? Int64, size > 1000 {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: self.auraeBin)
                let model = AppState.shared.config.model.isEmpty ? "small" : AppState.shared.config.model
                p.arguments = ["--model", model, "file", self.audioPath]
                try? p.run()
                p.waitUntilExit()
            }

            self.hud.hide()

            // Reload history on main thread
            DispatchQueue.main.async {
                AppState.shared.loadHistory()
            }
        }
    }
}

// MARK: - SwiftUI Views for the Popover

struct PopoverView: View {
    @ObservedObject var state = AppState.shared

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.purple)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Aurae")
                        .font(.system(size: 15, weight: .bold))
                    HStack(spacing: 4) {
                        Circle()
                            .fill(state.isListening ? Color.red : (state.hasAccessibilityPermission ? Color.green : Color.orange))
                            .frame(width: 7, height: 7)
                        Text(state.isListening ? "Escuchando..." : (state.hasAccessibilityPermission ? "Listo en segundo plano" : "Requiere Accesibilidad"))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            if !state.hasAccessibilityPermission {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.system(size: 11))
                    Text("Activa Accesibilidad para Aurae")
                        .font(.system(size: 11))
                    Spacer()
                    Button("Abrir Ajustes") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .font(.system(size: 10, weight: .bold))
                    .buttonStyle(BorderlessButtonStyle())
                    .foregroundColor(.blue)
                }
                .padding(8)
                .background(Color.orange.opacity(0.12))
                .cornerRadius(6)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }

            // Tab Picker
            Picker("", selection: $state.selectedTab) {
                Text("Historial").tag(0)
                Text("Atajo").tag(1)
                Text("Colores").tag(2)
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            Divider()

            // Tab Content
            Group {
                if state.selectedTab == 0 {
                    HistoryTabView()
                } else if state.selectedTab == 1 {
                    HotkeyTabView()
                } else {
                    AppearanceTabView()
                }
            }
            .frame(maxHeight: .infinity)

            Divider()

            // Footer
            HStack {
                Text("Aurae v0.1.0 • 100% Local")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Spacer()
                Button("Salir") {
                    NSApplication.shared.terminate(nil)
                }
                .font(.system(size: 11))
                .buttonStyle(BorderlessButtonStyle())
                .foregroundColor(.red.opacity(0.8))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.5))
        }
        .frame(width: 370, height: 490)
    }
}

// MARK: - Tab 1: Historial View

struct HistoryTabView: View {
    @ObservedObject var state = AppState.shared

    var filteredHistory: [HistoryItem] {
        if state.searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            return state.history
        }
        return state.history.filter { $0.text.localizedCaseInsensitiveContains(state.searchText) }
    }

    var body: some View {
        VStack(spacing: 8) {
            // Search & Clear Header
            HStack {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                    TextField("Buscar en dictados...", text: $state.searchText)
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(.system(size: 12))
                }
                .padding(6)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)

                if !state.history.isEmpty {
                    Button(action: { state.clearHistory() }) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                    .help("Borrar historial")
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)

            if filteredHistory.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text(state.history.isEmpty ? "No hay dictados guardados aún." : "Sin resultados.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredHistory) { item in
                            HistoryCard(item: item)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                }
            }
        }
    }
}

struct HistoryCard: View {
    let item: HistoryItem
    @ObservedObject var state = AppState.shared

    var isCopied: Bool {
        state.copiedId == item.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(item.formattedDate)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
                Text(String(format: "%.1fs", item.duration_sec))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.8))

                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(item.text, forType: .string)
                    state.copiedId = item.id
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        if state.copiedId == item.id { state.copiedId = nil }
                    }
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10))
                        Text(isCopied ? "Copiado" : "Copiar")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundColor(isCopied ? .green : .blue)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(4)
                }
                .buttonStyle(BorderlessButtonStyle())
            }

            Text(item.text)
                .font(.system(size: 12))
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundColor(.primary)
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

// MARK: - Tab 2: Hotkey View

struct HotkeyTabView: View {
    @ObservedObject var state = AppState.shared

    let options = [
        ("shift+option", "Shift + Option", "Recomendado (Wispr Flow)"),
        ("option+space", "Option + Barra Espaciadora", "Cómodo con el pulgar"),
        ("control+space", "Control + Barra Espaciadora", "Alternativa sin Spotlight"),
        ("control+option", "Control + Option", "Modificadores solos")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Atajo Push-to-Talk (Mantener para hablar)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.top, 12)

            ForEach(options, id: \.0) { opt in
                Button(action: { state.updateHotkey(opt.0) }) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(opt.1)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.primary)
                            Text(opt.2)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if state.config.hotkey == opt.0 {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.purple)
                                .font(.system(size: 16))
                        } else {
                            Circle()
                                .stroke(Color.secondary.opacity(0.4), lineWidth: 1.5)
                                .frame(width: 16, height: 16)
                        }
                    }
                    .padding(10)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                    .cornerRadius(8)
                }
                .buttonStyle(BorderlessButtonStyle())
            }

            Spacer()

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 11))
                        .foregroundColor(.blue)
                    Text("Cómo funciona:")
                        .font(.system(size: 11, weight: .bold))
                }
                Text("Mantén presionadas las teclas mientras hablas. Al soltarlas, Aurae transcribe, limpia muletillas y pega directamente en tu cursor.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(10)
            .background(Color.blue.opacity(0.08))
            .cornerRadius(8)
        }
        .padding(16)
    }
}

// MARK: - Tab 3: Appearance View (Themes and Live Preview)

struct AppearanceTabView: View {
    @ObservedObject var state = AppState.shared

    var body: some View {
        VStack(spacing: 16) {
            Text("Personaliza el estilo de las ondas")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 12)

            // Live Preview Box
            VStack(spacing: 8) {
                Text("VISTA PREVIA")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary)
                    .tracking(1)

                // The Pill preview
                HStack(spacing: 5) {
                    ForEach(0..<4) { i in
                        let hex = i < state.config.waveform_colors.count ? state.config.waveform_colors[i] : "#A855F7"
                        RoundedRectangle(cornerRadius: 2)
                            .fill(state.hexToColor(hex))
                            .frame(width: 4, height: [12, 22, 16, 9][i])
                            .shadow(color: state.hexToColor(hex).opacity(0.8), radius: 3)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.7))
                .cornerRadius(16)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                )
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
            .cornerRadius(10)

            // Theme Options
            Text("TEMAS PREDEFINIDOS")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 8) {
                ForEach(predefinedThemes) { theme in
                    Button(action: { state.updateTheme(theme) }) {
                        HStack {
                            Text(theme.name)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.primary)

                            Spacer()

                            // Color swatches
                            HStack(spacing: 4) {
                                ForEach(theme.colors, id: \.self) { c in
                                    Circle()
                                        .fill(state.hexToColor(c))
                                        .frame(width: 14, height: 14)
                                }
                            }

                            if state.config.waveform_colors == theme.colors {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.purple)
                                    .padding(.leading, 6)
                            }
                        }
                        .padding(10)
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                        .cornerRadius(8)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                }
            }

            Spacer()
        }
        .padding(.horizontal, 16)
    }
}

// MARK: - App Delegate & Menu Bar Setup

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set up Menubar Item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "waveform.circle.fill", accessibilityDescription: "Aurae")
            button.action = #selector(togglePopover)
            button.target = self
        }

        // Set up Popover
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 370, height: 490)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: PopoverView())
        self.popover = popover

        // Start global push-to-talk listener
        PushToTalkListener.shared.start()
        print("🚀 Aurae MenuBar App lista en la barra superior.")
    }

    @objc func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            AppState.shared.loadHistory()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }
}

// MARK: - Application Entry Point

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
