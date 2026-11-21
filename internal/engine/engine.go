package engine

import (
	"bytes"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"

	"github.com/neftaliacosta/aurae/internal/cleaner"
	"github.com/neftaliacosta/aurae/internal/config"
)

type Engine struct {
	cfg        *config.Config
	whisperBin string
}

func NewEngine(cfg *config.Config) (*Engine, error) {
	bin, err := FindWhisperBin()
	if err != nil {
		return nil, err
	}
	return &Engine{
		cfg:        cfg,
		whisperBin: bin,
	}, nil
}

func FindWhisperBin() (string, error) {
	// 1. Check path
	for _, name := range []string{"whisper-cli", "whisper"} {
		if path, err := exec.LookPath(name); err == nil {
			return path, nil
		}
	}
	// 2. Common Homebrew location
	for _, path := range []string{"/opt/homebrew/bin/whisper-cli", "/usr/local/bin/whisper-cli"} {
		if _, err := os.Stat(path); err == nil {
			return path, nil
		}
	}
	return "", fmt.Errorf("whisper-cli binary not found. Please install whisper-cpp (e.g. brew install whisper-cpp)")
}

// ModelFileName returns filename like "ggml-large-v3-turbo.bin"
func ModelFileName(modelName string) string {
	name := strings.TrimPrefix(modelName, "ggml-")
	name = strings.TrimSuffix(name, ".bin")
	return fmt.Sprintf("ggml-%s.bin", name)
}

func ModelDownloadURL(modelName string) string {
	fileName := ModelFileName(modelName)
	return fmt.Sprintf("https://huggingface.co/ggerganov/whisper.cpp/resolve/main/%s", fileName)
}

// EnsureModel checks if model is downloaded; if not, downloads with progress reporting
func (e *Engine) EnsureModel() (string, error) {
	if err := os.MkdirAll(e.cfg.ModelsDir, 0755); err != nil {
		return "", err
	}

	modelFile := ModelFileName(e.cfg.Model)
	targetPath := filepath.Join(e.cfg.ModelsDir, modelFile)

	if fi, err := os.Stat(targetPath); err == nil && fi.Size() > 1024*1024 {
		return targetPath, nil
	}

	url := ModelDownloadURL(e.cfg.Model)
	fmt.Printf("📦 Descargando modelo %s (%s)...\n", e.cfg.Model, url)

	resp, err := http.Get(url)
	if err != nil {
		return "", fmt.Errorf("error al conectar con HuggingFace: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("descarga falló con status HTTP %d", resp.StatusCode)
	}

	tmpFile := targetPath + ".downloading"
	out, err := os.Create(tmpFile)
	if err != nil {
		return "", err
	}

	total := resp.ContentLength
	var downloaded int64
	buf := make([]byte, 32*1024)

	for {
		nr, er := resp.Body.Read(buf)
		if nr > 0 {
			nw, ew := out.Write(buf[0:nr])
			if nw < 0 || nr != nw {
				out.Close()
				return "", ew
			}
			downloaded += int64(nw)
			if total > 0 {
				percent := float64(downloaded) / float64(total) * 100.0
				fmt.Printf("\r⬇️  Progreso: %.1f%% (%d / %d MB)", percent, downloaded/(1024*1024), total/(1024*1024))
			}
		}
		if er != nil {
			if er == io.EOF {
				break
			}
			out.Close()
			return "", er
		}
	}
	out.Close()
	fmt.Println("\n✅ Modelo descargado exitosamente.")

	if err := os.Rename(tmpFile, targetPath); err != nil {
		return "", err
	}

	return targetPath, nil
}

// Transcribe processes the audio file and returns clean text
func (e *Engine) Transcribe(audioPath string) (string, error) {
	modelPath, err := e.EnsureModel()
	if err != nil {
		return "", fmt.Errorf("modelo no disponible: %w", err)
	}

	prompt := "Transcripción profesional de tecnología, desarrollo y programación: API, SQL, JSON, Docker, endpoint, localhost, despliegue, pull request, GitHub, Gmail, comandos, listas."
	if e.cfg.Language != "es" {
		prompt = "Clean professional technical transcription: API, SQL, JSON, Docker, endpoint, localhost, deployment, pull request, GitHub, Gmail."
	}

	args := []string{
		"-m", modelPath,
		"-f", audioPath,
		"-l", e.cfg.Language,
		"-t", "8", // Use 8 threads on Apple Silicon
		"-bs", "1", // Greedy decoding (3x faster than beam search)
		"-bo", "1",
		"--prompt", prompt,
	}

	cmd := exec.Command(e.whisperBin, args...)
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	if err := cmd.Run(); err != nil {
		return "", fmt.Errorf("error ejecutando whisper: %w\nDetalle: %s", err, stderr.String())
	}

	rawText := stdout.String()

	// Parse lines and detect long pauses between segments (>= 1.2s -> \n\n)
	timestampRegex := regexp.MustCompile(`^\[(\d{2}:\d{2}:\d{2}\.\d{3})\s+-->\s+(\d{2}:\d{2}:\d{2}\.\d{3})\]\s*(.*)$`)
	lines := strings.Split(rawText, "\n")

	var sb strings.Builder
	var prevEndMs int64

	for _, l := range lines {
		trimmed := strings.TrimSpace(l)
		if trimmed == "" || strings.HasPrefix(trimmed, "whisper_") || strings.HasPrefix(trimmed, "system_info:") {
			continue
		}

		if m := timestampRegex.FindStringSubmatch(trimmed); len(m) == 4 {
			startMs := parseTimestamp(m[1])
			endMs := parseTimestamp(m[2])
			segText := strings.TrimSpace(m[3])

			if segText == "" {
				continue
			}

			// If silence gap between segments >= 1200ms (1.2s), insert paragraph break
			if prevEndMs > 0 && (startMs-prevEndMs) >= 1200 {
				sb.WriteString(".\n\n")
			} else if sb.Len() > 0 {
				sb.WriteString(" ")
			}
			sb.WriteString(segText)
			prevEndMs = endMs
		} else {
			// Plain line without timestamps
			if sb.Len() > 0 {
				sb.WriteString(" ")
			}
			sb.WriteString(trimmed)
		}
	}

	result := sb.String()

	if e.cfg.RemoveFillers {
		result = cleaner.CleanText(result)
	}

	return result, nil
}

// parseTimestamp converts "00:01:23.450" into total milliseconds
func parseTimestamp(ts string) int64 {
	var h, m, s, ms int64
	_, _ = fmt.Sscanf(ts, "%d:%d:%d.%d", &h, &m, &s, &ms)
	return (h*3600+m*60+s)*1000 + ms
}
