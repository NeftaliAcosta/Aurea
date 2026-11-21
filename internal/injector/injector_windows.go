//go:build windows

package injector

import (
	"fmt"
	"os/exec"
	"strings"
	"time"
)

type WindowsInjector struct{}

func init() {
	Default = &WindowsInjector{}
}

func (w *WindowsInjector) readClipboard() (string, bool) {
	cmd := exec.Command("powershell", "-NoProfile", "-Command", "Get-Clipboard")
	out, err := cmd.Output()
	if err != nil {
		return "", false
	}
	return strings.TrimRight(string(out), "\r\n"), true
}

func (w *WindowsInjector) CopyOnly(text string) error {
	cmd := exec.Command("powershell", "-NoProfile", "-Command", "Set-Clipboard", "-Value", text)
	return cmd.Run()
}

func (w *WindowsInjector) Inject(text string) error {
	if text == "" {
		return nil
	}

	oldContent, hasOld := w.readClipboard()

	if err := w.CopyOnly(text); err != nil {
		return fmt.Errorf("windows clipboard error: %w", err)
	}

	time.Sleep(60 * time.Millisecond)

	// Send Ctrl+V using PowerShell WScript.Shell SendKeys
	script := `Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.SendKeys]::SendWait('^v')`
	cmd := exec.Command("powershell", "-NoProfile", "-Command", script)
	pasteErr := cmd.Run()

	time.Sleep(180 * time.Millisecond)
	if hasOld && oldContent != "" {
		_ = w.CopyOnly(oldContent)
	}

	return pasteErr
}
