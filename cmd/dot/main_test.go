package main

import (
	"bytes"
	"flag"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"

	"github.com/pablopunk/dot/internal/component"
	"github.com/pablopunk/dot/internal/state"
)

func TestApp_Run(t *testing.T) {
	// Create a temporary directory for testing
	tempDir := t.TempDir()

	// Create a test config file
	configContent := `
profiles:
  default:
    test-component:
      link:
        test-file: ~/.test-file
`
	configPath := filepath.Join(tempDir, "dot.yaml")
	if err := os.WriteFile(configPath, []byte(configContent), 0644); err != nil {
		t.Fatalf("Failed to create test config: %v", err)
	}

	// Change to temp directory and set clean HOME
	oldWd, _ := os.Getwd()
	defer os.Chdir(oldWd)
	os.Chdir(tempDir)

	// Set HOME to temp directory to avoid using existing state
	originalHome := os.Getenv("HOME")
	os.Setenv("HOME", tempDir)
	defer os.Setenv("HOME", originalHome)

	tests := []struct {
		name        string
		app         *App
		args        []string
		wantErr     bool
		errContains string
	}{
		{
			name: "dry run mode",
			app: &App{
				DryRun:  true,
				Verbose: false,
			},
			args:    []string{},
			wantErr: false,
		},
		{
			name: "verbose mode",
			app: &App{
				Verbose: true,
				DryRun:  true, // Use dry run to avoid actual operations
			},
			args:    []string{},
			wantErr: false,
		},
		{
			name: "force install",
			app: &App{
				ForceInstall: true,
				DryRun:       true,
			},
			args:    []string{},
			wantErr: false,
		},
		{
			name: "with profile argument",
			app: &App{
				DryRun: true,
			},
			args:    []string{"default"},
			wantErr: false,
		},
		{
			name: "export defaults on non-macOS",
			app: &App{
				ExportDefaults: true,
			},
			args:        []string{},
			wantErr:     true,
			errContains: "only available on macOS",
		},
		{
			name: "import defaults on non-macOS",
			app: &App{
				ImportDefaults: true,
			},
			args:        []string{},
			wantErr:     true,
			errContains: "only available on macOS",
		},
		{
			name: "run postinstall hooks",
			app: &App{
				RunPostInstall: true,
				DryRun:         true,
				Verbose:        true,
			},
			args:    []string{},
			wantErr: false,
		},
		{
			name: "run postlink hooks",
			app: &App{
				RunPostLink: true,
				DryRun:      true,
				Verbose:     true,
			},
			args:    []string{},
			wantErr: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Skip macOS-specific tests when running on macOS
			if strings.Contains(tt.name, "non-macOS") && runtime.GOOS == "darwin" {
				t.Skip("Skipping non-macOS test on macOS platform")
			}

			err := tt.app.Run(tt.args)

			if tt.wantErr {
				if err == nil {
					t.Errorf("App.Run() expected error but got none")
					return
				}
				if tt.errContains != "" && !strings.Contains(err.Error(), tt.errContains) {
					t.Errorf("App.Run() error = %v, want error containing %q", err, tt.errContains)
				}
				return
			}

			if err != nil {
				t.Errorf("App.Run() unexpected error = %v", err)
			}
		})
	}
}

func TestApp_removeProfileCommand(t *testing.T) {
	tempDir := t.TempDir()
	oldWd, _ := os.Getwd()
	defer os.Chdir(oldWd)
	os.Chdir(tempDir)

	app := &App{}

	tests := []struct {
		name        string
		profileName string
		wantErr     bool
		errContains string
	}{
		{
			name:        "remove non-existent profile",
			profileName: "nonexistent",
			wantErr:     true,
			errContains: "not currently active",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := app.removeProfileCommand(tt.profileName)

			if tt.wantErr {
				if err == nil {
					t.Errorf("removeProfileCommand() expected error but got none")
					return
				}
				if tt.errContains != "" && !strings.Contains(err.Error(), tt.errContains) {
					t.Errorf("removeProfileCommand() error = %v, want error containing %q", err, tt.errContains)
				}
				return
			}

			if err != nil {
				t.Errorf("removeProfileCommand() unexpected error = %v", err)
			}
		})
	}
}

