import Cocoa
import SwiftUI
import Carbon
import QuartzCore
import ApplicationServices
import ServiceManagement
import AVFoundation
import Darwin

// MARK: - Logging

func auraeLog(_ message: String) {
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let line = "[\(timestamp)] \(message)\n"
    print(line, terminator: "")
    
    let home = FileManager.default.homeDirectoryForCurrentUser
    let logURL = home.appendingPathComponent(".aurae/aurae.log")
    if let data = line.data(using: .utf8) {
        if FileManager.default.fileExists(atPath: logURL.path) {
            if let handle = try? FileHandle(forWritingTo: logURL) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            }
        } else {
            try? data.write(to: logURL)
        }
    }
}

// MARK: - Models and Config

struct AudioInputDevice: Identifiable, Hashable {
    let id: String
    let name: String
}

struct ConfigData: Codable {
    var model: String = "small"
    var language: String = "es"
    var remove_fillers: Bool = true
    var auto_paste: Bool = true
    var hotkey: String = "shift+option"
    var waveform_colors: [String] = ["#A855F7", "#EC4899", "#3B82F6", "#06B6D4"]
    var sound_effects: Bool = true
    var audio_device: String = "default"

    enum CodingKeys: String, CodingKey {
        case model, language, remove_fillers, auto_paste, hotkey, waveform_colors, sound_effects, audio_device
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.model = try container.decodeIfPresent(String.self, forKey: .model) ?? "small"
        self.language = try container.decodeIfPresent(String.self, forKey: .language) ?? "es"
        self.remove_fillers = try container.decodeIfPresent(Bool.self, forKey: .remove_fillers) ?? true
        self.auto_paste = try container.decodeIfPresent(Bool.self, forKey: .auto_paste) ?? true
        self.hotkey = try container.decodeIfPresent(String.self, forKey: .hotkey) ?? "shift+option"
        self.waveform_colors = try container.decodeIfPresent([String].self, forKey: .waveform_colors) ?? ["#A855F7", "#EC4899", "#3B82F6", "#06B6D4"]
        self.sound_effects = try container.decodeIfPresent(Bool.self, forKey: .sound_effects) ?? true
        self.audio_device = try container.decodeIfPresent(String.self, forKey: .audio_device) ?? "default"
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

struct DictionaryEntry: Identifiable, Codable {
    var id: UUID = UUID()
    var word: String
    var replacement: String

    enum CodingKeys: String, CodingKey {
        case word, replacement
    }
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
    @Published var dictionary: [DictionaryEntry] = []
    @Published var selectedTab = 0
    @Published var isListening = false
    @Published var hasAccessibilityPermission: Bool = AXIsProcessTrusted()
    @Published var launchAtLogin: Bool = false
    @Published var copiedId: String? = nil
    @Published var searchText: String = ""
    @Published var dictionarySearchText: String = ""
    @Published var newDictionaryWord: String = ""
    @Published var newDictionaryReplacement: String = ""
    @Published var audioDevices: [AudioInputDevice] = [AudioInputDevice(id: "default", name: "Predeterminado del Sistema")]

    var filteredDictionary: [DictionaryEntry] {
        if dictionarySearchText.trimmingCharacters(in: .whitespaces).isEmpty {
            return dictionary
        }
        return dictionary.filter {
            $0.word.localizedCaseInsensitiveContains(dictionarySearchText) ||
            $0.replacement.localizedCaseInsensitiveContains(dictionarySearchText)
        }
    }

    let configURL: URL
    let historyURL: URL
    let dictionaryURL: URL
    private var permTimer: Timer?

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(".aurae")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.configURL = dir.appendingPathComponent("config.json")
        self.historyURL = dir.appendingPathComponent("history.jsonl")
        self.dictionaryURL = dir.appendingPathComponent("dictionary.json")

        loadConfig()
        loadHistory()
        loadDictionary()
        refreshAudioDevices()
        startPermissionWatcher()
        checkLaunchAtLoginStatus()
    }

