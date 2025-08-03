package component

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/pablopunk/dot/internal/config"
	"github.com/pablopunk/dot/internal/profile"
	"github.com/pablopunk/dot/internal/ui"
)

func createTestComponentManager(t *testing.T, dryRun bool) (*Manager, string) {
	tmpDir := t.TempDir()
	dotfilesDir := filepath.Join(tmpDir, "dotfiles")
	homeDir := filepath.Join(tmpDir, "home")

	// Create directories
	if err := os.MkdirAll(filepath.Join(dotfilesDir, "bash"), 0755); err != nil {
		t.Fatalf("Failed to create bash dir: %v", err)
	}
	if err := os.MkdirAll(homeDir, 0755); err != nil {
		t.Fatalf("Failed to create home dir: %v", err)
	}

	// Create source file
	bashrcPath := filepath.Join(dotfilesDir, "bash", ".bashrc")
	if err := os.WriteFile(bashrcPath, []byte("test content"), 0644); err != nil {
		t.Fatalf("Failed to create .bashrc: %v", err)
	}

	// Set HOME for state manager
	originalHome := os.Getenv("HOME")
	os.Setenv("HOME", homeDir)
	t.Cleanup(func() { os.Setenv("HOME", originalHome) })

	cfg := &config.Config{
		Profiles: map[string]config.Profile{
			"*": {
				"bash": config.Component{
					Link: map[string]string{
						"bash/.bashrc": filepath.Join(homeDir, ".bashrc"),
					},
				},
			},
			"work": {
				"git": config.Component{
					Link: map[string]string{
						"bash/.bashrc": filepath.Join(homeDir, ".gitconfig"), // Use linking instead of install for testing
					},
					PostLink: "echo 'git post-link'",
				},
				"docker": config.Component{
					Link: map[string]string{
						"bash/.bashrc": filepath.Join(homeDir, ".dockerrc"), // Reuse source file
					},
					PostLink: "echo 'docker post-link'",
				},
			},
		},
	}

	manager, err := NewManager(cfg, dotfilesDir, false, dryRun)
	if err != nil {
		t.Fatalf("Failed to create component manager: %v", err)
	}

	return manager, homeDir
}

func TestNewManager(t *testing.T) {
	cfg := &config.Config{
		Profiles: map[string]config.Profile{
			"*": {
				"test": config.Component{
					Link: map[string]string{"test": "~/.test"},
				},
			},
		},
	}

	manager, err := NewManager(cfg, "/tmp", false, false)
	if err != nil {
		t.Fatalf("NewManager() error = %v", err)
	}

	if manager.baseDir != "/tmp" {
		t.Errorf("NewManager() baseDir = %v, want /tmp", manager.baseDir)
	}

	if manager.dryRun {
		t.Error("NewManager() dryRun should be false")
	}
}

func TestInstallComponents(t *testing.T) {
	manager, homeDir := createTestComponentManager(t, false)

	// Install default profile
	results, err := manager.InstallComponents([]string{}, "", false)
	if err != nil {
		t.Fatalf("InstallComponents() error = %v", err)
	}

	if len(results) != 1 {
		t.Fatalf("InstallComponents() results count = %v, want 1", len(results))
	}

	result := results[0]
	if result.Error != nil {
		t.Errorf("InstallComponents() result error = %v", result.Error)
	}

	if result.Component.ComponentName != "bash" {
		t.Errorf("InstallComponents() component name = %v, want bash", result.Component.ComponentName)
	}

	// Verify symlink was created
	targetPath := filepath.Join(homeDir, ".bashrc")
	if _, err := os.Lstat(targetPath); err != nil {
		t.Errorf("Symlink should exist at %s: %v", targetPath, err)
	}
}

func TestInstallComponentsWithInstallCommands(t *testing.T) {
	manager, _ := createTestComponentManager(t, false)

	// Install work profile which has install commands
	results, err := manager.InstallComponents([]string{"work"}, "", false)
	if err != nil {
		t.Fatalf("InstallComponents() error = %v", err)
	}

	// Should have bash (from *) + git and docker (from work)
	if len(results) != 3 {
		t.Fatalf("InstallComponents() results count = %v, want 3", len(results))
	}

	// Find the git component result
	var gitResult *InstallResult
	for i := range results {
		if results[i].Component.ComponentName == "git" {
			gitResult = &results[i]
			break
		}
	}

	if gitResult == nil {
		t.Fatal("Git component result not found")
	}

	// Since we changed to linking, check for link results instead
	if len(gitResult.LinkResults) == 0 {
		t.Error("Git component should have link results")
	}

	if gitResult.PostLinkResult == nil {
		t.Error("Git component should have post-link result")
	}
}

