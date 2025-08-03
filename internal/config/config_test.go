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
    bash:
      link:
        "bash/.bashrc": "~/.bashrc"
    git:
      install:
        brew: "brew install git"
        apt: "apt install -y git"
  work:
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
	defaultProfile, exists := cfg.Profiles["*"]
	if !exists {
		t.Error("Default profile '*' not found")
	}
	
	defaultComponents := defaultProfile.GetComponents()
	bashComponent, exists := defaultComponents["bash"]
	if !exists {
		t.Error("bash component not found in default profile")
	}
	
	if len(bashComponent.Link) != 1 {
		t.Errorf("Expected 1 link in bash component, got %d", len(bashComponent.Link))
	}
	
	// Test work profile
	workProfile, exists := cfg.Profiles["work"]
	if !exists {
		t.Error("work profile not found")
	}
	
	workComponents := workProfile.GetComponents()
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
    bash:
      link:
        "bash/.bashrc": "~/.bashrc"
`,
			wantError: false,
		},
		{
			name: "no profiles",
			config: `
other_field: value
`,
			wantError: true,
		},
		{
			name: "invalid OS restriction",
			config: `
profiles:
  "*":
    bash:
      install:
        brew: "brew install bash"
      os: ["windows"]
`,
			wantError: true,
		},
		{
			name: "component with no actions",
			config: `
profiles:
  "*":
    empty:
      os: ["mac"]
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