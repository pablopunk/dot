package config

import (
	"os"
	"path/filepath"
	"testing"
)

func TestRecursiveModules(t *testing.T) {
	// Create a temporary config file with recursive structure
	tmpDir := t.TempDir()
	configPath := filepath.Join(tmpDir, "dot.yaml")
	
	configContent := `
profiles:
  laptop:
    # Direct component (current behavior)
    spotify:
      install:
        brew: "brew install spotify"
        apt: "snap install spotify"
    
    # Recursive container
    cli:
      tools:
        fzf:
          install:
            brew: "brew install fzf"
            apt: "apt install -y fzf"
          link:
            "fzf/.fzfrc": "~/.fzfrc"
        ripgrep:
          install:
            brew: "brew install ripgrep"
            apt: "apt install -y ripgrep"
      editors:
        vim:
          link:
            "vim/.vimrc": "~/.vimrc"
            "vim/.vim/": "~/.vim/"
        nvim:
          install:
            brew: "brew install neovim"
            apt: "apt install -y neovim"
          link:
            "nvim/": "~/.config/nvim/"
`
	
	if err := os.WriteFile(configPath, []byte(configContent), 0644); err != nil {
		t.Fatalf("Failed to write test config: %v", err)
	}
	
	cfg, err := Load(configPath)
	if err != nil {
		t.Fatalf("Failed to load config: %v", err)
	}
	
	// Test that we have the laptop profile
	laptopProfile, exists := cfg.Profiles["laptop"]
	if !exists {
		t.Fatal("laptop profile not found")
	}
	
	// Extract all components from the recursive structure
	components := laptopProfile.GetComponents()
	
	// Expected components with their full paths
	expectedComponents := []string{
		"spotify",           // Direct component
		"cli.tools.fzf",     // Nested component
		"cli.tools.ripgrep", // Nested component
		"cli.editors.vim",   // Nested component
		"cli.editors.nvim",  // Nested component
	}
	
	if len(components) != len(expectedComponents) {
		t.Errorf("Expected %d components, got %d", len(expectedComponents), len(components))
	}
	
	// Check that all expected components exist
	for _, expectedPath := range expectedComponents {
		component, exists := components[expectedPath]
		if !exists {
			t.Errorf("Expected component %s not found", expectedPath)
			continue
		}
		
		// Verify component has the required properties
		switch expectedPath {
		case "spotify":
			if len(component.Install) != 2 {
				t.Errorf("spotify component should have 2 install commands, got %d", len(component.Install))
			}
		case "cli.tools.fzf":
			if len(component.Install) != 2 {
				t.Errorf("fzf component should have 2 install commands, got %d", len(component.Install))
			}
			if len(component.Link) != 1 {
				t.Errorf("fzf component should have 1 link, got %d", len(component.Link))
			}
		case "cli.tools.ripgrep":
			if len(component.Install) != 2 {
				t.Errorf("ripgrep component should have 2 install commands, got %d", len(component.Install))
			}
		case "cli.editors.vim":
			if len(component.Link) != 2 {
				t.Errorf("vim component should have 2 links, got %d", len(component.Link))
			}
		case "cli.editors.nvim":
			if len(component.Install) != 2 {
				t.Errorf("nvim component should have 2 install commands, got %d", len(component.Install))
			}
			if len(component.Link) != 1 {
				t.Errorf("nvim component should have 1 link, got %d", len(component.Link))
			}
		}
	}
}

func TestMixedRecursiveAndDirectComponents(t *testing.T) {
	tmpDir := t.TempDir()
	configPath := filepath.Join(tmpDir, "dot.yaml")
	
	configContent := `
profiles:
  "*":
    git:
      install:
        brew: "brew install git"
      link:
        "git/.gitconfig": "~/.gitconfig"
    
    development:
      languages:
        go:
          install:
            brew: "brew install go"
        rust:
          install:
            brew: "brew install rust"
          link:
            "rust/cargo.toml": "~/.cargo/config.toml"
      editors:
        code:
          install:
            brew: "brew install visual-studio-code"
`
	
	if err := os.WriteFile(configPath, []byte(configContent), 0644); err != nil {
		t.Fatalf("Failed to write test config: %v", err)
	}
	
	cfg, err := Load(configPath)
	if err != nil {
		t.Fatalf("Failed to load config: %v", err)
	}
	
	defaultProfile := cfg.Profiles["*"]
	components := defaultProfile.GetComponents()
	
	expectedComponents := map[string]bool{
		"git":                       true,
		"development.languages.go":  true,
		"development.languages.rust": true,
		"development.editors.code":  true,
	}
	
	if len(components) != len(expectedComponents) {
		t.Errorf("Expected %d components, got %d", len(expectedComponents), len(components))
	}
	
	for componentPath := range components {
		if !expectedComponents[componentPath] {
			t.Errorf("Unexpected component: %s", componentPath)
		}
	}
	
	// Verify specific component properties
	gitComponent := components["git"]
	if len(gitComponent.Install) != 1 || len(gitComponent.Link) != 1 {
		t.Error("git component should have 1 install and 1 link")
	}
	
	rustComponent := components["development.languages.rust"]
	if len(rustComponent.Install) != 1 || len(rustComponent.Link) != 1 {
		t.Error("rust component should have 1 install and 1 link")
	}
}

func TestEmptyContainers(t *testing.T) {
	tmpDir := t.TempDir()
	configPath := filepath.Join(tmpDir, "dot.yaml")
	
	configContent := `
profiles:
  test:
    valid:
      install:
        brew: "brew install something"
    
    # This should be treated as an empty container and not cause issues
    empty_container:
      nested_empty: {}
`
	
	if err := os.WriteFile(configPath, []byte(configContent), 0644); err != nil {
		t.Fatalf("Failed to write test config: %v", err)
	}
	
	cfg, err := Load(configPath)
	if err != nil {
		t.Fatalf("Failed to load config: %v", err)
	}
	
	testProfile := cfg.Profiles["test"]
	components := testProfile.GetComponents()
	
	// Should only have the valid component, empty containers should be ignored
	if len(components) != 1 {
		t.Errorf("Expected 1 component, got %d", len(components))
	}
	
	if _, exists := components["valid"]; !exists {
		t.Error("valid component not found")
	}
}