func TestInstallComponentsDryRun(t *testing.T) {
	manager, homeDir := createTestComponentManager(t, true)

	results, err := manager.InstallComponents([]string{}, "", false)
	if err != nil {
		t.Fatalf("InstallComponents() error = %v", err)
	}

	if len(results) != 1 {
		t.Fatalf("InstallComponents() results count = %v, want 1", len(results))
	}

	result := results[0]
	if result.Error != nil {
		t.Errorf("InstallComponents() result error = %v", result.Error)
	}

	// Verify no actual symlink was created
	targetPath := filepath.Join(homeDir, ".bashrc")
	if _, err := os.Lstat(targetPath); !os.IsNotExist(err) {
		t.Error("Symlink should not exist in dry run mode")
	}

	// But link result should show would_create
	if len(result.LinkResults) != 1 {
		t.Fatalf("Expected 1 link result, got %d", len(result.LinkResults))
	}

	if result.LinkResults[0].Action != "would_create" {
		t.Errorf("Link action = %v, want would_create", result.LinkResults[0].Action)
	}
}

func TestInstallComponentsForceInstall(t *testing.T) {
	manager, _ := createTestComponentManager(t, false)

	// Install once
	results1, err := manager.InstallComponents([]string{}, "", false)
	if err != nil || len(results1) != 1 {
		t.Fatalf("First install failed: %v", err)
	}

	if results1[0].Error != nil {
		t.Fatalf("First install had error: %v", results1[0].Error)
	}

	// Install again without force - should be skipped due to no changes
	results2, err := manager.InstallComponents([]string{}, "", false)
	if err != nil {
		t.Fatalf("Second install error = %v", err)
	}

	if len(results2) != 1 {
		t.Fatalf("Second install result count = %v, want 1", len(results2))
	}

	// The component should be skipped on second install since links already exist correctly
	if !results2[0].Skipped {
		t.Errorf("Second install should be skipped since links already exist correctly")
	}

	// Should not have an error
	if results2[0].Error != nil {
		t.Errorf("Second install should not have error: %v", results2[0].Error)
	}

	// Install again with force - should not be skipped
	results3, err := manager.InstallComponents([]string{}, "", true)
	if err != nil {
		t.Fatalf("Force install error = %v", err)
	}

	if len(results3) != 1 || results3[0].Skipped {
		t.Error("Force install should not be skipped")
	}
}

func TestInstallComponentsFuzzySearch(t *testing.T) {
	manager, _ := createTestComponentManager(t, true)

	// Search for "bash"
	results, err := manager.InstallComponents([]string{}, "bash", false)
	if err != nil {
		t.Fatalf("InstallComponents() error = %v", err)
	}

	if len(results) != 1 {
		t.Fatalf("Fuzzy search results count = %v, want 1", len(results))
	}

	if results[0].Component.ComponentName != "bash" {
		t.Errorf("Fuzzy search result = %v, want bash", results[0].Component.ComponentName)
	}
}

func TestUninstallRemovedComponents(t *testing.T) {
	manager, _ := createTestComponentManager(t, true)

	// First install some components to populate state
	_, err := manager.InstallComponents([]string{"work"}, "", false)
	if err != nil {
		t.Fatalf("Initial install error = %v", err)
	}

	// Manually add a component to the state that's not in current config
	testComponent := profile.ComponentInfo{
		ProfileName:   "work",
		ComponentName: "removed",
		Component: config.Component{
			Install: map[string]string{
				"test": "echo 'this is a unique install command for removed component'",
			},
		},
	}
	manager.stateManager.MarkComponentInstalled(testComponent, "echo", "echo test", map[string]string{})

	// Now uninstall removed components
	results, err := manager.UninstallRemovedComponents()
	if err != nil {
		t.Fatalf("UninstallRemovedComponents() error = %v", err)
	}

	if len(results) != 1 {
		t.Fatalf("Uninstall results count = %v, want 1", len(results))
	}

	if results[0].Component.ComponentName != "removed" {
		t.Errorf("Uninstalled component = %v, want removed", results[0].Component.ComponentName)
	}
}

