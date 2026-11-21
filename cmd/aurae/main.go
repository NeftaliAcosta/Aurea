package main

import (
	"bufio"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"github.com/neftaliacosta/aurae/internal/audio"
	"github.com/neftaliacosta/aurae/internal/config"
	"github.com/neftaliacosta/aurae/internal/engine"
	"github.com/neftaliacosta/aurae/internal/history"
	"github.com/neftaliacosta/aurae/internal/injector"
)

const Version = "0.1.0"

func printHelp() {
	fmt.Printf("Aurae v%s — Dictado inteligente local y gratuito\n\n", Version)
	fmt.Println("Uso: aurae <comando> [opciones]")
	fmt.Println("\nComandos disponibles:")
	fmt.Println("  listen       Modo segundo plano (mantén Shift + Option para hablar)")
	fmt.Println("  record       Graba voz al pulsar Enter, transcribe y pega en el cursor")
	fmt.Println("  file <path>  Transcribe un archivo de audio existente")
	fmt.Println("  doctor       Verifica el entorno del sistema, micrófono y dependencias")
	fmt.Println("  download     Descarga el modelo configurado (por defecto large-v3-turbo)")
	fmt.Println("  config       Muestra la configuración actual")
	fmt.Println("  version      Muestra la versión de Aurae")
	fmt.Println("\nOpciones globales:")
	fmt.Println("  --model <name>    large-v3-turbo, small, base")
	fmt.Println("  --no-paste        Solo imprime el texto, no lo pega")
	fmt.Println("  --raw             No filtra muletillas")
}

func parseFlags(args []string, cfg *config.Config) []string {
	var filtered []string
	for i := 0; i < len(args); i++ {
		switch args[i] {
		case "--no-paste":
			cfg.AutoPaste = false
		case "--raw":
			cfg.RemoveFillers = false
		case "--model":
			if i+1 < len(args) {
				cfg.Model = args[i+1]
				i++
			}
		default:
			filtered = append(filtered, args[i])
		}
	}
	return filtered
}

func runDownload(cfg *config.Config) {
	eng, err := engine.NewEngine(cfg)
	if err != nil {
		fmt.Printf("❌ Error: %v\n", err)
		return
	}
	path, err := eng.EnsureModel()
	if err != nil {
		fmt.Printf("❌ Error descargando modelo: %v\n", err)
		return
	}
	fmt.Printf("✅ Modelo listo en: %s\n", path)
}

func main() {
	cfg, err := config.LoadConfig()
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error cargando configuración: %v\n", err)
		os.Exit(1)
	}

	filteredArgs := parseFlags(os.Args[1:], cfg)
	if len(filteredArgs) == 0 {
		printHelp()
		return
	}

	switch filteredArgs[0] {
	case "version", "-v", "--version":
		fmt.Printf("Aurae v%s\n", Version)

	case "config":
		fmt.Printf("Configuración actual (%s):\n", config.ConfigPath())
		fmt.Printf("  Modelo:           %s\n", cfg.Model)
		fmt.Printf("  Idioma:           %s\n", cfg.Language)
		fmt.Printf("  Filtrar muletillas: %v\n", cfg.RemoveFillers)
		fmt.Printf("  Auto-pegar texto:   %v\n", cfg.AutoPaste)
		fmt.Printf("  Directorio modelos: %s\n", cfg.ModelsDir)

	case "doctor":
		runDoctor(cfg)

	case "download":
		runDownload(cfg)

	case "file":
		if len(filteredArgs) < 2 {
			fmt.Println("Uso: aurae file <ruta-del-audio.wav>")
			return
		}
		runFile(cfg, filteredArgs[1])

	case "transcribe":
		if len(filteredArgs) < 2 {
			return
		}
		eng, err := engine.NewEngine(cfg)
		if err != nil {
			return
		}
		start := time.Now()
		text, err := eng.Transcribe(filteredArgs[1])
		if err != nil || strings.TrimSpace(text) == "" {
			return
		}
		_ = history.Append(text, time.Since(start).Seconds())
		fmt.Print(text)
		return

	case "history":
		runHistory(filteredArgs[1:])

	case "listen":
		runListen(cfg)

	case "record":
		runInteractiveRecord(cfg)

	default:
		fmt.Printf("Comando desconocido: %s\n", filteredArgs[0])
		printHelp()
	}
}

func runDoctor(cfg *config.Config) {
	fmt.Println("🩺 Verificando entorno de Aurae...")

	// 1. Whisper binary
	whisperBin, err := engine.FindWhisperBin()
	if err != nil {
		fmt.Println("  ❌ whisper-cli: NO encontrado (Instala con: brew install whisper-cpp)")
	} else {
		fmt.Printf("  ✅ whisper-cli: %s\n", whisperBin)
	}

	// 2. Audio backend
	audioBin, _, err := audio.FindAudioBackend()
	if err != nil {
		fmt.Println("  ❌ Audio backend: NO encontrado (Instala con: brew install sox)")
	} else {
		fmt.Printf("  ✅ Audio backend: %s\n", audioBin)
	}

	// 3. Model
	modelFile := engine.ModelFileName(cfg.Model)
	modelPath := filepath.Join(cfg.ModelsDir, modelFile)
	if fi, err := os.Stat(modelPath); err == nil && fi.Size() > 0 {
		fmt.Printf("  ✅ Modelo %s: Presente (%.1f MB)\n", cfg.Model, float64(fi.Size())/(1024*1024))
	} else {
		fmt.Printf("  ⚠️  Modelo %s: No descargado aún (se descargará automáticamente en primer uso)\n", cfg.Model)
	}

	// 4. Injector
	if injector.Default != nil {
		fmt.Println("  ✅ Inyector de cursor: Soportado para este sistema operativo")
	} else {
		fmt.Println("  ⚠️  Inyector de cursor: Sin soporte directo para este OS")
	}

	fmt.Println("\nDiagnóstico finalizado.")
}

