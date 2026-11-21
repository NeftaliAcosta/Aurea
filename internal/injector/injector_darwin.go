//go:build darwin

package injector

/*
#cgo LDFLAGS: -framework ApplicationServices
#include <ApplicationServices/ApplicationServices.h>
#include <unistd.h>

static void postCmdV() {
    CGEventSourceRef src = CGEventSourceCreate(kCGEventSourceStateHIDSystemState);
    CGEventRef vDown = CGEventCreateKeyboardEvent(src, (CGKeyCode)9, true);
    CGEventSetFlags(vDown, kCGEventFlagMaskCommand);
    CGEventRef vUp = CGEventCreateKeyboardEvent(src, (CGKeyCode)9, false);
    CGEventSetFlags(vUp, kCGEventFlagMaskCommand);

    CGEventPost(kCGAnnotatedSessionEventTap, vDown);
    CGEventPost(kCGHIDEventTap, vDown);
    usleep(25000); // 25ms key press hold duration so OS event loop dispatches the keystroke
    CGEventPost(kCGAnnotatedSessionEventTap, vUp);
    CGEventPost(kCGHIDEventTap, vUp);

    CFRelease(vDown);
    CFRelease(vUp);
    CFRelease(src);
}
*/
import "C"

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

	// 3. Buffer delay to ensure pasteboard server has flushed the new text
	time.Sleep(80 * time.Millisecond)

	// 4. Simulate Cmd+V directly at CoreGraphics HID and Session level
	C.postCmdV()

	// 5. Allow target application (Chrome, Safari, VS Code) to consume the clipboard event, then restore original content
	time.Sleep(450 * time.Millisecond)
	if hasOld && oldContent != "" {
		_ = d.CopyOnly(oldContent)
	}

	return nil
}