    func refreshAudioDevices() {
        var list: [AudioInputDevice] = [AudioInputDevice(id: "default", name: "Predeterminado del Sistema")]
        let types: [AVCaptureDevice.DeviceType]
        if #available(macOS 14.0, *) {
            types = [.microphone, .external]
        } else {
            types = [.builtInMicrophone, .externalUnknown]
        }
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: types,
            mediaType: .audio,
            position: .unspecified
        )
        for dev in session.devices {
            if !list.contains(where: { $0.id == dev.localizedName }) {
                list.append(AudioInputDevice(id: dev.localizedName, name: dev.localizedName))
            }
        }
        self.audioDevices = list
    }

    func checkLaunchAtLoginStatus() {
        if #available(macOS 13.0, *) {
            self.launchAtLogin = (SMAppService.mainApp.status == .enabled)
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    if SMAppService.mainApp.status != .enabled {
                        try SMAppService.mainApp.register()
                    }
                } else {
                    if SMAppService.mainApp.status == .enabled {
                        try SMAppService.mainApp.unregister()
                    }
                }
                self.launchAtLogin = (SMAppService.mainApp.status == .enabled)
                auraeLog("[Auto-Launch] Inicio con macOS actualizado a: \(self.launchAtLogin)")
            } catch {
                auraeLog("[Auto-Launch] Error al cambiar estado: \(error)")
                self.launchAtLogin = (SMAppService.mainApp.status == .enabled)
            }
        }
    }

    func startPermissionWatcher() {
        self.hasAccessibilityPermission = AXIsProcessTrusted()
        permTimer?.invalidate()
        permTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            let trusted = AXIsProcessTrusted()
            if self?.hasAccessibilityPermission != trusted {
                self?.hasAccessibilityPermission = trusted
                auraeLog("[Permisos] Estado de Accesibilidad actualizado: \(trusted)")
            }
        }
    }

    func checkAndPromptAccessibility() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let trusted = AXIsProcessTrustedWithOptions(options)
        self.hasAccessibilityPermission = trusted
        if !trusted {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
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

    func loadDictionary() {
        guard let data = try? Data(contentsOf: dictionaryURL),
              let decoded = try? JSONDecoder().decode([DictionaryEntry].self, from: data) else {
            self.dictionary = [
                DictionaryEntry(word: "aurea", replacement: "Aurae"),
                DictionaryEntry(word: "nectalia costa", replacement: "Neftali Acosta")
            ]
            saveDictionary()
            return
        }
        self.dictionary = decoded
    }

    func saveDictionary() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(dictionary) {
            try? data.write(to: dictionaryURL)
        }
    }

    func addDictionaryEntry(word: String, replacement: String) {
        let w = word.trimmingCharacters(in: .whitespacesAndNewlines)
        let r = replacement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !w.isEmpty && !r.isEmpty else { return }
        dictionary.append(DictionaryEntry(word: w, replacement: r))
        saveDictionary()
        auraeLog("[Diccionario] Regla agregada: \"\(w)\" -> \"\(r)\"")
    }

    func removeDictionaryEntry(id: UUID) {
        dictionary.removeAll { $0.id == id }
        saveDictionary()
        auraeLog("[Diccionario] Regla eliminada.")
    }

    func applyDictionary(to text: String) -> String {
        var result = text
        for entry in dictionary {
            let pattern = "(?i)\\b" + NSRegularExpression.escapedPattern(for: entry.word) + "\\b"
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(result.startIndex..., in: result)
                result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: entry.replacement)
            }
        }
        return result
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
    let baseHeights: [CGFloat] = [4, 7, 5, 4]
    let maxHeights: [CGFloat] = [20, 26, 22, 17]

    private var meterTimer: DispatchSourceTimer?
    private var smoothedLevel: Double = 0.0
    private var fileHandle: FileHandle?
    private let meterQueue = DispatchQueue(label: "com.aurae.hudmeter", qos: .userInteractive)

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

    func reposition() {
        let mouseLoc = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouseLoc, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen = screen, let window = self.window else { return }

        let width = window.frame.width
        let screenFrame = screen.frame
        let x = screenFrame.origin.x + (screenFrame.width - width) / 2
        let y = screenFrame.origin.y + 82

        window.setFrameOrigin(NSPoint(x: x, y: y))
    }

    func showListening(audioPath: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let window = self.window else { return }
            self.stopLevelMeter()
            self.reposition()
            self.updateColors()
            if AppState.shared.config.sound_effects {
                NSSound(named: "Pop")?.play()
            }

            // Reset wave bars to resting baseline heights
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for (i, bar) in self.waveBars.enumerated() {
                bar.removeAllAnimations()
                let by = (32.0 - self.baseHeights[i]) / 2.0
                bar.frame = CGRect(x: bar.frame.origin.x, y: by, width: self.barWidth, height: self.baseHeights[i])
            }
            CATransaction.commit()

            window.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.10
                window.animator().alphaValue = 1.0
            }

            self.startLevelMeter(audioPath: audioPath)
        }
    }

    private func startLevelMeter(audioPath: String) {
        meterTimer?.cancel()
        meterTimer = nil
        try? fileHandle?.close()
        fileHandle = nil
        smoothedLevel = 0.0

        let timer = DispatchSource.makeTimerSource(queue: meterQueue)
        timer.schedule(deadline: .now() + 0.04, repeating: 0.025) // 40 fps for ultra-smooth responsiveness
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }

            if self.fileHandle == nil {
                self.fileHandle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: audioPath))
            }
            guard let handle = self.fileHandle else { return }

            let currentLen = handle.seekToEndOfFile()
            guard currentLen > 100 else { return }

            // Read last 2048 bytes (~512 samples of 32-bit audio)
            let readLen: UInt64 = min(currentLen - 44, 2048)
            handle.seek(toFileOffset: currentLen - readLen)
            let data = handle.readData(ofLength: Int(readLen))
            let sampleCount = data.count / 4
            guard sampleCount > 0 else { return }

            var sumSq: Double = 0
            data.withUnsafeBytes { raw in
                let ptr = raw.bindMemory(to: Int32.self)
                for i in 0..<sampleCount {
                    let s = Double(ptr[i]) / Double(Int32.max)
                    sumSq += s * s
                }
            }
            let rms = sqrt(sumSq / Double(sampleCount))

            // Highly sensitive non-linear mapping:
            // Noise floor: 0.0008, voice saturation point: 0.040
            let noiseFloor: Double = 0.0008
            let maxVoiceRange: Double = 0.040
            let rawNormalized = max(0.0, min(1.0, (rms - noiseFloor) / maxVoiceRange))
            // Square root curve expands soft and normal voice so waves dance vigorously
            let targetLevel = sqrt(rawNormalized)

            // Fast attack (0.60) for immediate syllable response, smooth decay (0.22)
            let alpha = targetLevel > self.smoothedLevel ? 0.60 : 0.22
            self.smoothedLevel = self.smoothedLevel * (1.0 - alpha) + targetLevel * alpha

            let factors: [CGFloat] = [0.85, 1.0, 0.90, 0.75]
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                for (i, bar) in self.waveBars.enumerated() {
                    let baseH = self.baseHeights[i]
                    let maxH = self.maxHeights[i]
                    let targetH = baseH + (maxH - baseH) * CGFloat(self.smoothedLevel) * factors[i]
                    let by = (32.0 - targetH) / 2.0
                    bar.frame = CGRect(x: bar.frame.origin.x, y: by, width: self.barWidth, height: targetH)
                }
                CATransaction.commit()
            }
        }
        timer.resume()
        self.meterTimer = timer
    }

    private func stopLevelMeter() {
        meterTimer?.cancel()
        meterTimer = nil
        try? fileHandle?.close()
        fileHandle = nil
        smoothedLevel = 0.0
    }

    func showProcessing() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.stopLevelMeter()
            if AppState.shared.config.sound_effects {
                NSSound(named: "Tink")?.play()
            }

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for (i, bar) in self.waveBars.enumerated() {
                bar.removeAllAnimations()
                let by = (32.0 - self.baseHeights[i]) / 2.0
                bar.frame = CGRect(x: bar.frame.origin.x, y: by, width: self.barWidth, height: self.baseHeights[i])
            }
            CATransaction.commit()

            for bar in self.waveBars {
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
            self.stopLevelMeter()
            for bar in self.waveBars {
                bar.removeAllAnimations()
            }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.15
                window.animator().alphaValue = 0.0
            }, completionHandler: {
                window.orderOut(nil)
            })
        }
    }

    func hideImmediate() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let window = self.window else { return }
            self.stopLevelMeter()
            for bar in self.waveBars {
                bar.removeAllAnimations()
            }
            window.alphaValue = 0.0
            window.orderOut(nil)
        }
    }
}

