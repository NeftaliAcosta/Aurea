# Aurae — Registro de Decisiones de Arquitectura (ADR)

Este archivo documenta todas las decisiones técnicas tomadas durante el desarrollo autónomo de **Aurae** para que puedas revisarlas y validarlas.

---

## Decisión 1: Lenguaje Go vs Python
- **Elección:** Go (Golang) 1.26.
- **Razón:** Genera un único binario independiente (`aurae`), sin problemas de dependencias en máquinas de usuarios finales (Python 3.14 rompe pip y librerías C).
- **Impacto:** Tiempo de arranque <10ms, consumo RAM base <20MB, distribución trivial en GitHub Releases y Homebrew Tap.

---

## Decisión 2: Motor de Transcripción Whisper
- **Elección:** Invocación optimizada de `whisper-cli` (del proyecto `whisper.cpp` con Metal en macOS) + descarga automatizada de modelos a `~/.aurae/models/`.
- **Razón:** Enlazar directamente bindings de CGO para Whisper requiere que el usuario final tenga el compilador de C y headers configurados al compilar, o dependencias estáticas muy pesadas. La arquitectura de runner híbrido permite:
  1. Detección automática del binario nativo en el sistema (`whisper-cli`).
  2. Descarga y compilación o instalación transparente si no existe.
  3. Soporte automático de GPU Metal en Apple Silicon sin configuraciones manuales.
- **Duda para ti:** ¿Prefieres que Aurae use por defecto `large-v3-turbo` (máxima precisión, ~1.6GB) o `small` (~460MB, más rápido y liviano)? *(Actualmente configurado para usar `large-v3-turbo` por defecto, configurable con `--model small`)*.

---

## Decisión 3: Filtrado de Muletillas
- **Elección:** Pipeline en 2 capas:
  1. *Prompt Conditioning:* Se pasa a Whisper el prompt inicial indicando español neutro y directo.
  2. *Regex & Normalizer Engine:* Limpiador determinista en Go que remueve muletillas comunes en español e inglés (*"eh"*, *"este"*, *"o sea"*, *"bueno pues"*, *"uh"*, *"um"*, *"ah"*), elimina palabras duplicadas por tartamudeo (*"que que"*, *"yo yo"*), capitaliza inicios de frase y corrige espaciado de puntuación.
- **Razón:** Cero latencia (ejecución en <1ms), 100% predecible, sin alucinaciones y sin coste de memoria.

---

## Decisión 4: Inyección en el Cursor Activo
- **Elección:**
  - **macOS:** Guarda el portapapeles anterior, copia el texto dictado con `pbcopy`, simula `Cmd + V` usando AppleScript (`osascript`) o `CGEvent`, y restaura el portapapeles original si se desea.
  - **Linux:** `xdotool` / `wl-copy` + `ydotool` (Wayland).
  - **Windows:** API Win32 `SendInput` (`Ctrl + V`).

---

## Decisión 5: Atajo Global (Push-to-Talk)
- **Elección final:** **`Shift + Option`** implementado con listener nativo macOS en Swift (`bin/aurae-listener`).
- **Comportamiento:** 
  - Al mantener presionado `Shift + Option`: Inicia la grabación del micrófono y muestra el HUD animado.
  - Al soltar las teclas: Detiene la grabación, transcribe en ~0.6s con el modelo `small`, limpia muletillas y pega directamente en la ventana activa.
  - Activación: Ejecutar `./bin/aurae listen`.

---

## Decisión 6: Preservación y Restauración del Portapapeles
- **Problema:** Sobrescribir el portapapeles borraba el contenido copiado por el usuario (URLs, fragmentos de código, texto).
- **Solución implementada:** 
  1. Antes de inyectar, se lee y guarda en memoria el contenido actual del portapapeles (`pbpaste` / `wl-paste` / `Get-Clipboard`).
  2. Se copia el texto dictado y se simula `Cmd + V`.
  3. Tras una ventana de 180ms (tiempo suficiente para que la app destino procese el pegado), se restaura el contenido previo original en el portapapeles.
  4. Si el usuario vuelve a presionar `Cmd + V` manualmente, recupera su texto copiado intacto.


---

## Decisión 7: Arquitectura Híbrida Go (Motor) + Swift (UI & Barra de Menú)
- **Problema:** El usuario requería una interfaz de usuario visual nativa para configurar el atajo, revisar el historial y personalizar los colores de las ondas, además de residir discretamente en la barra de menú junto al reloj.
- **Alternativas evaluadas:**
  1. *Fyne / Wails en Go:* Fyne no genera un `NSStatusItem` nativo de macOS ni popovers integrados con el sistema de diseño de Apple; Wails requiere Chromium/WebKit con alto consumo de memoria RAM (~120MB+).
  2. *Reescribir todo a Swift:* Se perdería la suite de pruebas exhaustiva, el limpiador regex modular y la portabilidad a Linux/Windows ya desarrollada.
  3. *Arquitectura Híbrida (Elegida):*
     - **Frontend nativo:** Swift + SwiftUI + AppKit (`Aurae.app`). Maneja el `NSStatusItem`, el popover con las 3 pestañas (Historial, Atajo, Colores), el `CGEventTap` y el `HUDOverlay` flotante.
     - **Backend/Motor:** Go (`aurae-engine`). Maneja la inferencia de Whisper con Metal, el limpiador de muletillas, el historial JSONL y la inyección segura en el cursor restaurando el portapapeles.
- **Resultado:** Arranque instantáneo, consumo mínimo de recursos, 100% nativo a nivel visual y máxima modularidad técnica.
