package component

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/pablopunk/dot/internal/config"
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

	rawConfig := map[string]config.Component{
		"bash": {
			Link: config.LinkMap{
				"bash/.bashrc": []string{filepath.Join(homeDir, ".bashrc")},
			},
		},
		"git": {
			Link: config.LinkMap{
				"bash/.bashrc": []string{filepath.Join(homeDir, ".gitconfig")},
			},
			PostLink: "echo 'git post-link'",
		},
		"docker": {
			Link: config.LinkMap{
				"bash/.bashrc": []string{filepath.Join(homeDir, ".dockerrc")},
			},
			PostLink: "echo 'docker post-link'",
		},
	}

	// Convert to map[string]interface{} for Config field
	configMap := make(map[string]interface{})
	for k, v := range rawConfig {
		configMap[k] = v
	}

	cfg := &config.Config{
		Profiles: map[string][]interface{}{
			"*": {
				"bash",
			},
			"work": {
				"git",
				"docker",
			},
		},
		Config:    configMap,
		RawConfig: rawConfig,
	}

	manager, err := NewManager(cfg, dotfilesDir, false, dryRun)
	if err != nil {
		t.Fatalf("Failed to create component manager: %v", err)
	}

	return manager, homeDir
}

func TestNewManager(t *testing.T) {
	rawConfig := map[string]config.Component{
		"test": {
			Link: config.LinkMap{"test": []string{"~/.test"}},
		},
	}

	configMap := make(map[string]interface{})
	for k, v := range rawConfig {
		configMap[k] = v
	}

	cfg := &config.Config{
		Profiles: map[string][]interface{}{
			"*": {
				"test",
			},
		},
		Config:    configMap,
		RawConfig: rawConfig,
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

	// Should have bash component from * profile
	if len(results) == 0 {
		t.Error("Expected at least 1 result, got 0")
	}

	// Check that bash symlink was created
	bashrcLink := filepath.Join(homeDir, ".bashrc")
	if _, err := os.Stat(bashrcLink); os.IsNotExist(err) {
		t.Errorf("Expected .bashrc symlink to be created at %s", bashrcLink)
	}
}

func TestInstallSpecificProfile(t *testing.T) {
	manager, homeDir := createTestComponentManager(t, false)

	// Install work profile
	results, err := manager.InstallComponents([]string{"work"}, "", false)
	if err != nil {
		t.Fatalf("InstallComponents() error = %v", err)
	}

	// Should have git and docker components
	resultNames := make(map[string]bool)
	for _, result := range results {
		resultNames[result.Component.ComponentName] = true
	}

	if !resultNames["git"] {
		t.Error("Expected git component in results")
	}
	if !resultNames["docker"] {
		t.Error("Expected docker component in results")
	}

	// Check symlinks were created
	gitconfigLink := filepath.Join(homeDir, ".gitconfig")
	if _, err := os.Stat(gitconfigLink); os.IsNotExist(err) {
		t.Errorf("Expected .gitconfig symlink at %s", gitconfigLink)
	}

	dockerrcLink := filepath.Join(homeDir, ".dockerrc")
	if _, err := os.Stat(dockerrcLink); os.IsNotExist(err) {
		t.Errorf("Expected .dockerrc symlink at %s", dockerrcLink)
	}
}

func TestDryRun(t *testing.T) {
	manager, homeDir := createTestComponentManager(t, true)

	// Install in dry-run mode
	_, err := manager.InstallComponents([]string{}, "", false)
	if err != nil {
		t.Fatalf("InstallComponents() error = %v", err)
	}

	// Check that symlinks were NOT created
	bashrcLink := filepath.Join(homeDir, ".bashrc")
	if _, err := os.Stat(bashrcLink); err == nil {
		t.Errorf("Expected .bashrc symlink NOT to be created in dry-run mode at %s", bashrcLink)
	}
}