// MARK: - Pasteboard Helper

struct PasteboardSnapshot {
    let items: [[NSPasteboard.PasteboardType: Data]]

    static func capture(from pb: NSPasteboard = .general) -> PasteboardSnapshot {
        var result: [[NSPasteboard.PasteboardType: Data]] = []
        if let pbItems = pb.pasteboardItems {
            for item in pbItems {
                var dict: [NSPasteboard.PasteboardType: Data] = [:]
                for type in item.types {
                    if let data = item.data(forType: type) {
                        dict[type] = data
                    }
                }
                if !dict.isEmpty {
                    result.append(dict)
                }
            }
        }
        return PasteboardSnapshot(items: result)
    }

    func restore(to pb: NSPasteboard = .general) {
        guard !items.isEmpty else { return }
        pb.clearContents()
        var newItems: [NSPasteboardItem] = []
        for dict in items {
            let item = NSPasteboardItem()
            for (type, data) in dict {
                item.setData(data, forType: type)
            }
            newItems.append(item)
        }
        pb.writeObjects(newItems)
    }
}

// MARK: - Global Listener & Keystroke Injection

class PushToTalkListener {
    static let shared = PushToTalkListener()

    var isRecording = false
    var recordingPid: pid_t = 0
    let audioPath = "/tmp/aurae_ptt.wav"
    let auraeBin: String
    let hud = HUDOverlay()
    var targetApp: NSRunningApplication?

