package exec

import (
	"fmt"
	"os"
	"os/exec"
	"strings"
)

type Manager struct {
	dryRun  bool
	verbose bool
}

// ProgressCallback is called when interactive commands need UI updates
type ProgressCallback interface {
	PauseForInteraction(message string)
	ResumeAfterInteraction()
}

func NewManager(dryRun, verbose bool) *Manager {
	return &Manager{
		dryRun:  dryRun,
		verbose: verbose,
	}
}

type ExecResult struct {
	Command string
	Success bool
	Output  string
	Error   error
}

func (m *Manager) ExecuteCommand(command string) ExecResult {

	if m.dryRun {
		return ExecResult{
			Command: command,
			Success: true,
			Output:  fmt.Sprintf("[DRY RUN] Would execute: %s", command),
		}
	}

	// Parse command and arguments
	parts := strings.Fields(command)
	if len(parts) == 0 {
		return ExecResult{
			Command: command,
			Success: false,
			Error:   fmt.Errorf("empty command"),
		}
	}

	cmd := exec.Command(parts[0], parts[1:]...)
	cmd.Env = os.Environ()

	output, err := cmd.CombinedOutput()
	outputStr := strings.TrimSpace(string(output))

	success := err == nil

	return ExecResult{
		Command: command,
		Success: success,
		Output:  outputStr,
		Error:   err,
	}
}

func (m *Manager) ExecuteShellCommand(command string) ExecResult {
	return m.ExecuteShellCommandWithProgress(command, nil)
}

func (m *Manager) ExecuteShellCommandWithProgress(command string, progress ProgressCallback) ExecResult {

	if m.dryRun {
		return ExecResult{
			Command: command,
			Success: true,
			Output:  fmt.Sprintf("[DRY RUN] Would execute shell command: %s", command),
		}
	}

	// Check if command likely requires interaction (contains sudo, su, or other interactive commands)
	requiresInteraction := strings.Contains(command, "sudo") ||
		strings.Contains(command, " su ") ||
		strings.Contains(command, "passwd") ||
		strings.Contains(command, "ssh-keygen")

	// Use shell to execute command
	var cmd *exec.Cmd
	if isWindows() {
		cmd = exec.Command("cmd", "/C", command)
	} else {
		cmd = exec.Command("sh", "-c", command)
	}

	cmd.Env = os.Environ()

	var output []byte
	var err error

	if requiresInteraction {
		// Pause progress indicator and notify user
		if progress != nil {
			progress.PauseForInteraction("requires input (enter password if prompted)")
		}

		// For interactive commands, connect to terminal directly
		cmd.Stdin = os.Stdin
		cmd.Stdout = os.Stdout
		cmd.Stderr = os.Stderr
		err = cmd.Run()
		output = []byte{} // No output to capture for interactive commands

		// Resume progress indicator
		if progress != nil {
			progress.ResumeAfterInteraction()
		}
	} else {
		// For non-interactive commands, capture output
		output, err = cmd.CombinedOutput()

		// In verbose mode, display the output after execution
		if m.verbose && len(output) > 0 {
			// Pause progress indicator for output display
			if progress != nil {
				progress.PauseForInteraction("showing command output")
			}

			fmt.Printf("   Command output:\n")
			// Indent the output for better readability
			for _, line := range strings.Split(strings.TrimSpace(string(output)), "\n") {
				if line != "" {
					fmt.Printf("   │ %s\n", line)
				}
			}

			// Resume progress indicator
			if progress != nil {
				progress.ResumeAfterInteraction()
			}
		}
	}

	outputStr := strings.TrimSpace(string(output))
	success := err == nil

	return ExecResult{
		Command: command,
		Success: success,
		Output:  outputStr,
		Error:   err,
	}
}

func (m *Manager) ExecuteInstallCommand(packageManager, command string) ExecResult {

	result := m.ExecuteShellCommand(command)

	// Enhance result with package manager info
	if result.Success {
		result.Output = fmt.Sprintf("[%s] %s", packageManager, result.Output)
	} else {
		if result.Error != nil {
			result.Error = fmt.Errorf("install via %s failed: %w", packageManager, result.Error)
		}
	}

	return result
}

func (m *Manager) ExecuteUninstallCommand(packageManager, command string) ExecResult {

	result := m.ExecuteShellCommand(command)

	// Enhance result with package manager info
	if result.Success {
		result.Output = fmt.Sprintf("[%s] %s", packageManager, result.Output)
	} else {
		if result.Error != nil {
			result.Error = fmt.Errorf("uninstall via %s failed: %w", packageManager, result.Error)
		}
	}

	return result
}

func (m *Manager) TestCommand(command string) bool {
	parts := strings.Fields(command)
	if len(parts) == 0 {
		return false
	}

	cmd := exec.Command(parts[0], parts[1:]...)
	err := cmd.Run()
	return err == nil
}

func (m *Manager) CommandExists(command string) bool {
	_, err := exec.LookPath(command)
	return err == nil
}

func isWindows() bool {
	return os.Getenv("OS") == "Windows_NT"
}

func (r *ExecResult) String() string {
	if r.Success {
		return fmt.Sprintf("✓ %s", r.Command)
	} else {
		if r.Error != nil {
			return fmt.Sprintf("✗ %s: %v", r.Command, r.Error)
		} else {
			return fmt.Sprintf("✗ %s", r.Command)
		}
	}
}
