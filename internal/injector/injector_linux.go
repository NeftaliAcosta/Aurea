//go:build linux

package injector

import (
	"fmt"
	"os/exec"
	"strings"
	"time"
)

type LinuxInjector struct{}

func init() {
	Default = &LinuxInjector{}
}

func (l *LinuxInjector) readClipboard() (string, bool) {
	if _, err := exec.LookPath("wl-paste"); err == nil {
		out, err := exec.Command("wl-paste").Output()
		if err == nil {
			return string(out), true
		}
	}
	if _, err := exec.LookPath("xclip"); err == nil {
		out, err := exec.Command("xclip", "-o", "-selection", "clipboard").Output()
		if err == nil {
			return string(out), true
		}
	}
	return "", false
}

func (l *LinuxInjector) CopyOnly(text string) error {
	if _, err := exec.LookPath("wl-copy"); err == nil {
		cmd := exec.Command("wl-copy")
		cmd.Stdin = strings.NewReader(text)
		return cmd.Run()
	}
	if _, err := exec.LookPath("xclip"); err == nil {
		cmd := exec.Command("xclip", "-selection", "clipboard")
		cmd.Stdin = strings.NewReader(text)
		return cmd.Run()
	}
	return fmt.Errorf("neither wl-copy nor xclip found on system")
}

func (l *LinuxInjector) Inject(text string) error {
	if text == "" {
		return nil
	}

	oldContent, hasOld := l.readClipboard()

	if err := l.CopyOnly(text); err != nil {
		return err
	}

	time.Sleep(60 * time.Millisecond)

	var pasteErr error
	if _, err := exec.LookPath("ydotool"); err == nil {
		pasteErr = exec.Command("ydotool", "key", "29:1", "47:1", "47:0", "29:0").Run()
	} else if _, err := exec.LookPath("xdotool"); err == nil {
		pasteErr = exec.Command("xdotool", "key", "--clearmodifiers", "ctrl+v").Run()
	} else {
		pasteErr = fmt.Errorf("neither ydotool nor xdotool found to simulate paste")
	}

	time.Sleep(180 * time.Millisecond)
	if hasOld && oldContent != "" {
		_ = l.CopyOnly(oldContent)
	}

	return pasteErr
}