    private var pollTimer: Timer?

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
        auraeLog("[Listener] Iniciando Hardware Engine...")
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let trusted = AXIsProcessTrustedWithOptions(options)
        auraeLog("[Listener] AXIsProcessTrusted: \(trusted)")

        pollTimer?.invalidate()
        let timer = Timer(timeInterval: 0.025, repeats: true) { [weak self] _ in
            self?.pollHardwareKeys()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.pollTimer = timer
    }

    func pollHardwareKeys() {
        let flags = CGEventSource.flagsState(.combinedSessionState)
        let mode = AppState.shared.config.hotkey

        var isCombo = false
        switch mode {
        case "option+space":
            let isOpt = flags.contains(.maskAlternate)
            let isSpace = CGEventSource.keyState(.combinedSessionState, key: 49)
            isCombo = isOpt && isSpace
        case "control+space":
            let isCtrl = flags.contains(.maskControl)
            let isSpace = CGEventSource.keyState(.combinedSessionState, key: 49)
            isCombo = isCtrl && isSpace
        case "control+option":
            isCombo = flags.contains(.maskControl) && flags.contains(.maskAlternate)
        default: // "shift+option"
            isCombo = flags.contains(.maskShift) && flags.contains(.maskAlternate)
        }

        // Escape key (keycode 53) cancels recording immediately
        if isRecording && CGEventSource.keyState(.combinedSessionState, key: 53) {
            cancelRecording()
            return
        }

        if isCombo {
            if !isRecording {
                startRecording()
            }
        } else {
            if isRecording {
                stopRecording()
            }
        }
    }

    func startRecording() {
        guard !isRecording else { return }
        isRecording = true
        
        // Capture the active application window BEFORE showing HUD (ignore Aurae itself)
        if let front = NSWorkspace.shared.frontmostApplication,
           front.bundleIdentifier != Bundle.main.bundleIdentifier {
            self.targetApp = front
        }
        auraeLog("[PTT] Grabación iniciada. App destino: \(self.targetApp?.localizedName ?? "Desconocida") (PID: \(self.targetApp?.processIdentifier ?? 0))")

        DispatchQueue.main.async {
            (NSApp.delegate as? AppDelegate)?.closePopover()
            AppState.shared.isListening = true
        }

        hud.showListening(audioPath: audioPath)
        try? FileManager.default.removeItem(atPath: audioPath)

        let selectedDevice = AppState.shared.config.audio_device
        let cArgs: [String]
        if selectedDevice != "default" && AppState.shared.audioDevices.contains(where: { $0.id == selectedDevice }) {
            // Guarantee NFC (composed) canonical mapping so C byte comparison in SoX coreaudio.c matches verbatim
            let nfcDevice = (selectedDevice as NSString).precomposedStringWithCanonicalMapping
            cArgs = ["/opt/homebrew/bin/sox", "-q", "-t", "coreaudio", nfcDevice, "-c", "1", "-r", "16000", audioPath]
            auraeLog("[PTT] Grabando con micrófono seleccionado (posix_spawn): \"\(nfcDevice)\"")
        } else {
            cArgs = ["/opt/homebrew/bin/sox", "-q", "-d", "-c", "1", "-r", "16000", audioPath]
            auraeLog("[PTT] Grabando con micrófono predeterminado (posix_spawn -d)")
        }

        var cArgv: [UnsafeMutablePointer<CChar>?] = cArgs.map { strdup($0) }
        cArgv.append(nil)

        var pid: pid_t = 0
        let spawnStatus = posix_spawn(&pid, "/opt/homebrew/bin/sox", nil, nil, &cArgv, environ)
        for ptr in cArgv {
            if let p = ptr { free(p) }
        }

        if spawnStatus == 0 {
            self.recordingPid = pid
        } else {
            auraeLog("[PTT] Error al iniciar sox con posix_spawn: \(spawnStatus)")
            self.recordingPid = 0
        }
    }

