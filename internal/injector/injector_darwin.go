//go:build darwin

package injector

/*
#cgo LDFLAGS: -framework ApplicationServices
#include <ApplicationServices/ApplicationServices.h>
#include <unistd.h>

static void postCmdV() {
    CGEventSourceRef src = CGEventSourceCreate(kCGEventSourceStateHIDSystemState);

    // Left Command keycode: 55, 'V' keycode: 9
    CGEventRef cmdDown = CGEventCreateKeyboardEvent(src, (CGKeyCode)55, true);
    CGEventRef vDown = CGEventCreateKeyboardEvent(src, (CGKeyCode)9, true);
    CGEventSetFlags(vDown, kCGEventFlagMaskCommand);

    CGEventRef vUp = CGEventCreateKeyboardEvent(src, (CGKeyCode)9, false);
    CGEventSetFlags(vUp, kCGEventFlagMaskCommand);
    CGEventRef cmdUp = CGEventCreateKeyboardEvent(src, (CGKeyCode)55, false);

    // Post complete Command+V sequence directly to the login session event tap (1)
    CGEventPost(kCGSessionEventTap, cmdDown);
    usleep(15000); // 15ms
    CGEventPost(kCGSessionEventTap, vDown);
    usleep(35000); // 35ms hold duration
    CGEventPost(kCGSessionEventTap, vUp);
    usleep(15000); // 15ms
    CGEventPost(kCGSessionEventTap, cmdUp);

    CFRelease(cmdDown);
    CFRelease(vDown);
    CFRelease(vUp);
    CFRelease(cmdUp);
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

	// 3. Small buffer to ensure macOS pasteboard server is fully synchronized
	time.Sleep(100 * time.Millisecond)

	// 4. Simulate complete Cmd+V sequence at session level
	C.postCmdV()

	// 5. Allow target app (Chrome, Safari, Slack, Notion) ample time (700ms) to read over IPC, then restore original clipboard
	time.Sleep(700 * time.Millisecond)
	if hasOld && oldContent != "" && oldContent != text {
		_ = d.CopyOnly(oldContent)
	}

	return nil
}
