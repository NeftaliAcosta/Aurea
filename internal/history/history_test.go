package history

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/neftaliacosta/aurae/internal/config"
)

func TestHistoryAppendAndGet(t *testing.T) {
	// Use temporary history file for test
	tmpDir := t.TempDir()
	origHome := os.Getenv("HOME")
	defer os.Setenv("HOME", origHome)
	os.Setenv("HOME", tmpDir)

	_ = Append("Primera prueba", 0.5)
	_ = Append("Segunda prueba", 1.2)

	entries, err := GetRecent(10)
	if err != nil {
		t.Fatalf("Unexpected error: %v", err)
	}

	if len(entries) != 2 {
		t.Fatalf("Expected 2 entries, got %d", len(entries))
	}

	// Newest first
	if entries[0].Text != "Segunda prueba" {
		t.Errorf("Expected newest 'Segunda prueba', got %q", entries[0].Text)
	}
	if entries[1].Text != "Primera prueba" {
		t.Errorf("Expected 'Primera prueba', got %q", entries[1].Text)
	}

	_ = Clear()
	entriesAfter, _ := GetRecent(10)
	if len(entriesAfter) != 0 {
		t.Errorf("Expected 0 entries after clear, got %d", len(entriesAfter))
	}
	_ = filepath.Join(config.ConfigDir())
}
