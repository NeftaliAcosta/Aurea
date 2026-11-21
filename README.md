# 🎙️ Aurae

> **Dictado por voz inteligente, local, privado y 100% gratuito para macOS.**  
> Transcribe tu voz directamente donde esté tu cursor, eliminando automáticamente muletillas y preservando tu portapapeles intacto. Cero llamadas a APIs de pago, cero límites.

![Aurae MenuBar App](https://img.shields.io/badge/macOS-Sonoma%20%7C%20Sequoia-black?style=flat-square&logo=apple)
![Whisper.cpp](https://img.shields.io/badge/Whisper.cpp-Metal%20GPU-blue?style=flat-square)
![Go & Swift](https://img.shields.io/badge/Architecture-Go%20%2B%20SwiftUI-purple?style=flat-square)
![License](https://img.shields.io/badge/License-MIT-green?style=flat-square)

---

## ⚡ Características Principales

- **100% Gratis y Privado:** Todo corre en tu equipo vía `whisper.cpp` con aceleración GPU Metal. Sin suscripciones, sin telemetría, sin enviar audio a servidores externos.
- **App Nativa en la Barra de Menú (`Aurae.app`):** Vive discretamente al lado del reloj del sistema con un panel desplegable de control.
- **HUD Flotante Bioluminiscente:** Al hablar, aparece una elegante píldora flotante con barras de sonido animadas que reaccionan a tu voz.
- **Preservación Total del Portapapeles:** Dicta un texto sin perder lo que tenías copiado previamente. Aurae restaura tu portapapeles original de forma automática.
- **Filtro Inteligente de Muletillas y Formato por Voz:** Remueve muletillas (*"eh"*, *"este"*, *"o sea"*), tartamudeos (*"que que"*), y transforma comandos hablados (*"dos puntos"*, *"punto y aparte"*, *"piñata/viñeta"*, *"inciso a"*) en formato profesional y limpio.
- **Panel de Control con 3 Pestañas:**
  1. **Historial:** Registro persistente de todos tus dictados con buscador en tiempo real y botón de copiado rápido con feedback visual.
  2. **Atajo Push-to-Talk:** Elige entre `Shift + Option` (por defecto), `Option + Space`, `Control + Space` o `Control + Option`.
  3. **Personalización de Colores:** Selector de temas (*Cyberpunk*, *Siri / Apple*, *Sunset*, *Emerald*, *Monocromo*) con previsualización en vivo.

---

## 🖥️ La Interfaz de Usuario (SwiftUI + AppKit)

Aurae cuenta con una aplicación nativa diseñada específicamente para macOS:

- **Icono en la barra de menú:** Haz clic en el icono de ondas sonoras junto al reloj para abrir el panel de control (370x490 pt).
- **Tab Historial:** Consulta tus dictados anteriores, filtra con la barra de búsqueda y copia cualquiera de ellos con un clic.
- **Tab Atajo:** Cambia al instante la combinación de teclas para mantener mientras hablas.
- **Tab Colores:** Selecciona tu paleta preferida para que el HUD flotante coincida con la estética de tu escritorio.

---

## 🛠️ Requisitos Previos

En macOS, instala el motor Whisper y el grabador de audio con Homebrew:
```bash
brew install whisper-cpp sox
```

Verifica que tu entorno esté 100% listo con:
```bash
aurae doctor
```

---

## 🚀 Instalación y Compilación

### Compilar desde código fuente
```bash
git clone https://github.com/neftaliacosta/aurae.git
cd aurae

# Compilar tanto el CLI en Go como la app nativa en Swift
make build

# Instalar Aurae.app en /Applications y aurae en /usr/local/bin
make install

# Abrir Aurae directamente
open /Applications/Aurae.app
```

---

## 📖 Modo de Uso

### 1. Con la App de la Barra de Menú (Recomendado)
1. Inicia `Aurae.app` (se situará en tu barra de menú superior).
2. Ve a cualquier aplicación (VS Code, Slack, Notion, navegador, terminal, WhatsApp).
3. **Mantén presionado `Shift + Option`** (o tu atajo configurado) mientras hablas.
4. **Suelta las teclas:** Aurae transcribe en ~0.5s con aceleración Metal, limpia el texto, lo pega en tu cursor y restaura lo que tenías copiado.

### 2. Desde la Terminal (Modo CLI)
```bash
# Dictar y pegar interactivo con Enter
aurae record

# Escuchar globalmente en modo terminal
aurae listen

# Transcribir un archivo de audio existente
aurae file mi_grabacion.wav

# Diagnóstico del sistema y dependencias
aurae doctor

# Ver o modificar configuración
aurae config get hotkey
aurae config set model small
```

---

## 🏗️ Arquitectura Técnica

```
┌────────────────────────────────────────────────────────┐
│                   Aurae.app (Swift)                    │
│  - NSStatusItem (Barra de menú macOS junto al reloj)   │
│  - Popover SwiftUI (Historial, Atajos, Colores)        │
│  - EventTap global de teclado (Push-to-Talk)           │
│  - Floating HUD Overlay animado (CALayer + Waveform)   │
└──────────────────────────┬─────────────────────────────┘
                           │ Invoca
┌──────────────────────────▼─────────────────────────────┐
│                 aurae-engine (Go Core)                 │
│  - internal/audio: Grabación 16kHz WAV mono            │
│  - internal/engine: Runner whisper.cpp + Metal GPU     │
│  - internal/cleaner: Regex pipeline limpiador          │
│  - internal/injector: Preservación + Pegado en cursor  │
│  - internal/history: Persistencia JSONL                │
└────────────────────────────────────────────────────────┘
```

---

## 🧪 Pruebas Unitarias

```bash
# Ejecutar suite de pruebas de Go
make test

# Ejecutar diagnóstico de dependencias
make doctor
```

---

## 📄 Licencia

Distribuido bajo la licencia MIT. Consulta `LICENSE` para más información.
