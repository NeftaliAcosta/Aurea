# 🎙️ Aurae

[English](README.md) | **Español**

> **Dictado por voz inteligente, 100% local, privado y nativo para macOS.**  
> Transcribe voz en tiempo real directamente en la posición de tu cursor, limpia muletillas automáticamente y preserva tu portapapeles intacto. Sin suscripciones, sin APIs de terceros y sin enviar audio a internet.

---

## ⚡ Características Principales

- **Privacidad Total (Zero Cloud):** Todo el procesamiento ocurre en local mediante `whisper.cpp` acelerado por hardware con Metal GPU. Cero telemetría y cero conexiones salientes.
- **App Nativa en Barra de Menú (`Aurae.app`):** Panel desplegable accesible desde el icono superior junto al reloj de macOS.
- **Píldora Flotante con Ondas Reactivas (RMS en vivo):** Mientras mantienes pulsado el atajo, aparece un HUD flotante cuyas ondas bioluminiscentes responden dinámicamente al volumen y cadencia de tu voz a 40 FPS.
- **Preservación Fiel del Portapapeles:** Dicta cualquier texto sin perder lo que tenías copiado. Aurae toma una instantánea del portapapeles y lo restaura de forma transparente en milisegundos.
- **Inyección por Eventos de Hardware:** Pega directamente en cualquier aplicación activa (VS Code, Chrome, Slack, Notes, Terminal, WhatsApp, Cursor) usando eventos CoreGraphics a nivel de sesión.
- **Diccionario Personalizado:** Mapea términos técnicos, acrónimos o nombres propios con reemplazos regex insensibles a mayúsculas y buscador integrado.
- **Selector de Entrada de Audio:** Elige entre el micrófono predeterminado del sistema o dispositivos específicos (micrófono integrado, AirPods, interfaces USB) con soporte para reconexión en caliente.
- **Iniciar con macOS:** Configuración de arranque automático al iniciar sesión mediante el framework nativo `ServiceManagement`.
- **Modo Discreto:** Alterna los efectos sonoros de confirmación (*Pop* y *Tink*) para trabajar en entornos silenciosos.

---

## 🖥️ Estructura del Panel de Control

La ventana emergente de Aurae incluye cuatro secciones:

1. **Historial:** Registro local de transcripciones con buscador en vivo y botón para copiar con un solo clic.
2. **Diccionario:** Administrador de reglas de sustitución con buscador instantáneo y altas/bajas de términos.
3. **Atajo (Push-to-Talk):** Selector de combinación de teclas para mantener mientras hablas:
   - `Shift + Option` (Recomendado)
   - `Option + Barra Espaciadora`
   - `Control + Barra Espaciadora`
   - `Control + Option`
4. **Ajustes:**
   - Selector de micrófono de entrada con botón de refresco.
   - Interruptor de sonidos de confirmación (Modo Discreto).
   - Interruptor de inicio con macOS.
   - Selector de paletas visuales para las ondas (*Cyberpunk*, *Siri*, *Sunset*, *Emerald*, *Monocromo*).
   - Información de autoría, contacto, soporte y licencia.

---

## 🛠️ Requisitos del Sistema

- **Sistema Operativo:** macOS 13.0 (Ventura) o superior (probado en Sonoma y Sequoia).
- **Arquitectura:** Apple Silicon (M1/M2/M3/M4) para aceleración Metal GPU.
- **Dependencias:**
  ```bash
  brew install whisper-cpp sox
  ```

---

## 🚀 Instalación y Compilación

### Compilación desde código fuente

```bash
# 1. Clonar el repositorio
git clone https://github.com/NeftaliAcosta/Aurea.git
cd Aurea

# 2. Compilar el motor y la aplicación nativa
make build

# 3. Instalar Aurae.app en /Applications y CLI en /usr/local/bin
make install

# 4. Abrir la aplicación
open /Applications/Aurae.app
```

### Permisos del Sistema
En el primer arranque, macOS solicitará permiso de **Accesibilidad** (`Privacidad y Seguridad -> Accesibilidad`) para permitir la inyección de texto en el cursor mediante simulación de eventos de teclado.

---

## 📖 Flujo de Uso

1. Inicia `Aurae.app` (aparecerá en la barra superior de macOS).
2. Coloca el cursor en cualquier campo de texto o editor.
3. **Mantén presionado el atajo** (por defecto `Shift + Option`) y habla normalmente.
4. **Suelta las teclas:** Las ondas cambiarán a modo de procesamiento y tu texto aparecerá escrito donde esté el cursor.

---

## 🏗️ Arquitectura del Software

```
┌────────────────────────────────────────────────────────┐
│                   Aurae.app (Swift)                    │
│  - NSStatusItem (Barra de menú nativa de macOS)        │
│  - Popover SwiftUI (Historial, Diccionario, Ajustes)   │
│  - Global Hardware EventTap (Push-to-Talk)             │
│  - HUD Flotante (CALayer + RMS en tiempo real a 40fps) │
│  - Inyector CoreGraphics (kCGSessionEventTap)          │
└──────────────────────────┬─────────────────────────────┘
                           │ Ejecuta
┌──────────────────────────▼─────────────────────────────┐
│                 aurae-engine (Go Core)                 │
│  - internal/audio: Captura WAV mono 16kHz              │
│  - internal/engine: Motor de inferencia whisper.cpp    │
│  - internal/cleaner: Filtro de muletillas y formato    │
│  - internal/history: Persistencia de historial JSONL   │
│  - internal/config: Gestión de ~/.aurae/config.json    │
└────────────────────────────────────────────────────────┘
```

---

## 🧪 Validación y Pruebas

```bash
# Ejecutar suite de pruebas unitarias
make test

# Diagnóstico de herramientas del sistema
bin/aurae doctor
```

---

## 👤 Autor y Contacto

- **Autor:** Neftali Acosta
- **Contacto:** [neftaliacosta@protonmail.com](mailto:neftaliacosta@protonmail.com)
- **Repositorio:** [github.com/NeftaliAcosta/Aurea](https://github.com/NeftaliAcosta/Aurea)
- **Reporte de incidencias:** [github.com/NeftaliAcosta/Aurea/issues](https://github.com/NeftaliAcosta/Aurea/issues)

---

## 📄 Licencia

Distribuido bajo la Licencia MIT. Consulta el archivo `LICENSE` para detalles.