    func cancelRecording() {
        guard isRecording else { return }
        isRecording = false
        auraeLog("[PTT] Grabación cancelada por el usuario.")
        DispatchQueue.main.async { AppState.shared.isListening = false }

        hud.hide()
        let pidToStop = self.recordingPid
        self.recordingPid = 0

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            if pidToStop > 0 {
                kill(pidToStop, SIGINT)
                let startTime = Date()
                var status: Int32 = 0
                while Date().timeIntervalSince(startTime) < 0.5 {
                    let res = waitpid(pidToStop, &status, WNOHANG)
                    if res == pidToStop || res == -1 {
                        break
                    }
                    usleep(30000)
                }
                kill(pidToStop, SIGKILL)
            }
            if let path = self?.audioPath {
                try? FileManager.default.removeItem(atPath: path)
            }
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        auraeLog("[PTT] Teclas soltadas. Procesando audio...")
        DispatchQueue.main.async { AppState.shared.isListening = false }

        hud.showProcessing()
        let pidToStop = self.recordingPid
        self.recordingPid = 0
        let destinationApp = self.targetApp

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            if pidToStop > 0 {
                kill(pidToStop, SIGINT)
                let startTime = Date()
                var status: Int32 = 0
                while Date().timeIntervalSince(startTime) < 0.8 {
                    let res = waitpid(pidToStop, &status, WNOHANG)
                    if res == pidToStop || res == -1 {
                        break
                    }
                    usleep(30000)
                }
                kill(pidToStop, SIGKILL)
            }

            if let attrs = try? FileManager.default.attributesOfItem(atPath: self.audioPath),
               let size = attrs[.size] as? Int64, size > 1000 {
                auraeLog("[PTT] Audio guardado (\(size) bytes). Transcribiendo con whisper...")
                let p = Process()
                p.executableURL = URL(fileURLWithPath: self.auraeBin)
                let model = AppState.shared.config.model.isEmpty ? "small" : AppState.shared.config.model
                p.arguments = ["--model", model, "transcribe", self.audioPath]
                let pipe = Pipe()
                p.standardOutput = pipe
                try? p.run()
                p.waitUntilExit()

                // Hide HUD immediately so WindowServer returns full focus to the target app
                self.hud.hideImmediate()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let rawText = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !rawText.isEmpty {
                    let text = AppState.shared.applyDictionary(to: rawText)
                    auraeLog("[PTT] Transcripción completada: \"\(text)\"")
                    self.pasteDirectly(text: text, targetApp: destinationApp)
                } else {
                    auraeLog("[PTT] Transcripción vacía o silencio.")
                }
            } else {
                auraeLog("[PTT] Audio inexistente o demasiado corto.")
                self.hud.hideImmediate()
            }

            DispatchQueue.main.async {
                AppState.shared.loadHistory()
            }
        }
    }

    func pasteDirectly(text: String, targetApp: NSRunningApplication?) {
        auraeLog("[Inyector] Iniciando pegado para texto: \"\(text)\"")
        
        let pb = NSPasteboard.general
        let snapshot = PasteboardSnapshot.capture(from: pb)

        // 1. Put transcribed text into clipboard
        pb.clearContents()
        pb.setString(text, forType: .string)
        let auraeChangeCount = pb.changeCount

        // 2. Wait until physical modifier keys are completely released
        var retries = 0
        while retries < 30 {
            let hwFlags = CGEventSource.flagsState(.combinedSessionState)
            let hasShift = hwFlags.contains(.maskShift)
            let hasAlt = hwFlags.contains(.maskAlternate)
            let hasCtrl = hwFlags.contains(.maskControl)
            let hasCmd = hwFlags.contains(.maskCommand)
            if !hasShift && !hasAlt && !hasCtrl && !hasCmd {
                break
            }
            usleep(15000) // 15ms
            retries += 1
        }
        auraeLog("[Inyector] Modificadores físicos liberados (reintentos: \(retries))")

        // 3. Re-activate target app if it lost focus
        if let app = targetApp, !app.isActive {
            auraeLog("[Inyector] Reactivando aplicación objetivo: \(app.localizedName ?? "")")
            app.activate()
            usleep(60000) // 60ms settling buffer for OS focus
        } else {
            usleep(40000) // 40ms buffer
        }

        let isTrusted = AXIsProcessTrusted()
        auraeLog("[Inyector] Permiso Accesibilidad actual: \(isTrusted)")

        if !isTrusted {
            // Prompt the user for accessibility permission so they can approve it
            DispatchQueue.main.async {
                AppState.shared.checkAndPromptAccessibility()
            }
        }

        // 4. Inject single clean Cmd+V keystroke directly to session event tap
        let src = CGEventSource(stateID: .hidSystemState)
        if let cmdDown = CGEvent(keyboardEventSource: src, virtualKey: 55, keyDown: true),
           let vDown = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: true),
           let vUp = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: false),
           let cmdUp = CGEvent(keyboardEventSource: src, virtualKey: 55, keyDown: false) {
            cmdDown.flags = .maskCommand
            vDown.flags = .maskCommand
            vUp.flags = .maskCommand
            cmdUp.flags = []

            cmdDown.post(tap: .cgSessionEventTap)
            usleep(15000)
            vDown.post(tap: .cgSessionEventTap)
            usleep(35000)
            vUp.post(tap: .cgSessionEventTap)
            usleep(15000)
            cmdUp.post(tap: .cgSessionEventTap)
            auraeLog("[Inyector] ✅ Evento Cmd+V emitido limpiamente a cgSessionEventTap")
        }

        // 5. Restore previous clipboard rapidly (350ms) so user's clipboard is immediately available
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.35) {
            if NSPasteboard.general.changeCount == auraeChangeCount {
                snapshot.restore(to: NSPasteboard.general)
                auraeLog("[Inyector] Portapapeles original restaurado fielmente (350ms).")
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
                        Text(state.isListening ? "Escuchando..." : (state.hasAccessibilityPermission ? "Listo en segundo plano" : "Permiso de pegado pendiente"))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 10)

            // Accessibility Warning Banner
            if !state.hasAccessibilityPermission {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.system(size: 14))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Requiere Permiso de Accesibilidad")
                            .font(.system(size: 11, weight: .bold))
                        Text("Necesario para pegar automáticamente en tu cursor.")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button("Dar Permiso") {
                        state.checkAndPromptAccessibility()
                    }
                    .font(.system(size: 10, weight: .bold))
                    .buttonStyle(BorderedProminentButtonStyle())
                    .tint(.purple)
                }
                .padding(10)
                .background(Color.orange.opacity(0.12))
                .cornerRadius(8)
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            }

            // Tab Picker
            Picker("", selection: $state.selectedTab) {
                Text("Historial").tag(0)
                Text("Diccionario").tag(1)
                Text("Atajo").tag(2)
                Text("Ajustes").tag(3)
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
                    DictionaryTabView()
                } else if state.selectedTab == 2 {
                    HotkeyTabView()
                } else {
                    SettingsTabView()
                }
            }
            .frame(maxHeight: .infinity)

            Divider()

            // Footer
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Aurae v0.1.0 • 100% Local")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)

                    Button(action: {
                        if let url = URL(string: "https://github.com/NeftaliAcosta/Aurea") {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        HStack(spacing: 3) {
                            Text("por")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                            Text("Neftali Acosta")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.purple)
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 8))
                                .foregroundColor(.purple.opacity(0.8))
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                }

                Spacer()

                Button("Salir") {
                    NSApplication.shared.terminate(nil)
                }
                .font(.system(size: 11))
                .buttonStyle(BorderlessButtonStyle())
                .foregroundColor(.red.opacity(0.8))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.5))
        }
        .frame(width: 410, height: 540)
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

