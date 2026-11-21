package history

import (
	"bufio"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/neftaliacosta/aurae/internal/config"
)

type Entry struct {
	ID          string    `json:"id"`
	Timestamp   time.Time `json:"timestamp"`
	Text        string    `json:"text"`
	DurationSec float64   `json:"duration_sec"`
}

func newID() string {
	b := make([]byte, 8)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}

func Append(text string, durationSec float64) error {
	clean := strings.TrimSpace(text)
	if clean == "" {
		return nil
	}

	path := config.HistoryPath()
	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return err
	}

	entry := Entry{
		ID:          newID(),
		Timestamp:   time.Now().UTC(),
		Text:        clean,
		DurationSec: durationSec,
	}

	data, err := json.Marshal(entry)
	if err != nil {
		return err
	}

	f, err := os.OpenFile(path, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
	if err != nil {
		return err
	}
	defer f.Close()

	_, err = f.Write(append(data, '\n'))
	return err
}

func GetRecent(limit int) ([]Entry, error) {
	path := config.HistoryPath()
	f, err := os.Open(path)
	if err != nil {
		if os.IsNotExist(err) {
			return []Entry{}, nil
		}
		return nil, err
	}
	defer f.Close()

	var entries []Entry
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" {
			continue
		}
		var e Entry
		if err := json.Unmarshal([]byte(line), &e); err == nil {
			entries = append(entries, e)
		}
	}

	// Reverse to have newest first
	n := len(entries)
	reversed := make([]Entry, n)
	for i := 0; i < n; i++ {
		reversed[i] = entries[n-1-i]
	}

	if limit > 0 && len(reversed) > limit {
		return reversed[:limit], nil
	}
	return reversed, nil
}

func Clear() error {
	path := config.HistoryPath()
	return os.Remove(path)
}
