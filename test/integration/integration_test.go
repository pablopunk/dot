package integration

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/pablopunk/dot/internal/component"
	"github.com/pablopunk/dot/internal/config"
)

func TestEndToEndWorkflow(t *testing.T) {
	// Create temporary directory structure
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

	// Create source files
	bashrcContent := "export PS1='test> '"
	bashrcPath := filepath.Join(dotfilesDir, "bash", ".bashrc")
	if err := os.WriteFile(bashrcPath, []byte(bashrcContent), 0644); err != nil {
		t.Fatalf("Failed to create .bashrc: %v", err)
	}

	// Create config file
	configContent := `
profiles:
  "*":
    bash:
      link:
        "bash/.bashrc": "` + filepath.Join(homeDir, ".bashrc") + `"
`

	configPath := filepath.Join(dotfilesDir, "dot.yaml")
	if err := os.WriteFile(configPath, []byte(configContent), 0644); err != nil {
		t.Fatalf("Failed to create config: %v", err)
	}

	// Change to dotfiles directory
	originalDir, err := os.Getwd()
	if err != nil {
		t.Fatalf("Failed to get current dir: %v", err)
	}
	defer os.Chdir(originalDir)

	if err := os.Chdir(dotfilesDir); err != nil {
		t.Fatalf("Failed to change to dotfiles dir: %v", err)
	}

	// Load config
	cfg, err := config.Load("dot.yaml")
	if err != nil {
		t.Fatalf("Failed to load config: %v", err)
	}

	// Create component manager
	componentManager, err := component.NewManager(cfg, dotfilesDir, false, false)
	if err != nil {
		t.Fatalf("Failed to create component manager: %v", err)
	}

	// Install components
	results, err := componentManager.InstallComponents([]string{}, "", false)
	if err != nil {
		t.Fatalf("Failed to install components: %v", err)
	}

	// Verify results
	if len(results) != 1 {
		t.Fatalf("Expected 1 result, got %d", len(results))
	}

	result := results[0]
	if result.Error != nil {
		t.Fatalf("Install result has error: %v", result.Error)
	}

	if result.Component.ComponentName != "bash" {
		t.Errorf("Expected component name 'bash', got %s", result.Component.ComponentName)
	}

	// Verify symlink was created
	targetPath := filepath.Join(homeDir, ".bashrc")
	linkInfo, err := os.Lstat(targetPath)
	if err != nil {
		t.Fatalf("Failed to stat target file: %v", err)
	}

	if linkInfo.Mode()&os.ModeSymlink == 0 {
		t.Error("Target is not a symlink")
	}

	// Verify symlink points to correct source
	linkedPath, err := os.Readlink(targetPath)
	if err != nil {
		t.Fatalf("Failed to read symlink: %v", err)
	}

	expectedPath := bashrcPath
	if linkedPath != expectedPath {
		t.Errorf("Symlink points to %s, want %s", linkedPath, expectedPath)
	}

	// Verify file content through symlink
	content, err := os.ReadFile(targetPath)
	if err != nil {
		t.Fatalf("Failed to read through symlink: %v", err)
	}

	if string(content) != bashrcContent {
		t.Errorf("File content mismatch: got %q, want %q", string(content), bashrcContent)
	}
}

func TestDryRunWorkflow(t *testing.T) {
	// Create temporary directory structure
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

	// Create config file
	configContent := `
profiles:
  "*":
    bash:
      link:
        "bash/.bashrc": "` + filepath.Join(homeDir, ".bashrc") + `"
`

	configPath := filepath.Join(dotfilesDir, "dot.yaml")
	if err := os.WriteFile(configPath, []byte(configContent), 0644); err != nil {
		t.Fatalf("Failed to create config: %v", err)
	}

	// Change to dotfiles directory
	originalDir, err := os.Getwd()
	if err != nil {
		t.Fatalf("Failed to get current dir: %v", err)
	}
	defer os.Chdir(originalDir)

	if err := os.Chdir(dotfilesDir); err != nil {
		t.Fatalf("Failed to change to dotfiles dir: %v", err)
	}

	// Load config
	cfg, err := config.Load("dot.yaml")
	if err != nil {
		t.Fatalf("Failed to load config: %v", err)
	}

	// Create component manager with dry run enabled
	componentManager, err := component.NewManager(cfg, dotfilesDir, false, true)
	if err != nil {
		t.Fatalf("Failed to create component manager: %v", err)
	}

	// Install components in dry run mode
	results, err := componentManager.InstallComponents([]string{}, "", false)
	if err != nil {
		t.Fatalf("Failed to install components: %v", err)
	}

	// Verify results
	if len(results) != 1 {
		t.Fatalf("Expected 1 result, got %d", len(results))
	}

	result := results[0]
	if result.Error != nil {
		t.Fatalf("Install result has error: %v", result.Error)
	}

	// Verify no actual symlink was created
	targetPath := filepath.Join(homeDir, ".bashrc")
	if _, err := os.Lstat(targetPath); !os.IsNotExist(err) {
		t.Error("Symlink should not exist in dry run mode")
	}

	// Verify link result indicates dry run
	if len(result.LinkResults) != 1 {
		t.Fatalf("Expected 1 link result, got %d", len(result.LinkResults))
	}

	linkResult := result.LinkResults[0]
	if linkResult.Action != "would_create" {
		t.Errorf("Expected link action 'would_create', got %s", linkResult.Action)
	}
}