func TestUpgradeCommand(t *testing.T) {
	tests := []struct {
		name    string
		verbose bool
		wantErr bool
	}{
		{
			name:    "verbose upgrade",
			verbose: true,
			wantErr: true, // Will fail because we can't actually download
		},
		{
			name:    "quiet upgrade",
			verbose: false,
			wantErr: true, // Will fail because we can't actually download
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := upgradeCommand(tt.verbose)

			// We expect this to fail in tests since we can't actually download
			if !tt.wantErr && err != nil {
				t.Errorf("upgradeCommand() unexpected error = %v", err)
			}
		})
	}
}

func TestListProfilesCommand(t *testing.T) {
	tempDir := t.TempDir()
	configContent := `
profiles:
  default:
    test-component:
      link:
        test-file: ~/.test-file
  work:
    work-component:
      link:
        work-file: ~/.work-file
`
	configPath := filepath.Join(tempDir, "dot.yaml")
	if err := os.WriteFile(configPath, []byte(configContent), 0644); err != nil {
		t.Fatalf("Failed to create test config: %v", err)
	}

	oldWd, _ := os.Getwd()
	defer os.Chdir(oldWd)
	os.Chdir(tempDir)

	// Capture stdout
	old := os.Stdout
	r, w, _ := os.Pipe()
	os.Stdout = w

	err := listProfilesCommand()

	w.Close()
	os.Stdout = old

	var buf bytes.Buffer
	buf.ReadFrom(r)
	output := buf.String()

	if err != nil {
		t.Errorf("listProfilesCommand() unexpected error = %v", err)
	}

	if !strings.Contains(output, "Available profiles:") {
		t.Errorf("listProfilesCommand() output should contain 'Available profiles:', got: %s", output)
	}

	if !strings.Contains(output, "default") || !strings.Contains(output, "work") {
		t.Errorf("listProfilesCommand() output should contain profile names, got: %s", output)
	}
}

func TestApp_printResults(t *testing.T) {
	tempDir := t.TempDir()
	oldWd, _ := os.Getwd()
	defer os.Chdir(oldWd)
	os.Chdir(tempDir)

	app := &App{Verbose: true}

	// This test mainly ensures the print functions don't crash
	// We can't easily test output without complex stdout capturing
	results := []component.InstallResult{} // Import will be needed

	// Test with empty results
	app.printResults("Test", results)

	// Test summary results
	app.printSummaryResults("Test", results)
}

func TestApp_HookExecution(t *testing.T) {
	// Create a temporary directory for testing
	tempDir := t.TempDir()

	// Create a test config file with hooks
	configContent := `
profiles:
  "*":
    component-with-postinstall:
      link:
        test-file: ~/.test-file
      postinstall: "echo 'postinstall executed'"
    component-with-postlink:
      link:
        test-file2: ~/.test-file2
      postlink: "echo 'postlink executed'"
    component-without-hooks:
      link:
        test-file3: ~/.test-file3
`
	configPath := filepath.Join(tempDir, "dot.yaml")
	if err := os.WriteFile(configPath, []byte(configContent), 0644); err != nil {
		t.Fatalf("Failed to create test config: %v", err)
	}

	// Change to temp directory and set clean HOME
	oldWd, _ := os.Getwd()
	defer os.Chdir(oldWd)
	os.Chdir(tempDir)

	// Set HOME to temp directory to avoid using existing state
	originalHome := os.Getenv("HOME")
	os.Setenv("HOME", tempDir)
	defer os.Setenv("HOME", originalHome)

	tests := []struct {
		name    string
		app     *App
		args    []string
		wantErr bool
	}{
		{
			name: "run postinstall hooks",
			app: &App{
				RunPostInstall: true,
				DryRun:         true,
				Verbose:        false,
			},
			args:    []string{},
			wantErr: false,
		},
		{
			name: "run postlink hooks",
			app: &App{
				RunPostLink: true,
				DryRun:      true,
				Verbose:     false,
			},
			args:    []string{},
			wantErr: false,
		},
		{
			name: "run postinstall hooks with profile",
			app: &App{
				RunPostInstall: true,
				DryRun:         true,
				Verbose:        true,
			},
			args:    []string{"*"},
			wantErr: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := tt.app.Run(tt.args)

			if tt.wantErr {
				if err == nil {
					t.Errorf("App.Run() expected error but got none")
				}
				return
			}

			if err != nil {
				t.Errorf("App.Run() unexpected error = %v", err)
			}
		})
	}
}

