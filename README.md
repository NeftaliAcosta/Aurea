# 🎙️ Aurae

**English** | [Español](README.es.md)

> **Intelligent, 100% local, private, and native voice dictation for macOS.**  
> Transcribe speech in real-time directly at your cursor position, automatically remove filler words, and keep your clipboard history intact. No subscriptions, no third-party APIs, and zero audio sent over the internet.

---

## ⚡ Key Features

- **Total Privacy (Zero Cloud):** All processing runs entirely on your Mac using `whisper.cpp` with Apple Silicon Metal GPU acceleration. Zero telemetry and no outgoing network requests.
- **Native Menu Bar App (`Aurae.app`):** Sleek, lightweight status bar application accessible right beside the macOS system clock.
- **Floating HUD with Volume-Reactive Waves (Live RMS):** While holding your push-to-talk shortcut, a floating pill appears with bioluminescent waves dynamically responding to your voice amplitude at 40 FPS.
- **Zero-Loss Clipboard Preservation:** Dictate text without overwriting what you previously copied. Aurae captures a multi-type snapshot of your pasteboard and restores it transparently in milliseconds.
- **Hardware-Level Event Injection:** Types directly into whatever app is currently focused (VS Code, Chrome, Slack, Notes, Terminal, WhatsApp, Cursor) using CoreGraphics session event taps.
- **Custom Vocabulary Dictionary:** Map technical terms, acronyms, or names with case-insensitive regex boundary replacement and a real-time search interface.
- **Audio Input Selector:** Switch between the macOS system default microphone or dedicated devices (built-in mic, AirPods, USB interfaces) with hot-plug discovery.
- **Launch at Login:** Native autostart configuration via Apple's official `ServiceManagement` framework.
- **Discreet Mode:** Toggle confirmation sound effects (*Pop* and *Tink*) on or off for quiet work environments.

---

## 🖥️ Menu Bar Panel Overview

Clicking the wave icon in your menu bar opens a popover with four sections:

1. **History:** Searchable log of past transcriptions with one-click copy and visual confirmation feedback.
2. **Dictionary:** Vocabulary replacement engine with instant filtering and quick rule creation/deletion.
3. **Shortcut (Push-to-Talk):** Select your preferred trigger keys:
   - `Shift + Option` (Recommended)
   - `Option + Space`
   - `Control + Space`
   - `Control + Option`
4. **Settings:**
   - Microphone selector with refresh button.
   - Confirmation sound effects toggle (Discreet Mode).
   - Launch at macOS login toggle.
   - Waveform color theme picker (*Cyberpunk*, *Siri*, *Sunset*, *Emerald*, *Monochrome*).
   - Legal, author credits, and bug reporting links.

---

## 🛠️ System Requirements

- **Operating System:** macOS 13.0 (Ventura) or later (fully tested on macOS Sonoma and Sequoia).
- **Architecture:** Apple Silicon (M1/M2/M3/M4) for Metal GPU acceleration.
- **Dependencies:**
  ```bash
  brew install whisper-cpp sox
  ```

---

## 🚀 Building and Installation

### Build from Source

```bash
# 1. Clone the repository
git clone https://github.com/NeftaliAcosta/Aurea.git
cd Aurea

# 2. Compile both the Go engine and native Swift application
make build

# 3. Install Aurae.app into /Applications and CLI into /usr/local/bin
make install

# 4. Launch the application
open /Applications/Aurae.app
```

### System Permissions
On first launch, macOS will request **Accessibility** permission (`System Settings -> Privacy & Security -> Accessibility`) to enable cursor text injection via simulated keyboard events.

---

## 📖 How to Use

1. Start `Aurae.app` (it will sit quietly in your top menu bar).
2. Focus any text field or editor.
3. **Hold down your shortcut** (default: `Shift + Option`) and speak naturally.
4. **Release the keys:** The waves pulse as Whisper transcribes locally (~0.5s), and your text is typed right at your cursor.

---

## 🏗️ Software Architecture

```
┌────────────────────────────────────────────────────────┐
│                   Aurae.app (Swift)                    │
│  - NSStatusItem (macOS Menu Bar App)                   │
│  - SwiftUI Popover (History, Dictionary, Settings)     │
│  - Global Hardware EventTap (Push-to-Talk)             │
│  - Floating Pill HUD (CALayer + 40 FPS real-time RMS)  │
│  - CoreGraphics Keystroke Injector (kCGSessionEventTap)│
└──────────────────────────┬─────────────────────────────┘
                           │ Executes
┌──────────────────────────▼─────────────────────────────┐
│                 aurae-engine (Go Core)                 │
│  - internal/audio: 16kHz mono WAV capture              │
│  - internal/engine: whisper.cpp Metal inference runner │
│  - internal/cleaner: Filler removal & voice formatting │
│  - internal/history: JSONL transcription persistence   │
│  - internal/config: ~/.aurae/config.json manager       │
└────────────────────────────────────────────────────────┘
```

---

## 🧪 Validation and Testing

```bash
# Run unit test suite
make test

# Run system diagnostic doctor
bin/aurae doctor
```

---

## 👤 Author and Contact

- **Author:** Neftali Acosta
- **Contact:** [neftaliacosta@protonmail.com](mailto:neftaliacosta@protonmail.com)
- **Repository:** [github.com/NeftaliAcosta/Aurea](https://github.com/NeftaliAcosta/Aurea)
- **Issue Tracker:** [github.com/NeftaliAcosta/Aurea/issues](https://github.com/NeftaliAcosta/Aurea/issues)

---

## 📄 License

Distributed under the MIT License. See `LICENSE` for details.