// MARK: - Tab 2: Diccionario View (Scrollable con Buscador)

struct DictionaryTabView: View {
    @ObservedObject var state = AppState.shared

    var body: some View {
        VStack(spacing: 8) {
            // Search & Clear Header
            HStack {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                    TextField("Buscar regla o reemplazo...", text: $state.dictionarySearchText)
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(.system(size: 12))

                    if !state.dictionarySearchText.isEmpty {
                        Button(action: { state.dictionarySearchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .font(.system(size: 11))
                        }
                        .buttonStyle(BorderlessButtonStyle())
                    }
                }
                .padding(6)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)

            // Add Rule Card
            VStack(alignment: .leading, spacing: 6) {
                Text("AÑADIR NUEVA REGLA")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary)
                    .tracking(0.5)

                HStack(spacing: 6) {
                    TextField("Escuchado (ej: aurea)", text: $state.newDictionaryWord)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .font(.system(size: 11))

                    Image(systemName: "arrow.right")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)

                    TextField("Reemplazo (ej: Aurae)", text: $state.newDictionaryReplacement)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .font(.system(size: 11))

                    Button(action: {
                        let w = state.newDictionaryWord.trimmingCharacters(in: .whitespaces)
                        let r = state.newDictionaryReplacement.trimmingCharacters(in: .whitespaces)
                        guard !w.isEmpty && !r.isEmpty else { return }
                        state.addDictionaryEntry(word: w, replacement: r)
                        state.newDictionaryWord = ""
                        state.newDictionaryReplacement = ""
                    }) {
                        HStack(spacing: 3) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 12))
                            Text("Añadir")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.purple)
                        .cornerRadius(6)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(state.newDictionaryWord.trimmingCharacters(in: .whitespaces).isEmpty || state.newDictionaryReplacement.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(10)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
            .cornerRadius(8)
            .padding(.horizontal, 14)

            // Scrollable List of Rules
            if state.filteredDictionary.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "character.book.closed")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text(state.dictionary.isEmpty ? "No hay reglas guardadas aún." : "Sin resultados para la búsqueda.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Text(state.dictionary.isEmpty ? "Agrega palabras o nombres propios que el modelo confunda." : "Verifica los términos o limpia el buscador.")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(state.filteredDictionary) { entry in
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(entry.word)
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundColor(.purple)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.purple.opacity(0.12))
                                            .cornerRadius(4)