func TestProfileSelection(t *testing.T) {
	// Create temporary directory structure
	tmpDir := t.TempDir()
	dotfilesDir := filepath.Join(tmpDir, "dotfiles")

	// Create directories
	if err := os.MkdirAll(filepath.Join(dotfilesDir, "bash"), 0755); err != nil {
		t.Fatalf("Failed to create bash dir: %v", err)
	}
	if err := os.MkdirAll(filepath.Join(dotfilesDir, "work"), 0755); err != nil {
		t.Fatalf("Failed to create work dir: %v", err)
	}

	// Create source files
	bashrcPath := filepath.Join(dotfilesDir, "bash", ".bashrc")
	if err := os.WriteFile(bashrcPath, []byte("bash config"), 0644); err != nil {
		t.Fatalf("Failed to create .bashrc: %v", err)
	}

	workConfigPath := filepath.Join(dotfilesDir, "work", "config")
	if err := os.WriteFile(workConfigPath, []byte("work config"), 0644); err != nil {
		t.Fatalf("Failed to create work config: %v", err)
	}

	// Create config file with multiple profiles
	configContent := `
profiles:
  "*":
    bash:
      link:
        "bash/.bashrc": "~/test_bashrc"
  work:
    work_tool:
      link:
        "work/config": "~/work_config"
`

	configPath := filepath.Join(dotfilesDir, "dot.yaml")
	if err := os.WriteFile(configPath, []byte(configContent), 0644); err != nil {
		t.Fatalf("Failed to create config: %v", err)
	}

	// Change to dotfiles directory
	originalDir, err := os.Getwd()
	if err != nil {
		t.Fatalf("Failed to get current dir: %v", err)
	}
	defer os.Chdir(originalDir)

	if err := os.Chdir(dotfilesDir); err != nil {
		t.Fatalf("Failed to change to dotfiles dir: %v", err)
	}

	// Load config
	cfg, err := config.Load("dot.yaml")
	if err != nil {
		t.Fatalf("Failed to load config: %v", err)
	}

	// Test default profile only
	componentManager, err := component.NewManager(cfg, dotfilesDir, false, true)
	if err != nil {
		t.Fatalf("Failed to create component manager: %v", err)
	}

	results, err := componentManager.InstallComponents([]string{}, "", false)
	if err != nil {
		t.Fatalf("Failed to install components: %v", err)
	}

	// Should only have bash component from default profile
	if len(results) != 1 {
		t.Fatalf("Expected 1 result for default profile, got %d", len(results))
	}

	if results[0].Component.ComponentName != "bash" {
		t.Errorf("Expected bash component, got %s", results[0].Component.ComponentName)
	}

	// Test with work profile
	results, err = componentManager.InstallComponents([]string{"work"}, "", false)
	if err != nil {
		t.Fatalf("Failed to install work components: %v", err)
	}

	// Should have both bash (from default) and work_tool (from work profile)
	if len(results) != 2 {
		t.Fatalf("Expected 2 results for work profile, got %d", len(results))
	}

	componentNames := make(map[string]bool)
	for _, result := range results {
		componentNames[result.Component.ComponentName] = true
	}

	if !componentNames["bash"] {
		t.Error("Expected bash component from default profile")
	}

	if !componentNames["work_tool"] {
		t.Error("Expected work_tool component from work profile")
	}
}
