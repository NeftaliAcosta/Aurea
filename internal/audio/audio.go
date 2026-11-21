package audio

import (
	"fmt"
	"os"
	"os/exec"
	"syscall"
	"time"
)

type Recorder struct {
	cmd        *exec.Cmd
	outputPath string
	isRecording bool
}

func NewRecorder() *Recorder {
	return &Recorder{}
}

// FindAudioBackend detects available audio recorder binary
func FindAudioBackend() (string, []string, error) {
	// 1. Check for 'rec' (part of sox)
	if path, err := exec.LookPath("rec"); err == nil {
		return path, []string{"-q", "-c", "1", "-r", "16000"}, nil
	}
	// 2. Check for 'sox'
	if path, err := exec.LookPath("sox"); err == nil {
		return path, []string{"-q", "-d", "-c", "1", "-r", "16000"}, nil
	}
	// 3. Check for 'ffmpeg'
	if path, err := exec.LookPath("ffmpeg"); err == nil {
		return path, []string{"-y", "-f", "avfoundation", "-i", ":default", "-ar", "16000", "-ac", "1"}, nil
	}

	return "", nil, fmt.Errorf("no audio recorder found: please install 'sox' or 'ffmpeg'")
}

// Start begins recording to the specified WAV destination
func (r *Recorder) Start(outputPath string) error {
	if r.isRecording {
		return fmt.Errorf("recording already in progress")
	}

	bin, baseArgs, err := FindAudioBackend()
	if err != nil {
		return err
	}

	r.outputPath = outputPath
	args := append(baseArgs, outputPath)
	cmd := exec.Command(bin, args...)

	if err := cmd.Start(); err != nil {
		return fmt.Errorf("failed to start audio recording: %w", err)
	}

	r.cmd = cmd
	r.isRecording = true
	return nil
}

// Stop terminates the recording cleanly and ensures file exists
func (r *Recorder) Stop() (string, error) {
	if !r.isRecording || r.cmd == nil {
		return "", fmt.Errorf("no recording in progress")
	}

	// Send SIGINT / Interrupt to allow sox/rec to flush WAV headers properly
	if r.cmd.Process != nil {
		_ = r.cmd.Process.Signal(syscall.SIGINT)
	}

	// Wait up to 2 seconds for process to exit
	done := make(chan error, 1)
	go func() {
		done <- r.cmd.Wait()
	}()

	select {
	case <-done:
	case <-time.After(2 * time.Second):
		if r.cmd.Process != nil {
			_ = r.cmd.Process.Kill()
		}
	}

	r.isRecording = false

	// Validate output file exists and has size
	fi, err := os.Stat(r.outputPath)
	if err != nil {
		return "", fmt.Errorf("output audio file missing: %w", err)
	}
	if fi.Size() == 0 {
		return "", fmt.Errorf("recorded audio file is empty")
	}

	return r.outputPath, nil
}

func (r *Recorder) IsRecording() bool {
	return r.isRecording
}