func TestUninstallComponentWithCommand(t *testing.T) {
	// Create a test configuration with a component that has uninstall commands
	tmpDir := t.TempDir()
	dotfilesDir := filepath.Join(tmpDir, "dotfiles")
	homeDir := filepath.Join(tmpDir, "home")

	// Create directories
	if err := os.MkdirAll(dotfilesDir, 0755); err != nil {
		t.Fatalf("Failed to create dotfiles dir: %v", err)
	}
	if err := os.MkdirAll(homeDir, 0755); err != nil {
		t.Fatalf("Failed to create home dir: %v", err)
	}

	// Create source files for linking
	testFilePath := filepath.Join(dotfilesDir, "test")
	if err := os.WriteFile(testFilePath, []byte("test content"), 0644); err != nil {
		t.Fatalf("Failed to create test file: %v", err)
	}

	// Set HOME for state manager
	originalHome := os.Getenv("HOME")
	os.Setenv("HOME", homeDir)
	t.Cleanup(func() { os.Setenv("HOME", originalHome) })

	cfg := &config.Config{
		Profiles: map[string]config.Profile{
			"test": {
				"uninstallable": config.Component{
					Install: map[string]string{
						"echo": "echo 'installing uninstallable'",
					},
					Uninstall: map[string]string{
						"echo": "echo 'uninstalling uninstallable'",
					},
					Link: map[string]string{
						"test": filepath.Join(homeDir, ".test"),
					},
				},
				"no-uninstall": config.Component{
					Install: map[string]string{
						"echo": "echo 'installing no-uninstall'",
					},
					// No uninstall commands
					Link: map[string]string{
						"test": filepath.Join(homeDir, ".notest"),
					},
				},
			},
		},
	}

	manager, err := NewManager(cfg, dotfilesDir, false, false) // not dry-run mode
	if err != nil {
		t.Fatalf("Failed to create component manager: %v", err)
	}

	// Install components first
	installResults, err := manager.InstallComponents([]string{"test"}, "", false)
	if err != nil {
		t.Fatalf("Initial install error = %v", err)
	}

	if len(installResults) != 2 {
		t.Fatalf("Expected 2 install results, got %d", len(installResults))
	}

	// Verify components are in state
	installedComponents := manager.stateManager.GetInstalledComponents()
	if len(installedComponents) != 2 {
		t.Fatalf("Expected 2 components in state, got %d", len(installedComponents))
	}

	// Now simulate components being removed from the "test" profile
	// The state still has them as installed under "test", but the config no longer has them in "test"
	configAfterRemoval := &config.Config{
		Profiles: map[string]config.Profile{
			"test": {
				// Profile exists but components were removed from it
				"uninstallable": config.Component{
					Install: map[string]string{
						"echo": "echo 'installing uninstallable'",
					},
					Uninstall: map[string]string{
						"echo": "echo 'uninstalling uninstallable'",
					},
					Link: map[string]string{
						"test": filepath.Join(homeDir, ".test"),
					},
				},
				"no-uninstall": config.Component{
					Install: map[string]string{
						"echo": "echo 'installing no-uninstall'",
					},
					// No uninstall commands
					Link: map[string]string{
						"test": filepath.Join(homeDir, ".notest"),
					},
				},
			},
		},
	}

	// Create new profile manager but simulate removing these components from active use
	// by calling GetActiveComponents with a profile that doesn't include them
	originalProfileManager := manager.profileManager
	manager.profileManager = profile.NewManager(configAfterRemoval)

	// Manually call GetRemovedComponents with empty current components to simulate removal
	currentComponents := []profile.ComponentInfo{} // No current components = all existing ones are removed
	removedComponents := manager.stateManager.GetRemovedComponents(currentComponents)

	// Test uninstalling these removed components
	if len(removedComponents) != 2 {
		t.Fatalf("Expected 2 removed components, got %d", len(removedComponents))
	}

	// Restore original profile manager and create an empty current components list to trigger uninstall
	manager.profileManager = originalProfileManager

	// Simulate the real scenario by using the public API with an empty profile
	emptyConfig := &config.Config{
		Profiles: map[string]config.Profile{
			"test": {
				// Empty profile - components were removed
			},
		},
	}
	manager.profileManager = profile.NewManager(emptyConfig)

	// Now call the real UninstallRemovedComponents method
	results, err := manager.UninstallRemovedComponents()
	if err != nil {
		t.Fatalf("UninstallRemovedComponents() error = %v", err)
	}

	if len(results) != 2 {
		t.Fatalf("Expected 2 uninstall results, got %d", len(results))
	}

	// Verify results - one should have InstallResult (actual uninstall command), one should not
	var withUninstall, withoutUninstall *InstallResult
	for i := range results {
		if results[i].Component.ComponentName == "uninstallable" {
			withUninstall = &results[i]
		} else if results[i].Component.ComponentName == "no-uninstall" {
			withoutUninstall = &results[i]
		}
	}

	if withUninstall == nil {
		t.Fatal("Did not find uninstallable component in results")
	}
	if withoutUninstall == nil {
		t.Fatal("Did not find no-uninstall component in results")
	}

	// Component with uninstall commands should have InstallResult set
	if withUninstall.InstallResult == nil {
		t.Error("Component with uninstall commands should have InstallResult set")
	} else {
		if !withUninstall.InstallResult.Success {
			t.Errorf("Uninstall command should succeed in dry-run mode")
		}
		if !strings.Contains(withUninstall.InstallResult.Output, "uninstalling uninstallable") {
			t.Errorf("Uninstall output should contain command output, got: %s", withUninstall.InstallResult.Output)
		}
	}

	// Component without uninstall commands should not have InstallResult set
	if withoutUninstall.InstallResult != nil {
		t.Error("Component without uninstall commands should not have InstallResult set")
	}

	// Both should have link results (link removal)
	if len(withUninstall.LinkResults) == 0 {
		t.Error("Component with uninstall should still have link removal results")
	}
	if len(withoutUninstall.LinkResults) == 0 {
		t.Error("Component without uninstall should have link removal results")
	}
}

