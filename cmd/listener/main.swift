import Cocoa
import Carbon
import QuartzCore

class HUDOverlay {
    var window: NSPanel?
    var waveBars: [CALayer] = []
    let barWidth: CGFloat = 3.5
    let barSpacing: CGFloat = 4.0
    let baseHeights: [CGFloat] = [6, 10, 8, 5]
    let maxHeights: [CGFloat] = [18, 22, 19, 15]
    let durations: [Double] = [0.32, 0.45, 0.28, 0.38]
    let colors: [NSColor] = [
        NSColor(red: 0.65, green: 0.33, blue: 0.98, alpha: 1.0), // Purple
        NSColor(red: 0.93, green: 0.28, blue: 0.60, alpha: 1.0), // Pink
        NSColor(red: 0.23, green: 0.51, blue: 0.96, alpha: 1.0), // Blue
        NSColor(red: 0.02, green: 0.71, blue: 0.83, alpha: 1.0)  // Cyan
    ]

    init() {
        setupWindow()
    }

    func setupWindow() {
        guard let screen = NSScreen.main else { return }
        let width: CGFloat = 90
        let height: CGFloat = 32
        let x = (screen.frame.width - width) / 2
        let y: CGFloat = 82 // Perfectly balanced above macOS Dock

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

        // Modern frosted glass capsule
        let visualEffect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        visualEffect.material = .hudWindow
        visualEffect.state = .active
        visualEffect.blendingMode = .behindWindow
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = height / 2
        visualEffect.layer?.masksToBounds = true
        visualEffect.layer?.borderWidth = 0.5
        visualEffect.layer?.borderColor = NSColor.white.withAlphaComponent(0.25).cgColor

        // Container view
        let container = NSView(frame: visualEffect.bounds)
        container.wantsLayer = true

        // Center 4 animated waveform bars
        let totalBarsWidth = (CGFloat(baseHeights.count) * barWidth) + (CGFloat(baseHeights.count - 1) * barSpacing)
        let startX = (width - totalBarsWidth) / 2

        for i in 0..<baseHeights.count {
            let bar = CALayer()
            let bx = startX + CGFloat(i) * (barWidth + barSpacing)
            let by = (height - baseHeights[i]) / 2
            bar.frame = CGRect(x: bx, y: by, width: barWidth, height: baseHeights[i])
            bar.cornerRadius = barWidth / 2
            bar.backgroundColor = colors[i].cgColor
            bar.shadowColor = colors[i].cgColor
            bar.shadowRadius = 4
            bar.shadowOpacity = 0.8
            bar.shadowOffset = .zero

            container.layer?.addSublayer(bar)
            waveBars.append(bar)
        }

        visualEffect.addSubview(container)
        panel.contentView = visualEffect
        panel.alphaValue = 0.0

        self.window = panel
    }

    func showListening() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let window = self.window else { return }

            // Play start sound (crisp subtle feedback)
            NSSound(named: "Pop")?.play()

            // Animate waveform bars
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

            // Play stop sound (delicate chime)
            NSSound(named: "Tink")?.play()

            // Stop dancing bars, pulse gently into calm state
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

class PushToTalkListener {
    var isRecording = false
    var recProcess: Process?
    let audioPath = "/tmp/aurae_ptt.wav"
    let auraeBin: String
    let hud = HUDOverlay()

    init() {
        let currentDir = FileManager.default.currentDirectoryPath
        let localBin = "\(currentDir)/bin/aurae"
        if FileManager.default.fileExists(atPath: localBin) {
            self.auraeBin = localBin
        } else {
            self.auraeBin = "/usr/local/bin/aurae"
        }
    }

    func start() {
        print("🎧 [Aurae Listener] Modo Push-to-Talk activo.")
        print("👉 Mantén presionado [Shift + Option] para hablar.")
        print("👉 Suelta cualquiera de las teclas para transcribir y pegar.\n")

        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let accessEnabled = AXIsProcessTrustedWithOptions(options)
        if !accessEnabled {
            print("⚠️  AVISO DE PERMISOS: Concede permiso de Accesibilidad a tu terminal si el sistema lo solicita.")
        }

        let eventMask = (1 << CGEventType.flagsChanged.rawValue)

        guard let eventTap = CGEvent.tapCreate(
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
            print("❌ Error creando EventTap. Asegúrate de otorgar permisos de Accesibilidad a tu terminal en:")
            print("   Ajustes del Sistema -> Privacidad y Seguridad -> Accesibilidad.")
            exit(1)
        }

        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        CFRunLoopRun()
    }

    func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let flags = event.flags
        let isShiftDown = flags.contains(.maskShift)
        let isOptionDown = flags.contains(.maskAlternate)
        let isComboActive = isShiftDown && isOptionDown

        if type == .flagsChanged {
            if isComboActive {
                if !isRecording {
                    startRecording()
                }
            } else {
                if isRecording {
                    stopRecording()
                }
            }
        }

        return Unmanaged.passRetained(event)
    }

    func startRecording() {
        guard !isRecording else { return }
        isRecording = true
        print("🎙️  [Aurae] Grabando...")

        // Show modern animated waveform HUD & play sound
        hud.showListening()

        // Remove old audio if any
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
        print("⏳ [Aurae] Procesando y pegando...")

        // Update HUD & play chime sound
        hud.showProcessing()

        recProcess?.interrupt()
        recProcess?.waitUntilExit()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            if let attrs = try? FileManager.default.attributesOfItem(atPath: self.audioPath),
               let size = attrs[.size] as? Int64, size > 1000 {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: self.auraeBin)
                p.arguments = ["--model", "small", "file", self.audioPath]
                try? p.run()
                p.waitUntilExit()
            }

            // Hide HUD after paste completes
            self.hud.hide()
            print("✨ [Aurae] Listo.\n")
        }
    }
}

// Ensure NSApplication is initialized for UI
let app = NSApplication.shared
let listener = PushToTalkListener()
listener.start()