                                        Image(systemName: "arrow.right")
                                            .font(.system(size: 9))
                                            .foregroundColor(.secondary.opacity(0.7))

                                        Text(entry.replacement)
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundColor(.primary)
                                    }
                                }

                                Spacer()

                                Button(action: {
                                    state.removeDictionaryEntry(id: entry.id)
                                }) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 11))
                                        .foregroundColor(.red.opacity(0.8))
                                        .padding(5)
                                        .background(Color.red.opacity(0.1))
                                        .clipShape(Circle())
                                }
                                .buttonStyle(BorderlessButtonStyle())
                                .help("Eliminar regla")
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
                            )
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                }
            }
        }
    }
}

// MARK: - Tab 3: Hotkey View

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
                Text("Mantén presionadas las teclas mientras hablas. Al soltarlas, Aurae transcribe y pega automáticamente en donde tengas colocado el cursor.")
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

// MARK: - Tab 4: Settings View (Modo Discreto, Auto-Launch, Temas)

struct SettingsTabView: View {
    @ObservedObject var state = AppState.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Preferencias del Sistema")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.top, 10)

                // Sound Effects Card
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        ZStack {
                            Circle()
                                .fill(Color.purple.opacity(0.15))
                                .frame(width: 32, height: 32)
                            Image(systemName: state.config.sound_effects ? "speaker.wave.2.fill" : "speaker.slash.fill")
                                .foregroundColor(.purple)
                                .font(.system(size: 14))
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Sonidos de confirmación")
                                .font(.system(size: 13, weight: .medium))
                            Text(state.config.sound_effects ? "Sonidos Pop y Tink activos" : "Modo Discreto (silencioso)")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Toggle("", isOn: Binding(
                            get: { state.config.sound_effects },
                            set: { val in
                                state.config.sound_effects = val
                                state.saveConfig()
                            }
                        ))
                        .toggleStyle(SwitchToggleStyle(tint: .purple))
                        .labelsHidden()
                    }
                }
                .padding(12)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )

                // Auto-Launch at Login Card
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        ZStack {
                            Circle()
                                .fill(Color.blue.opacity(0.15))
                                .frame(width: 32, height: 32)
                            Image(systemName: "macwindow.and.cursorarrow")
                                .foregroundColor(.blue)
                                .font(.system(size: 14))
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Iniciar con macOS")
                                .font(.system(size: 13, weight: .medium))
                            Text(state.launchAtLogin ? "Listo para iniciar al encender el equipo" : "Desactivado (inicio manual)")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Toggle("", isOn: Binding(
                            get: { state.launchAtLogin },
                            set: { state.setLaunchAtLogin($0) }
                        ))
                        .toggleStyle(SwitchToggleStyle(tint: .purple))
                        .labelsHidden()
                    }
                }
                .padding(12)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )

                // Audio Input Microphone Card
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        ZStack {
                            Circle()
                                .fill(Color.teal.opacity(0.15))
                                .frame(width: 32, height: 32)
                            Image(systemName: "mic.fill")
                                .foregroundColor(.teal)
                                .font(.system(size: 14))
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Micrófono de entrada")
                                .font(.system(size: 13, weight: .medium))
                            Text(state.config.audio_device == "default" ? "Predeterminado de macOS" : state.config.audio_device)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        Button(action: { state.refreshAudioDevices() }) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(BorderlessButtonStyle())
                        .help("Actualizar lista de micrófonos")
                    }

                    Picker("", selection: Binding(
                        get: { state.config.audio_device },
                        set: { val in
                            state.config.audio_device = val
                            state.saveConfig()
                            auraeLog("[Audio] Dispositivo de entrada seleccionado: \(val)")
                        }
                    )) {
                        ForEach(state.audioDevices) { dev in
                            Text(dev.name).tag(dev.id)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .labelsHidden()
                }
                .padding(12)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )

                // Waveform Themes Card
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        ZStack {
                            Circle()
                                .fill(Color.purple.opacity(0.15))
                                .frame(width: 32, height: 32)
                            Image(systemName: "paintpalette.fill")
                                .foregroundColor(.purple)
                                .font(.system(size: 14))
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Estilo Visual de Ondas")
                                .font(.system(size: 13, weight: .medium))
                            Text("Paleta de colores para la píldora flotante")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }

                    // Theme selector buttons
                    VStack(spacing: 6) {
                        ForEach(predefinedThemes) { theme in
                            Button(action: { state.updateTheme(theme) }) {
                                HStack {
                                    Text(theme.name)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.primary)

                                    Spacer()

                                    HStack(spacing: 4) {
                                        ForEach(theme.colors, id: \.self) { c in
                                            Circle()
                                                .fill(state.hexToColor(c))
                                                .frame(width: 12, height: 12)
                                        }
                                    }

                                    if state.config.waveform_colors == theme.colors {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(.purple)
                                            .padding(.leading, 4)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                                .cornerRadius(6)
                            }
                            .buttonStyle(BorderlessButtonStyle())
                        }
                    }
                }
                .padding(12)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )

                // Info Card
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.shield.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 12))
                        Text("Privacidad y Rendimiento Local")
                            .font(.system(size: 11, weight: .bold))
                    }
                    Text("Todo el procesamiento de voz ocurre exclusivamente en tu Mac mediante whisper.cpp con aceleración por hardware Metal GPU. Ningún dato sale de tu equipo.")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .background(Color.green.opacity(0.07))
                .cornerRadius(10)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }
}

// MARK: - App Delegate & Menu Bar Setup

class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    var eventMonitor: Any?

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
        popover.contentSize = NSSize(width: 410, height: 540)
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: PopoverView())
        self.popover = popover

        // Start global push-to-talk listener
        PushToTalkListener.shared.start()
        auraeLog("🚀 Aurae MenuBar App lista en la barra superior.")
    }

    @objc func togglePopover() {
        if popover.isShown {
            closePopover()
        } else {
            showPopover()
        }
    }

    func showPopover() {
        guard let button = statusItem.button else { return }
        AppState.shared.hasAccessibilityPermission = AXIsProcessTrusted()
        AppState.shared.loadHistory()
        AppState.shared.refreshAudioDevices()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)

        // Global event monitor closes popover on any click outside
        if eventMonitor == nil {
            eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                self?.closePopover()
            }
        }
    }

    func closePopover() {
        popover.performClose(nil)
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    func popoverDidClose(_ notification: Notification) {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}

// MARK: - Application Entry Point

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
