package config

import (
	"os"
	"path/filepath"
	"testing"
)

func TestLoadConfig(t *testing.T) {
	// Create a temporary config file
	tmpDir := t.TempDir()
	configPath := filepath.Join(tmpDir, "dot.yaml")

	configContent := `
profiles:
  "*":
    - bash
    - git
  work:
    - vpn
    - docker

config:
  bash:
    link:
      "bash/.bashrc": "~/.bashrc"
  git:
    install:
      brew: "brew install git"
      apt: "apt install -y git"
  vpn:
    install:
      brew: "brew install --cask viscosity"
    os: ["mac"]
  docker:
    install:
      apt: "apt install -y docker.io"
    os: ["linux"]
`

	if err := os.WriteFile(configPath, []byte(configContent), 0644); err != nil {
		t.Fatalf("Failed to write test config: %v", err)
	}

	cfg, err := Load(configPath)
	if err != nil {
		t.Fatalf("Failed to load config: %v", err)
	}

	// Test profiles exist
	if len(cfg.Profiles) != 2 {
		t.Errorf("Expected 2 profiles, got %d", len(cfg.Profiles))
	}

	// Test default profile
	defaultTools, exists := cfg.Profiles["*"]
	if !exists {
		t.Error("Default profile '*' not found")
	}

	if len(defaultTools) != 2 {
		t.Errorf("Expected 2 tools in default profile, got %d", len(defaultTools))
	}

	// Test default profile expands to components
	defaultComponents, err := cfg.GetComponentsForProfileTools("*")
	if err != nil {
		t.Fatalf("Failed to get default profile components: %v", err)
	}

	bashComponent, exists := defaultComponents["bash"]
	if !exists {
		t.Error("bash component not found in default profile")
	}

	if len(bashComponent.Link) != 1 {
		t.Errorf("Expected 1 link in bash component, got %d", len(bashComponent.Link))
	}

	// Test work profile
	workTools, exists := cfg.Profiles["work"]
	if !exists {
		t.Error("work profile not found")
	}

	if len(workTools) != 2 {
		t.Errorf("Expected 2 tools in work profile, got %d", len(workTools))
	}

	workComponents, err := cfg.GetComponentsForProfileTools("work")
	if err != nil {
		t.Fatalf("Failed to get work profile components: %v", err)
	}

	vpnComponent, exists := workComponents["vpn"]
	if !exists {
		t.Error("vpn component not found in work profile")
	}

	if len(vpnComponent.OS) != 1 || vpnComponent.OS[0] != "mac" {
		t.Errorf("Expected vpn component to have OS restriction 'mac', got %v", vpnComponent.OS)
	}
}

func TestConfigValidation(t *testing.T) {
	tests := []struct {
		name      string
		config    string
		wantError bool
	}{
		{
			name: "valid config",
			config: `
profiles:
  "*":
    - bash
config:
  bash:
    link:
      "bash/.bashrc": "~/.bashrc"
`,
			wantError: false,
		},
		{
			name: "no profiles",
			config: `
config:
  bash:
    link:
      "bash/.bashrc": "~/.bashrc"
`,
			wantError: true,
		},
		{
			name: "no config",
			config: `
profiles:
  "*":
    - bash
`,
			wantError: true,
		},
		{
			name: "invalid OS restriction",
			config: `
profiles:
  "*":
    - bash
config:
  bash:
    install:
      brew: "brew install bash"
    os: ["windows"]
`,
			wantError: true,
		},
		{
			name: "tool with no actions (invalid)",
			config: `
profiles:
  "*":
    - invalid-tool
config:
  invalid-tool:
    os: ["mac"]
`,
			wantError: true,
		},
		{
			name: "nested config container (valid)",
			config: `
profiles:
  "*":
    - apps
config:
  apps:
    1password:
      install:
        brew: "brew install 1password"
`,
			wantError: false,
		},
		{
			name: "tool referenced but not in config",
			config: `
profiles:
  "*":
    - missing
config:
  bash:
    install:
      brew: "brew install bash"
`,
			wantError: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tmpDir := t.TempDir()
			configPath := filepath.Join(tmpDir, "dot.yaml")

			if err := os.WriteFile(configPath, []byte(tt.config), 0644); err != nil {
				t.Fatalf("Failed to write test config: %v", err)
			}

			_, err := Load(configPath)
			if (err != nil) != tt.wantError {
				t.Errorf("Load() error = %v, wantError %v", err, tt.wantError)
			}
		})
	}
}