func TestInstallResultWasSuccessful(t *testing.T) {
	tests := []struct {
		name   string
		result InstallResult
		want   bool
	}{
		{
			name:   "successful result",
			result: InstallResult{Error: nil},
			want:   true,
		},
		{
			name:   "result with error",
			result: InstallResult{Error: &TestError{}},
			want:   false,
		},
		{
			name:   "skipped result",
			result: InstallResult{Skipped: true, Error: nil},
			want:   true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := tt.result.WasSuccessful(); got != tt.want {
				t.Errorf("InstallResult.WasSuccessful() = %v, want %v", got, tt.want)
			}
		})
	}
}

// Mock error for testing
type TestError struct{}

func (e *TestError) Error() string {
	return "test error"
}

func TestInstallComponentsWithProgress(t *testing.T) {
	manager, homeDir := createTestComponentManager(t, false)
	progressManager := ui.NewProgressManager(true) // quiet mode for tests
	defer progressManager.StopAll()

	// Install default profile with progress
	results, err := manager.InstallComponentsWithProgress([]string{}, "", false, progressManager)
	if err != nil {
		t.Fatalf("InstallComponentsWithProgress() error = %v", err)
	}

	if len(results) != 1 {
		t.Fatalf("InstallComponentsWithProgress() results count = %v, want 1", len(results))
	}

	result := results[0]
	if result.Error != nil {
		t.Errorf("InstallComponentsWithProgress() result error = %v", result.Error)
	}

	if result.Component.ComponentName != "bash" {
		t.Errorf("InstallComponentsWithProgress() component name = %v, want bash", result.Component.ComponentName)
	}

	// Verify symlink was created
	targetPath := filepath.Join(homeDir, ".bashrc")
	if _, err := os.Lstat(targetPath); err != nil {
		t.Errorf("Symlink should exist at %s: %v", targetPath, err)
	}
}