func runFile(cfg *config.Config, audioPath string) {
	eng, err := engine.NewEngine(cfg)
	if err != nil {
		fmt.Printf("❌ Error: %v\n", err)
		return
	}

	start := time.Now()
	text, err := eng.Transcribe(audioPath)
	if err != nil {
		fmt.Printf("❌ Error transcribiendo: %v\n", err)
		return
	}
	elapsed := time.Since(start)

	if strings.TrimSpace(text) == "" {
		fmt.Println("\n(Silencio o audio en blanco descartado — nada que pegar)")
		return
	}

	_ = history.Append(text, elapsed.Seconds())

	fmt.Printf("\n✨ Transcripción (en %.2fs):\n%s\n", elapsed.Seconds(), text)

	if cfg.AutoPaste && injector.Default != nil {
		if err := injector.Default.Inject(text); err != nil {
			fmt.Printf("⚠️  No se pudo pegar en el cursor: %v\n", err)
		} else {
			fmt.Println("📋 Pegado en la aplicación activa.")
		}
	}
}

func runInteractiveRecord(cfg *config.Config) {
	eng, err := engine.NewEngine(cfg)
	if err != nil {
		fmt.Printf("❌ Error: %v\n", err)
		return
	}

	// Ensure model is ready before recording
	if _, err := eng.EnsureModel(); err != nil {
		fmt.Printf("❌ Error preparando modelo: %v\n", err)
		return
	}

	tmpDir := os.TempDir()
	wavFile := filepath.Join(tmpDir, fmt.Sprintf("aurae_%d.wav", time.Now().UnixNano()))
	defer os.Remove(wavFile)

	rec := audio.NewRecorder()
	reader := bufio.NewReader(os.Stdin)

	fmt.Println("\n🎙️  Aurae listo.")
	fmt.Print("👉 Presiona [ENTER] para EMPEZAR a hablar...")
	_, _ = reader.ReadString('\n')

	if err := rec.Start(wavFile); err != nil {
		fmt.Printf("❌ Error iniciando grabación: %v\n", err)
		return
	}

	fmt.Println("🔴 Grabando... (habla con naturalidad)")
	fmt.Print("👉 Presiona [ENTER] para DETENER y transcribir...")
	_, _ = reader.ReadString('\n')

	savedPath, err := rec.Stop()
	if err != nil {
		fmt.Printf("❌ Error deteniendo grabación: %v\n", err)
		return
	}

	fmt.Print("⏳ Procesando audio...")
	start := time.Now()
	text, err := eng.Transcribe(savedPath)
	if err != nil {
		fmt.Printf("\n❌ Error transcribiendo: %v\n", err)
		return
	}
	elapsed := time.Since(start)

	if strings.TrimSpace(text) == "" {
		fmt.Println("\n(No se detectó voz)")
		return
	}

	_ = history.Append(text, elapsed.Seconds())

	fmt.Printf("\r✨ Transcrito en %.2fs:\n\"%s\"\n", elapsed.Seconds(), text)

	if cfg.AutoPaste && injector.Default != nil {
		// Small delay so user can focus wherever they want if needed
		time.Sleep(100 * time.Millisecond)
		if err := injector.Default.Inject(text); err != nil {
			fmt.Printf("⚠️  No se pudo pegar: %v (copiado al portapapeles)\n", err)
		} else {
			fmt.Println("🚀 Pegado en cursor activo.")
		}
	}
}

func runListen(cfg *config.Config) {
	// Locate listener binary
	execPath, err := os.Executable()
	if err != nil {
		execPath = "bin/aurae"
	}
	dir := filepath.Dir(execPath)
	listenerBin := filepath.Join(dir, "aurae-listener")

	if _, err := os.Stat(listenerBin); os.IsNotExist(err) {
		// Fallback check current directory bin
		listenerBin = "bin/aurae-listener"
		if _, err := os.Stat(listenerBin); os.IsNotExist(err) {
			listenerBin = "/usr/local/bin/aurae-listener"
		}
	}

	if _, err := os.Stat(listenerBin); os.IsNotExist(err) {
		fmt.Println("⚠️  Compilando listener nativo de macOS...")
		cmd := exec.Command("swiftc", "-O", "-o", "bin/aurae-listener", "cmd/listener/main.swift")
		if err := cmd.Run(); err != nil {
			fmt.Fprintf(os.Stderr, "❌ Error compilando listener: %v\n", err)
			return
		}
		listenerBin = "bin/aurae-listener"
	}

	cmd := exec.Command(listenerBin)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Stdin = os.Stdin

	if err := cmd.Run(); err != nil {
		fmt.Fprintf(os.Stderr, "Listener finalizado: %v\n", err)
	}
}

func runHistory(args []string) {
	if len(args) > 0 && args[0] == "clear" {
		if err := history.Clear(); err != nil {
			fmt.Printf("❌ Error borrando historial: %v\n", err)
		} else {
			fmt.Println("🧹 Historial borrado.")
		}
		return
	}

	limit := 10
	entries, err := history.GetRecent(limit)
	if err != nil {
		fmt.Printf("❌ Error leyendo historial: %v\n", err)
		return
	}

	if len(entries) == 0 {
		fmt.Println("📜 No hay dictados en el historial aún.")
		return
	}

	fmt.Printf("📜 Últimos %d dictados:\n\n", len(entries))
	for i, e := range entries {
		fmt.Printf("[%d] %s (%.2fs):\n%s\n\n", i+1, e.Timestamp.Local().Format("02/01 15:04"), e.DurationSec, e.Text)
	}
}

