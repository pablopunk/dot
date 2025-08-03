package exec

import (
	"strings"
	"testing"
)

func TestNewManager(t *testing.T) {
	manager := NewManager(true, false)
	
	if !manager.dryRun {
		t.Error("Expected dryRun to be true")
	}
	
	if manager.verbose {
		t.Error("Expected verbose to be false")
	}
}

func TestExecuteCommand(t *testing.T) {
	tests := []struct {
		name      string
		command   string
		dryRun    bool
		wantError bool
	}{
		{
			name:      "dry run mode",
			command:   "echo hello",
			dryRun:    true,
			wantError: false,
		},
		{
			name:      "simple echo command",
			command:   "echo hello",
			dryRun:    false,
			wantError: false,
		},
		{
			name:      "empty command",
			command:   "",
			dryRun:    false,
			wantError: true,
		},
		{
			name:      "invalid command",
			command:   "nonexistent-command-xyz",
			dryRun:    false,
			wantError: true,
		},
	}
	
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			manager := NewManager(tt.dryRun, false)
			result := manager.ExecuteCommand(tt.command)
			
			if tt.dryRun {
				if !result.Success {
					t.Errorf("Dry run should always succeed, got success=%v", result.Success)
				}
				if !strings.Contains(result.Output, "[DRY RUN]") {
					t.Errorf("Dry run output should contain '[DRY RUN]', got: %s", result.Output)
				}
				return
			}
			
			if (result.Error != nil) != tt.wantError {
				t.Errorf("ExecuteCommand() error = %v, wantError %v", result.Error, tt.wantError)
			}
			
			if result.Success == tt.wantError {
				t.Errorf("ExecuteCommand() success = %v, expected opposite of wantError %v", result.Success, tt.wantError)
			}
			
			if result.Command != tt.command {
				t.Errorf("ExecuteCommand() command = %v, want %v", result.Command, tt.command)
			}
		})
	}
}

func TestExecuteShellCommand(t *testing.T) {
	tests := []struct {
		name    string
		command string
		dryRun  bool
		wantErr bool
	}{
		{
			name:    "echo with pipe",
			command: "echo 'hello world' | wc -w",
			dryRun:  false,
			wantErr: false,
		},
		{
			name:    "dry run shell command",
			command: "echo test && echo success",
			dryRun:  true,
			wantErr: false,
		},
		{
			name:    "invalid shell command",
			command: "exit 1",
			dryRun:  false,
			wantErr: true,
		},
	}
	
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			manager := NewManager(tt.dryRun, false)
			result := manager.ExecuteShellCommand(tt.command)
			
			if tt.dryRun {
				if !result.Success {
					t.Errorf("Dry run should always succeed")
				}
				if !strings.Contains(result.Output, "[DRY RUN]") {
					t.Errorf("Dry run output should contain '[DRY RUN]'")
				}
				return
			}
			
			if (result.Error != nil) != tt.wantErr {
				t.Errorf("ExecuteShellCommand() error = %v, wantErr %v", result.Error, tt.wantErr)
			}
		})
	}
}

func TestExecuteInstallCommand(t *testing.T) {
	manager := NewManager(true, false) // dry run
	
	result := manager.ExecuteInstallCommand("brew", "brew install git")
	
	if !result.Success {
		t.Error("Install command should succeed in dry run")
	}
	
	if !strings.Contains(result.Output, "[brew]") {
		t.Errorf("Install result should contain package manager name, got: %s", result.Output)
	}
}

func TestExecuteUninstallCommand(t *testing.T) {
	manager := NewManager(true, false) // dry run
	
	result := manager.ExecuteUninstallCommand("apt", "apt remove -y git")
	
	if !result.Success {
		t.Error("Uninstall command should succeed in dry run")
	}
	
	if !strings.Contains(result.Output, "[apt]") {
		t.Errorf("Uninstall result should contain package manager name, got: %s", result.Output)
	}
}

func TestTestCommand(t *testing.T) {
	manager := NewManager(false, false)
	
	// Test with a command that should exist
	if !manager.TestCommand("echo hello") {
		t.Error("TestCommand should return true for valid echo command")
	}
	
	// Test with a command that shouldn't exist
	if manager.TestCommand("nonexistent-command-xyz") {
		t.Error("TestCommand should return false for invalid command")
	}
}

func TestCommandExists(t *testing.T) {
	manager := NewManager(false, false)
	
	// Test with a command that should exist on most systems
	if !manager.CommandExists("echo") {
		t.Error("CommandExists should return true for echo")
	}
	
	// Test with a command that shouldn't exist
	if manager.CommandExists("nonexistent-command-xyz") {
		t.Error("CommandExists should return false for nonexistent command")
	}
}

func TestExecResultString(t *testing.T) {
	tests := []struct {
		name   string
		result ExecResult
		want   string
	}{
		{
			name:   "successful command",
			result: ExecResult{Command: "echo hello", Success: true},
			want:   "✓ echo hello",
		},
		{
			name:   "failed command with error",
			result: ExecResult{Command: "false", Success: false, Error: &ExitError{}},
			want:   "✗ false:",
		},
		{
			name:   "failed command without error",
			result: ExecResult{Command: "false", Success: false},
			want:   "✗ false",
		},
	}
	
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := tt.result.String()
			if !strings.Contains(got, tt.want) {
				t.Errorf("ExecResult.String() = %v, want to contain %v", got, tt.want)
			}
		})
	}
}

// Mock error type for testing
type ExitError struct{}

func (e *ExitError) Error() string {
	return "exit status 1"
}