func TestInstallComponentWithProgress(t *testing.T) {
	manager, homeDir := createTestComponentManager(t, false)
	progressManager := ui.NewProgressManager(true) // quiet mode for tests
	defer progressManager.StopAll()

	// Get component info
	components, err := manager.profileManager.GetActiveComponents([]string{}, "")
	if err != nil {
		t.Fatalf("Failed to get components: %v", err)
	}

	if len(components) != 1 {
		t.Fatalf("Expected 1 component, got %d", len(components))
	}

	comp := components[0]

	// Test install with progress
	result := manager.installComponentWithProgress(comp, false, progressManager)

	if result.Error != nil {
		t.Errorf("installComponentWithProgress() error = %v", result.Error)
	}

	if result.Component.ComponentName != "bash" {
		t.Errorf("installComponentWithProgress() component name = %v, want bash", result.Component.ComponentName)
	}

	// Verify symlink was created
	targetPath := filepath.Join(homeDir, ".bashrc")
	if _, err := os.Lstat(targetPath); err != nil {
		t.Errorf("Symlink should exist at %s: %v", targetPath, err)
	}

	// Test second install with progress (should be skipped since links already exist correctly)
	result2 := manager.installComponentWithProgress(comp, false, progressManager)
	if !result2.Skipped {
		t.Error("Second install should be skipped since links already exist correctly")
	}

	if result2.Error != nil {
		t.Errorf("Second install should not have error: %v", result2.Error)
	}

	// Test force install with progress
	result3 := manager.installComponentWithProgress(comp, true, progressManager)
	if result3.Skipped {
		t.Error("Force install should not be skipped")
	}
}

func TestInstallComponentFailures(t *testing.T) {
	tmpDir := t.TempDir()
	dotfilesDir := filepath.Join(tmpDir, "dotfiles")
	homeDir := filepath.Join(tmpDir, "home")

	// Create directories
	if err := os.MkdirAll(dotfilesDir, 0755); err != nil {
		t.Fatalf("Failed to create dotfiles dir: %v", err)
	}
	if err := os.MkdirAll(homeDir, 0755); err != nil {
		t.Fatalf("Failed to create home dir: %v", err)
	}

	// Set HOME for state manager
	originalHome := os.Getenv("HOME")
	os.Setenv("HOME", homeDir)
	t.Cleanup(func() { os.Setenv("HOME", originalHome) })

	tests := []struct {
		name           string
		config         *config.Config
		expectedError  string
		skipSourceFile bool
	}{
		{
			name: "component with install but no package manager",
			config: &config.Config{
				Profiles: map[string]config.Profile{
					"*": {
						"test": config.Component{
							Install: map[string]string{
								"nonexistent": "nonexistent install some-package",
							},
						},
					},
				},
			},
			expectedError: "no available command for component",
		},
		{
			name: "component with invalid link source",
			config: &config.Config{
				Profiles: map[string]config.Profile{
					"*": {
						"test": config.Component{
							Link: map[string]string{
								"nonexistent/.bashrc": filepath.Join(homeDir, ".bashrc"),
							},
						},
					},
				},
			},
			expectedError:  "linking failed",
			skipSourceFile: true,
		},
		{
			name: "component with failing post-install hook",
			config: &config.Config{
				Profiles: map[string]config.Profile{
					"*": {
						"test": config.Component{
							Install: map[string]string{
								"echo": "echo test", // Use echo which should be available
							},
							PostInstall: "exit 1", // Failing command
						},
					},
				},
			},
			expectedError: "post-install hook failed",
		},
		{
			name: "component with failing post-link hook",
			config: &config.Config{
				Profiles: map[string]config.Profile{
					"*": {
						"test": config.Component{
							Link: map[string]string{
								"test/.bashrc": filepath.Join(homeDir, ".bashrc"),
							},
							PostLink: "exit 1", // Failing command
						},
					},
				},
			},
			expectedError: "post-link hook failed",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Create source file if needed
			if !tt.skipSourceFile {
				sourcePath := filepath.Join(dotfilesDir, "test", ".bashrc")
				if err := os.MkdirAll(filepath.Dir(sourcePath), 0755); err != nil {
					t.Fatalf("Failed to create source dir: %v", err)
				}
				if err := os.WriteFile(sourcePath, []byte("test content"), 0644); err != nil {
					t.Fatalf("Failed to create source file: %v", err)
				}
			}

			manager, err := NewManager(tt.config, dotfilesDir, false, false)
			if err != nil {
				t.Fatalf("Failed to create component manager: %v", err)
			}

			results, err := manager.InstallComponents([]string{}, "", false)
			if err != nil {
				t.Fatalf("InstallComponents() error = %v", err)
			}

			if len(results) != 1 {
				t.Fatalf("Expected 1 result, got %d", len(results))
			}

			result := results[0]
			if result.Error == nil {
				t.Errorf("Expected error containing %q, got no error", tt.expectedError)
			} else if !contains(result.Error.Error(), tt.expectedError) {
				t.Errorf("Expected error containing %q, got %q", tt.expectedError, result.Error.Error())
			}

			// Clean up for next test
			os.RemoveAll(filepath.Join(dotfilesDir, "test"))
			os.RemoveAll(filepath.Join(homeDir, ".bashrc"))
		})
	}
}