func TestComponentMatchesOS(t *testing.T) {
	tests := []struct {
		name      string
		component Component
		currentOS string
		want      bool
	}{
		{
			name:      "no OS restriction",
			component: Component{},
			currentOS: "darwin",
			want:      true,
		},
		{
			name:      "matches darwin",
			component: Component{OS: []string{"darwin"}},
			currentOS: "darwin",
			want:      true,
		},
		{
			name:      "matches mac as darwin",
			component: Component{OS: []string{"mac"}},
			currentOS: "darwin",
			want:      true,
		},
		{
			name:      "matches linux",
			component: Component{OS: []string{"linux"}},
			currentOS: "linux",
			want:      true,
		},
		{
			name:      "doesn't match different OS",
			component: Component{OS: []string{"linux"}},
			currentOS: "darwin",
			want:      false,
		},
		{
			name:      "matches one of multiple OS",
			component: Component{OS: []string{"linux", "darwin"}},
			currentOS: "darwin",
			want:      true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := tt.component.MatchesOS(tt.currentOS); got != tt.want {
				t.Errorf("Component.MatchesOS() = %v, want %v", got, tt.want)
			}
		})
	}
}

func TestNestedConfigContainerExpansion(t *testing.T) {
	tmpDir := t.TempDir()
	configPath := filepath.Join(tmpDir, "dot.yaml")

	configContent := `
profiles:
  "*":
    - cli
  gui:
    - apps

config:
  cli:
    bash:
      link:
        "bash/.bashrc": "~/.bashrc"
    git:
      install:
        brew: "brew install git"

  apps:
    1password:
      install:
        brew: "brew install 1password"
    slack:
      install:
        brew: "brew install --cask slack"
    chrome:
      install:
        brew: "brew install --cask google-chrome"
`

	if err := os.WriteFile(configPath, []byte(configContent), 0644); err != nil {
		t.Fatalf("Failed to write test config: %v", err)
	}

	cfg, err := Load(configPath)
	if err != nil {
		t.Fatalf("Failed to load config: %v", err)
	}

	// Test default profile expands cli container to bash and git
	defaultComponents, err := cfg.GetComponentsForProfileTools("*")
	if err != nil {
		t.Fatalf("Failed to get default profile components: %v", err)
	}

	expectedDefault := map[string]bool{"bash": true, "git": true}
	if len(defaultComponents) != len(expectedDefault) {
		t.Errorf("Expected %d tools in default profile, got %d", len(expectedDefault), len(defaultComponents))
	}

	for toolName := range defaultComponents {
		if !expectedDefault[toolName] {
			t.Errorf("Unexpected tool '%s' in default profile", toolName)
		}
		delete(expectedDefault, toolName)
	}

	for toolName := range expectedDefault {
		t.Errorf("Missing expected tool '%s' in default profile", toolName)
	}

	// Test gui profile expands apps container to 1password, slack, chrome
	guiComponents, err := cfg.GetComponentsForProfileTools("gui")
	if err != nil {
		t.Fatalf("Failed to get gui profile components: %v", err)
	}

	expectedGUI := map[string]bool{"1password": true, "slack": true, "chrome": true}
	if len(guiComponents) != len(expectedGUI) {
		t.Errorf("Expected %d tools in gui profile, got %d", len(expectedGUI), len(guiComponents))
	}

	for toolName := range guiComponents {
		if !expectedGUI[toolName] {
			t.Errorf("Unexpected tool '%s' in gui profile", toolName)
		}
		delete(expectedGUI, toolName)
	}

	for toolName := range expectedGUI {
		t.Errorf("Missing expected tool '%s' in gui profile", toolName)
	}
}