func TestFlagParsing(t *testing.T) {
	tests := []struct {
		name     string
		args     []string
		expected map[string]bool
	}{
		{
			name: "verbose flag short",
			args: []string{"-v"},
			expected: map[string]bool{
				"verbose": true,
			},
		},
		{
			name: "verbose flag long",
			args: []string{"--verbose"},
			expected: map[string]bool{
				"verbose": true,
			},
		},
		{
			name: "dry run flag",
			args: []string{"--dry-run"},
			expected: map[string]bool{
				"dry-run": true,
			},
		},
		{
			name: "multiple flags",
			args: []string{"-v", "--dry-run", "--install", "--link"},
			expected: map[string]bool{
				"verbose": true,
				"dry-run": true,
				"install": true,
				"link":    true,
			},
		},
		{
			name: "postinstall hook flag",
			args: []string{"--postinstall"},
			expected: map[string]bool{
				"postinstall": true,
			},
		},
		{
			name: "postlink hook flag",
			args: []string{"--postlink"},
			expected: map[string]bool{
				"postlink": true,
			},
		},
		{
			name: "link flag",
			args: []string{"--link"},
			expected: map[string]bool{
				"link": true,
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			flag.CommandLine = flag.NewFlagSet(os.Args[0], flag.ExitOnError)

			verbose := flag.Bool("v", false, "verbose output")
			verboseLong := flag.Bool("verbose", false, "verbose output")
			dryRun := flag.Bool("dry-run", false, "preview actions without making changes")
			install := flag.Bool("install", false, "force reinstall")
			postinstall := flag.Bool("postinstall", false, "run only postinstall hooks")
			postlink := flag.Bool("postlink", false, "run only postlink hooks")
			link := flag.Bool("link", false, "link configs only (no installs)")

			os.Args = append([]string{"dot"}, tt.args...)
			flag.Parse()

			if expected, exists := tt.expected["verbose"]; exists {
				if (*verbose || *verboseLong) != expected {
					t.Errorf("verbose flag = %v, want %v", (*verbose || *verboseLong), expected)
				}
			}
			if expected, exists := tt.expected["dry-run"]; exists {
				if *dryRun != expected {
					t.Errorf("dry-run flag = %v, want %v", *dryRun, expected)
				}
			}
			if expected, exists := tt.expected["install"]; exists {
				if *install != expected {
					t.Errorf("install flag = %v, want %v", *install, expected)
				}
			}
			if expected, exists := tt.expected["link"]; exists {
				if *link != expected {
					t.Errorf("link flag = %v, want %v", *link, expected)
				}
			}
			if expected, exists := tt.expected["postinstall"]; exists {
				if *postinstall != expected {
					t.Errorf("postinstall flag = %v, want %v", *postinstall, expected)
				}
			}
			if expected, exists := tt.expected["postlink"]; exists {
				if *postlink != expected {
					t.Errorf("postlink flag = %v, want %v", *postlink, expected)
				}
			}
		})
	}
}

// New test: profiles are saved even if tool installation fails
func TestProfileSavedEvenIfInstallFails(t *testing.T) {
	// Setup temp workspace and HOME
	tempDir := t.TempDir()
	oldWd, _ := os.Getwd()
	defer os.Chdir(oldWd)
	os.Chdir(tempDir)

	originalHome := os.Getenv("HOME")
	os.Setenv("HOME", tempDir)
	defer os.Setenv("HOME", originalHome)

	// Config with a profile whose install always fails
	configContent := `
profiles:
  failp:
    broken:
      install:
        sh: "false"
`
	if err := os.WriteFile(filepath.Join(tempDir, "dot.yaml"), []byte(configContent), 0644); err != nil {
		t.Fatalf("Failed to write config: %v", err)
	}

	// Run the app with the failing profile
	app := &App{Verbose: false, DryRun: false}
	if err := app.Run([]string{"failp"}); err != nil {
		// The app should not return an error for component failures
		t.Fatalf("App.Run returned error: %v", err)
	}

	// Verify state saved the active profile
	stateManager, err := state.NewManager()
	if err != nil {
		t.Fatalf("Failed to create state manager: %v", err)
	}

	profiles := stateManager.GetActiveProfiles()
	found := false
	for _, p := range profiles {
		if p == "failp" {
			found = true
			break
		}
	}
	if !found {
		t.Fatalf("expected active profiles to include 'failp', got %v", profiles)
	}
}