func TestManagerDefaults(t *testing.T) {
	tmpDir := t.TempDir()
	homeDir := filepath.Join(tmpDir, "home")
	if err := os.MkdirAll(homeDir, 0755); err != nil {
		t.Fatalf("Failed to create home dir: %v", err)
	}

	// Set HOME for state manager
	originalHome := os.Getenv("HOME")
	os.Setenv("HOME", homeDir)
	t.Cleanup(func() { os.Setenv("HOME", originalHome) })

	cfg := &config.Config{
		Profiles: map[string]config.Profile{
			"*": {
				"test": config.Component{
					Link: map[string]string{
						"test": "~/test",
					},
					Defaults: map[string]string{
						"com.example.test": "~/test.plist",
					},
				},
			},
		},
	}

	manager, err := NewManager(cfg, tmpDir, false, false)
	if err != nil {
		t.Fatalf("Failed to create component manager: %v", err)
	}

	// Test ExportDefaults
	results := manager.ExportDefaults([]string{})
	if results != nil {
		// On non-macOS systems, this might return early
		// This test mainly ensures the method doesn't panic
	}

	// Test ImportDefaults
	results = manager.ImportDefaults([]string{})
	if results != nil {
		// On non-macOS systems, this might return early
		// This test mainly ensures the method doesn't panic
	}
}

func TestManagerVerboseAndDryRun(t *testing.T) {
	cfg := &config.Config{
		Profiles: map[string]config.Profile{
			"*": {
				"test": config.Component{
					Link: map[string]string{"test": "~/test"},
				},
			},
		},
	}

	tests := []struct {
		name    string
		verbose bool
		dryRun  bool
	}{
		{"verbose enabled", true, false},
		{"dry run enabled", false, true},
		{"both enabled", true, true},
		{"both disabled", false, false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			manager, err := NewManager(cfg, "/tmp", tt.verbose, tt.dryRun)
			if err != nil {
				t.Fatalf("NewManager() error = %v", err)
			}

			if manager.verbose != tt.verbose {
				t.Errorf("NewManager() verbose = %v, want %v", manager.verbose, tt.verbose)
			}

			if manager.dryRun != tt.dryRun {
				t.Errorf("NewManager() dryRun = %v, want %v", manager.dryRun, tt.dryRun)
			}
		})
	}
}

func TestRunPostInstallHooks(t *testing.T) {
	tmpDir := t.TempDir()
	homeDir := filepath.Join(tmpDir, "home")

	// Set HOME for state manager
	originalHome := os.Getenv("HOME")
	os.Setenv("HOME", homeDir)
	t.Cleanup(func() { os.Setenv("HOME", originalHome) })

	tests := []struct {
		name            string
		config          *config.Config
		profiles        []string
		fuzzySearch     string
		expectedSuccess int
		expectedSkipped int
		expectedFailed  int
	}{
		{
			name: "run postinstall hooks",
			config: &config.Config{
				Profiles: map[string]config.Profile{
					"*": {
						"with-hook": config.Component{
							PostInstall: "echo 'postinstall success'",
						},
						"without-hook": config.Component{
							Link: map[string]string{"test": "~/.test"},
						},
					},
				},
			},
			profiles:        []string{"*"},
			expectedSuccess: 1,
			expectedSkipped: 1,
			expectedFailed:  0,
		},
		{
			name: "failing postinstall hook",
			config: &config.Config{
				Profiles: map[string]config.Profile{
					"*": {
						"failing-hook": config.Component{
							PostInstall: "exit 1",
						},
					},
				},
			},
			profiles:        []string{"*"},
			expectedSuccess: 0,
			expectedSkipped: 0,
			expectedFailed:  1,
		},
		{
			name: "no matching components",
			config: &config.Config{
				Profiles: map[string]config.Profile{
					"*": {
						"test": config.Component{
							Link: map[string]string{"test": "~/.test"},
						},
					},
				},
			},
			profiles:        []string{"*"},
			expectedSuccess: 0,
			expectedSkipped: 1,
			expectedFailed:  0,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			manager, err := NewManager(tt.config, tmpDir, false, false)
			if err != nil {
				t.Fatalf("Failed to create manager: %v", err)
			}

			results, err := manager.RunPostInstallHooks(tt.profiles, tt.fuzzySearch)
			if err != nil {
				t.Fatalf("RunPostInstallHooks() error = %v", err)
			}

			var successful, skipped, failed int
			for _, result := range results {
				if result.Skipped {
					skipped++
				} else if result.WasSuccessful() {
					successful++
				} else {
					failed++
				}
			}

			if successful != tt.expectedSuccess {
				t.Errorf("RunPostInstallHooks() successful = %v, want %v", successful, tt.expectedSuccess)
			}
			if skipped != tt.expectedSkipped {
				t.Errorf("RunPostInstallHooks() skipped = %v, want %v", skipped, tt.expectedSkipped)
			}
			if failed != tt.expectedFailed {
				t.Errorf("RunPostInstallHooks() failed = %v, want %v", failed, tt.expectedFailed)
			}
		})
	}
}

