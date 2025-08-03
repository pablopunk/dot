package profile

import (
	"testing"

	"github.com/pablopunk/dot/internal/config"
)

func createTestConfig() *config.Config {
	return &config.Config{
		Profiles: map[string]config.Profile{
			"*": {
				"bash": config.Component{
					Link: map[string]string{
						"bash/.bashrc": "~/.bashrc",
					},
				},
				"git": config.Component{
					Install: map[string]string{
						"brew": "brew install git",
						"apt":  "apt install -y git",
					},
				},
			},
			"work": {
				"vpn": config.Component{
					Install: map[string]string{
						"brew": "brew install --cask viscosity",
					},
					OS: []string{"mac"},
				},
				"docker": config.Component{
					Install: map[string]string{
						"apt": "apt install -y docker.io",
					},
					OS: []string{"linux"},
				},
			},
			"laptop": {
				"battery": config.Component{
					Install: map[string]string{
						"brew": "brew install --cask battery-guardian",
					},
					OS: []string{"mac"},
				},
			},
		},
	}
}

func TestNewManager(t *testing.T) {
	cfg := createTestConfig()
	manager := NewManager(cfg)

	if manager.config != cfg {
		t.Error("Manager config not set correctly")
	}

	if manager.currentOS == "" {
		t.Error("Manager currentOS not set")
	}
}

func TestGetActiveComponents(t *testing.T) {
	cfg := createTestConfig()
	manager := NewManager(cfg)

	tests := []struct {
		name           string
		activeProfiles []string
		fuzzySearch    string
		wantCount      int
		wantComponents []string
	}{
		{
			name:           "default profile only",
			activeProfiles: []string{},
			fuzzySearch:    "",
			wantCount:      2,
			wantComponents: []string{"bash", "git"},
		},
		{
			name:           "work profile",
			activeProfiles: []string{"work"},
			fuzzySearch:    "",
			wantCount:      3, // 2 from default + 1 from work (OS dependent)
		},
		{
			name:           "fuzzy search for 'git'",
			activeProfiles: []string{},
			fuzzySearch:    "git",
			wantCount:      1,
			wantComponents: []string{"git"},
		},
		{
			name:           "fuzzy search for 'ba'",
			activeProfiles: []string{},
			fuzzySearch:    "ba",
			wantCount:      1,
			wantComponents: []string{"bash"},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			components, err := manager.GetActiveComponents(tt.activeProfiles, tt.fuzzySearch)
			if err != nil {
				t.Fatalf("GetActiveComponents() error = %v", err)
			}

			if tt.wantCount > 0 && len(components) != tt.wantCount {
				t.Errorf("GetActiveComponents() count = %v, want %v", len(components), tt.wantCount)
			}

			if len(tt.wantComponents) > 0 {
				found := make(map[string]bool)
				for _, comp := range components {
					found[comp.ComponentName] = true
				}

				for _, wantComp := range tt.wantComponents {
					if !found[wantComp] {
						t.Errorf("Expected component %s not found", wantComp)
					}
				}
			}
		})
	}
}

func TestListProfiles(t *testing.T) {
	cfg := createTestConfig()
	manager := NewManager(cfg)

	profiles := manager.ListProfiles()

	if len(profiles) != 3 {
		t.Errorf("ListProfiles() count = %v, want 3", len(profiles))
	}

	expectedProfiles := map[string]bool{
		"*":      true,
		"work":   true,
		"laptop": true,
	}

	for _, profile := range profiles {
		if !expectedProfiles[profile] {
			t.Errorf("Unexpected profile: %s", profile)
		}
	}
}

func TestProfileExists(t *testing.T) {
	cfg := createTestConfig()
	manager := NewManager(cfg)

	tests := []struct {
		profile string
		want    bool
	}{
		{"*", true},
		{"work", true},
		{"laptop", true},
		{"nonexistent", false},
		{"", false},
	}

	for _, tt := range tests {
		t.Run(tt.profile, func(t *testing.T) {
			if got := manager.ProfileExists(tt.profile); got != tt.want {
				t.Errorf("ProfileExists(%s) = %v, want %v", tt.profile, got, tt.want)
			}
		})
	}
}

func TestMatchesFuzzySearch(t *testing.T) {
	cfg := createTestConfig()
	manager := NewManager(cfg)

	tests := []struct {
		name          string
		componentName string
		search        string
		want          bool
	}{
		{"exact match", "git", "git", true},
		{"contains match", "bash", "as", true},
		{"case insensitive", "Git", "git", true},
		{"fuzzy match", "docker", "dkr", true},
		{"fuzzy match partial", "battery", "bty", true},
		{"no match", "git", "xyz", false},
		{"empty search matches all", "anything", "", true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := manager.matchesFuzzySearch(tt.componentName, tt.search); got != tt.want {
				t.Errorf("matchesFuzzySearch(%s, %s) = %v, want %v", tt.componentName, tt.search, got, tt.want)
			}
		})
	}
}

func TestValidateProfiles(t *testing.T) {
	cfg := createTestConfig()
	manager := NewManager(cfg)

	tests := []struct {
		name     string
		profiles []string
		wantErr  bool
	}{
		{"valid profiles", []string{"*", "work"}, false},
		{"invalid profile", []string{"nonexistent"}, true},
		{"mixed valid and invalid", []string{"work", "nonexistent"}, true},
		{"empty list", []string{}, false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := manager.ValidateProfiles(tt.profiles)
			if (err != nil) != tt.wantErr {
				t.Errorf("ValidateProfiles() error = %v, wantErr %v", err, tt.wantErr)
			}
		})
	}
}

func TestComponentInfoFullName(t *testing.T) {
	comp := ComponentInfo{
		ProfileName:   "work",
		ComponentName: "docker",
	}

	want := "work.docker"
	if got := comp.FullName(); got != want {
		t.Errorf("ComponentInfo.FullName() = %v, want %v", got, want)
	}
}
