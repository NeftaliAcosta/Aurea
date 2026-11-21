//go:build darwin

package injector

import (
	"fmt"
	"os/exec"
	"strings"
	"time"
)

type DarwinInjector struct{}

func init() {
	Default = &DarwinInjector{}
}

func (d *DarwinInjector) readClipboard() (string, bool) {
	cmd := exec.Command("pbpaste")
	out, err := cmd.Output()
	if err != nil {
		return "", false
	}
	return string(out), true
}

func (d *DarwinInjector) CopyOnly(text string) error {
	cmd := exec.Command("pbcopy")
	cmd.Stdin = strings.NewReader(text)
	return cmd.Run()
}

func (d *DarwinInjector) Inject(text string) error {
	if text == "" {
		return nil
	}

	// 1. Capture current clipboard state to restore later
	oldContent, hasOld := d.readClipboard()

	// 2. Copy new transcribed text to clipboard
	if err := d.CopyOnly(text); err != nil {
		return fmt.Errorf("pbcopy error: %w", err)
	}

	// 3. Small delay to ensure clipboard buffer is populated
	time.Sleep(60 * time.Millisecond)

	// 4. Simulate Cmd+V using AppleScript
	script := `tell application "System Events" to keystroke "v" using command down`
	cmd := exec.Command("osascript", "-e", script)
	pasteErr := cmd.Run()

	// 5. Allow target application to consume the clipboard event, then restore original content
	time.Sleep(180 * time.Millisecond)
	if hasOld && oldContent != "" {
		_ = d.CopyOnly(oldContent)
	}

	if pasteErr != nil {
		return fmt.Errorf("simulate paste error: %w", pasteErr)
	}

	return nil
}