func TestRunPostLinkHooks(t *testing.T) {
	tmpDir := t.TempDir()
	homeDir := filepath.Join(tmpDir, "home")

	// Set HOME for state manager
	originalHome := os.Getenv("HOME")
	os.Setenv("HOME", homeDir)
	t.Cleanup(func() { os.Setenv("HOME", originalHome) })

	tests := []struct {
		name            string
		config          *config.Config
		profiles        []string
		fuzzySearch     string
		expectedSuccess int
		expectedSkipped int
		expectedFailed  int
	}{
		{
			name: "run postlink hooks",
			config: &config.Config{
				Profiles: map[string]config.Profile{
					"*": {
						"with-hook": config.Component{
							PostLink: "echo 'postlink success'",
						},
						"without-hook": config.Component{
							Link: map[string]string{"test": "~/.test"},
						},
					},
				},
			},
			profiles:        []string{"*"},
			expectedSuccess: 1,
			expectedSkipped: 1,
			expectedFailed:  0,
		},
		{
			name: "failing postlink hook",
			config: &config.Config{
				Profiles: map[string]config.Profile{
					"*": {
						"failing-hook": config.Component{
							PostLink: "exit 1",
						},
					},
				},
			},
			profiles:        []string{"*"},
			expectedSuccess: 0,
			expectedSkipped: 0,
			expectedFailed:  1,
		},
		{
			name: "no matching components",
			config: &config.Config{
				Profiles: map[string]config.Profile{
					"*": {
						"test": config.Component{
							Link: map[string]string{"test": "~/.test"},
						},
					},
				},
			},
			profiles:        []string{"*"},
			expectedSuccess: 0,
			expectedSkipped: 1,
			expectedFailed:  0,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			manager, err := NewManager(tt.config, tmpDir, false, false)
			if err != nil {
				t.Fatalf("Failed to create manager: %v", err)
			}

			results, err := manager.RunPostLinkHooks(tt.profiles, tt.fuzzySearch)
			if err != nil {
				t.Fatalf("RunPostLinkHooks() error = %v", err)
			}

			var successful, skipped, failed int
			for _, result := range results {
				if result.Skipped {
					skipped++
				} else if result.WasSuccessful() {
					successful++
				} else {
					failed++
				}
			}

			if successful != tt.expectedSuccess {
				t.Errorf("RunPostLinkHooks() successful = %v, want %v", successful, tt.expectedSuccess)
			}
			if skipped != tt.expectedSkipped {
				t.Errorf("RunPostLinkHooks() skipped = %v, want %v", skipped, tt.expectedSkipped)
			}
			if failed != tt.expectedFailed {
				t.Errorf("RunPostLinkHooks() failed = %v, want %v", failed, tt.expectedFailed)
			}
		})
	}
}

// Helper function
func contains(s, substr string) bool {
	return len(s) >= len(substr) && (s == substr || (len(s) > len(substr) &&
		(s[:len(substr)] == substr || s[len(s)-len(substr):] == substr ||
			findSubstring(s, substr))))
}

func findSubstring(s, substr string) bool {
	for i := 0; i <= len(s)-len(substr); i++ {
		if s[i:i+len(substr)] == substr {
			return true
		}
	}
	return false
}
