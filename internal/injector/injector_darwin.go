//go:build darwin

package injector

/*
#cgo LDFLAGS: -framework ApplicationServices
#include <ApplicationServices/ApplicationServices.h>

static void postCmdV() {
    CGEventSourceRef src = CGEventSourceCreate(kCGEventSourceStateHIDSystemState);
    CGEventRef vDown = CGEventCreateKeyboardEvent(src, (CGKeyCode)9, true);
    CGEventSetFlags(vDown, kCGEventFlagMaskCommand);
    CGEventRef vUp = CGEventCreateKeyboardEvent(src, (CGKeyCode)9, false);

    CGEventPost(kCGHIDEventTap, vDown);
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

	// 3. Small delay to ensure clipboard buffer is populated
	time.Sleep(50 * time.Millisecond)

	// 4. Simulate Cmd+V directly at CoreGraphics HID level (replaces osascript/System Events)
	C.postCmdV()

	// 5. Allow target application to consume the clipboard event, then restore original content
	time.Sleep(180 * time.Millisecond)
	if hasOld && oldContent != "" {
		_ = d.CopyOnly(oldContent)
	}

	return nil
}
