# 🗺️ Aurae — Roadmap de Implementación

> Registro del progreso y fases del desarrollo de **Aurae**.

---

## ✅ Fase 1: Arquitectura Base y Entorno (Completada)
- [x] Configuración de Go Modules (`github.com/neftaliacosta/aurae`).
- [x] Verificación de dependencias locales (`whisper-cli` y `rec`).
- [x] Estructura modular estándar de Go (`cmd/aurae`, `internal/audio`, `internal/cleaner`, `internal/engine`, `internal/injector`, `internal/config`, `internal/history`).
- [x] Descarga de modelos Whisper a `~/.aurae/models/` (`small` y `large-v3-turbo`).

---

## ✅ Fase 2: Motor de Limpieza e Inyección (Completada)
- [x] Limpiador de muletillas determinista con RE2 en Go (`cleaner.go`).
- [x] Descarte de placeholders de ruido y silencio (`[AUDIO_EN_BLANCO]`, `[MÚSICA]`).
- [x] Formato inteligente por voz (`punto y aparte`, `dos puntos`, `punto 1 / viñeta / piñata`).
- [x] Normalización fonética para términos técnicos (`SQL`, `API`, `JSON`, `Docker`, `localhost`, etc.).
- [x] Inyector en cursor multiplataforma (`pbcopy` + simulación de pegado).
- [x] **Preservación del portapapeles:** Guarda el contenido anterior antes de pegar y lo restaura tras 180ms.
- [x] Suite de pruebas unitarias al 100% en `cleaner_test.go`, `history_test.go`, `injector_test.go`.

---

## ✅ Fase 3: Push-to-Talk y HUD Visual (Completada)
- [x] Detección global de atajo de teclado (`CGEvent.tapCreate`).
- [x] HUD flotante nativo con ondas sonoras animadas bioluminiscentes (`CALayer`).
- [x] Posición flotante ergonómica sobre el Dock (`y = 82`).
- [x] Efectos acústicos hápticos (`Pop` al presionar, `Tink` al procesar).

---

## ✅ Fase 4: Interfaz de Usuario Nativa en la Barra de Menú (Completada)
- [x] App nativa para macOS (`Aurae.app`) con icono `NSStatusItem` junto al reloj.
- [x] Icono oficial para la aplicación (`AppIcon.icns`) con diseño de squircle oscuro y ondas neón.
- [x] Popover SwiftUI (370x490 pt) con diseño moderno y soporte para temas claro/oscuro.
- [x] **Pestaña 1 (Historial):**
  - Lista de dictados con hora relativa y duración.
  - Buscador de texto en tiempo real.
  - Botón de copiado con feedback visual instantáneo ("Copiado").
  - Botón para vaciar historial.
- [x] **Pestaña 2 (Atajo):**
  - Selector visual de atajos (`Shift + Option`, `Option + Space`, `Control + Space`, `Control + Option`).
  - Actualización dinámica sin reiniciar la aplicación.
- [x] **Pestaña 3 (Colores):**
  - Previsualización en vivo de la píldora y ondas sonoras.
  - 5 paletas de color predefinidas (*Cyberpunk*, *Siri / Apple*, *Sunset*, *Emerald*, *Monocromo*).
- [x] Empaquetado autocontenido: `Aurae.app` incluye `aurae-engine` en `Contents/MacOS/`.

---

## 🚀 Fase 5: Distribución y Futuro (Próximos Pasos)
- [ ] Creación de Homebrew Tap para `brew install aurae`.
- [ ] GitHub Actions para release de binarios universales (`arm64` y `amd64`).
- [ ] Soporte para modelos Whisper Fine-Tuned de bajo tamaño.
