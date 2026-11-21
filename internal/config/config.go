package config

import (
	"encoding/json"
	"os"
	"path/filepath"
)

type Config struct {
	Model          string   `json:"model"`           // e.g. "small" or "large-v3-turbo"
	Language       string   `json:"language"`        // e.g. "es"
	RemoveFillers  bool     `json:"remove_fillers"`  // true
	AutoPaste      bool     `json:"auto_paste"`      // true
	Hotkey         string   `json:"hotkey"`          // e.g. "shift+option"
	WaveformColors []string `json:"waveform_colors"` // hex colors for 4 waveform bars
	ModelsDir      string   `json:"models_dir"`      // path to models directory
}

func DefaultConfig() *Config {
	home, _ := os.UserHomeDir()
	modelsDir := filepath.Join(home, ".aurae", "models")
	return &Config{
		Model:         "small",
		Language:      "es",
		RemoveFillers: true,
		AutoPaste:     true,
		Hotkey:        "shift+option",
		WaveformColors: []string{
			"#A855F7", // Purple
			"#EC4899", // Pink
			"#3B82F6", // Blue
			"#06B6D4", // Cyan
		},
		ModelsDir: modelsDir,
	}
}

func ConfigDir() string {
	home, _ := os.UserHomeDir()
	return filepath.Join(home, ".aurae")
}

func ConfigPath() string {
	return filepath.Join(ConfigDir(), "config.json")
}

func HistoryPath() string {
	return filepath.Join(ConfigDir(), "history.jsonl")
}

func LoadConfig() (*Config, error) {
	cfg := DefaultConfig()
	path := ConfigPath()

	data, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			_ = SaveConfig(cfg)
			return cfg, nil
		}
		return nil, err
	}

	if err := json.Unmarshal(data, cfg); err != nil {
		return cfg, nil
	}

	// Ensure colors has at least 4 items
	if len(cfg.WaveformColors) < 4 {
		cfg.WaveformColors = DefaultConfig().WaveformColors
	}

	return cfg, nil
}

func SaveConfig(cfg *Config) error {
	path := ConfigPath()
	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return err
	}

	data, err := json.MarshalIndent(cfg, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(path, data, 0644)
}
