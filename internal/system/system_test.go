package system

import (
	"os"
	"runtime"
	"testing"
)

func TestDetectOS(t *testing.T) {
	os := DetectOS()
	if os == "" {
		t.Error("DetectOS() returned empty string")
	}
	
	// Should return one of the supported OS names
	validOSes := map[string]bool{
		"darwin":  true,
		"linux":   true,
		"windows": true,
	}
	
	if !validOSes[os] {
		t.Errorf("DetectOS() returned unexpected OS: %s", os)
	}
}

func TestIsMacOS(t *testing.T) {
	result := IsMacOS()
	// Just check that it returns a boolean, can't test exact value since it depends on runtime
	_ = result
}

func TestIsLinux(t *testing.T) {
	result := IsLinux()
	// Just check that it returns a boolean, can't test exact value since it depends on runtime
	_ = result
}

func TestDiscoverPackageManagers(t *testing.T) {
	managers := DiscoverPackageManagers()
	
	// Should return a map with expected package managers
	expectedManagers := []string{"brew", "apt", "yum", "dnf", "pacman", "snap", "pip", "pip3", "npm", "cargo", "go"}
	
	for _, expected := range expectedManagers {
		manager, exists := managers[expected]
		if !exists {
			t.Errorf("Expected package manager %s not found", expected)
		}
		
		if manager.Name != expected {
			t.Errorf("Package manager name mismatch: expected %s, got %s", expected, manager.Name)
		}
	}
}

func TestGetFirstAvailablePackageManager(t *testing.T) {
	// Mock package managers
	managers := map[string]PackageManager{
		"brew": {Name: "brew", Available: true, Path: "/usr/local/bin/brew"},
		"apt":  {Name: "apt", Available: false, Path: ""},
		"npm":  {Name: "npm", Available: true, Path: "/usr/bin/npm"},
	}
	
	tests := []struct {
		name         string
		installCmds  map[string]string
		wantManager  string
		wantCommand  string
		wantAvailable bool
	}{
		{
			name: "prefers brew over npm",
			installCmds: map[string]string{
				"npm":  "npm install -g something",
				"brew": "brew install something",
			},
			wantManager:   "brew",
			wantCommand:   "brew install something",
			wantAvailable: true,
		},
		{
			name: "uses npm when brew not available",
			installCmds: map[string]string{
				"npm": "npm install -g something",
				"apt": "apt install something",
			},
			wantManager:   "npm",
			wantCommand:   "npm install -g something",
			wantAvailable: true,
		},
		{
			name: "returns false when no managers available",
			installCmds: map[string]string{
				"apt": "apt install something",
				"yum": "yum install something",
			},
			wantManager:   "",
			wantCommand:   "",
			wantAvailable: false,
		},
	}
	
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			gotManager, gotCommand, gotAvailable := GetFirstAvailablePackageManager(tt.installCmds, managers)
			
			if gotManager != tt.wantManager {
				t.Errorf("GetFirstAvailablePackageManager() manager = %v, want %v", gotManager, tt.wantManager)
			}
			
			if gotCommand != tt.wantCommand {
				t.Errorf("GetFirstAvailablePackageManager() command = %v, want %v", gotCommand, tt.wantCommand)
			}
			
			if gotAvailable != tt.wantAvailable {
				t.Errorf("GetFirstAvailablePackageManager() available = %v, want %v", gotAvailable, tt.wantAvailable)
			}
		})
	}
}

func TestNormalizeOSName(t *testing.T) {
	tests := []struct {
		input string
		want  string
	}{
		{"mac", "darwin"},
		{"Mac", "darwin"},
		{"macOS", "darwin"},
		{"osx", "darwin"},
		{"darwin", "darwin"},
		{"linux", "linux"},
		{"Linux", "linux"},
		{"ubuntu", "linux"},
		{"Ubuntu", "linux"},
		{"debian", "linux"},
		{"fedora", "linux"},
		{"centos", "linux"},
		{"rhel", "linux"},
		{"arch", "linux"},
		{"manjaro", "linux"},
		{"windows", "windows"},
		{"unknown", "unknown"},
	}
	
	for _, tt := range tests {
		t.Run(tt.input, func(t *testing.T) {
			if got := NormalizeOSName(tt.input); got != tt.want {
				t.Errorf("NormalizeOSName(%s) = %v, want %v", tt.input, got, tt.want)
			}
		})
	}
}

func TestPackageManagerPriority(t *testing.T) {
	tests := []struct {
		name        string
		available   []string
		installCmds map[string]string
		expected    string
	}{
		{
			name:      "brew has highest priority among multiple",
			available: []string{"npm", "pip", "brew", "apt"},
			installCmds: map[string]string{
				"brew": "brew install test",
				"npm":  "npm install test",
				"pip":  "pip install test",
				"apt":  "apt install test",
			},
			expected: "brew",
		},
		{
			name:      "apt preferred over other linux managers",
			available: []string{"yum", "dnf", "apt", "pacman"},
			installCmds: map[string]string{
				"apt":    "apt install test",
				"yum":    "yum install test",
				"dnf":    "dnf install test", 
				"pacman": "pacman -S test",
			},
			expected: "apt",
		},
		{
			name:      "pip preferred over pip3",
			available: []string{"pip3", "pip"},
			installCmds: map[string]string{
				"pip":  "pip install test",
				"pip3": "pip3 install test",
			},
			expected: "pip",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Create mock package managers
			managers := make(map[string]PackageManager)
			for _, name := range tt.available {
				managers[name] = PackageManager{
					Name:      name,
					Available: true,
					Path:      "/usr/bin/" + name,
				}
			}

			gotManager, _, gotAvailable := GetFirstAvailablePackageManager(tt.installCmds, managers)
			
			if !gotAvailable {
				t.Errorf("Expected to find available package manager")
			}
			
			if gotManager != tt.expected {
				t.Errorf("GetFirstAvailablePackageManager() = %v, want %v", gotManager, tt.expected)
			}
		})
	}
}

func TestPackageManagerDiscovery(t *testing.T) {
	managers := DiscoverPackageManagers()

	expectedManagers := []string{"brew", "apt", "yum", "dnf", "pacman", "snap", "pip", "pip3", "npm", "cargo", "go"}

	for _, expectedName := range expectedManagers {
		manager, exists := managers[expectedName]
		if !exists {
			t.Errorf("Expected package manager %s not found", expectedName)
			continue
		}

		if manager.Name != expectedName {
			t.Errorf("Package manager name mismatch: expected %s, got %s", expectedName, manager.Name)
		}

		// Test that available managers have paths
		if manager.Available && manager.Path == "" {
			t.Errorf("Available package manager %s should have non-empty path", expectedName)
		}
	}
}

func TestOSDetectionConsistency(t *testing.T) {
	// Test that our OS detection is consistent with Go's runtime
	detectedOS := DetectOS()
	runtimeOS := runtime.GOOS

	switch runtimeOS {
	case "darwin":
		if detectedOS != "darwin" {
			t.Errorf("Expected darwin for macOS, got %s", detectedOS)
		}
		if !IsMacOS() {
			t.Error("IsMacOS() should return true on macOS")
		}
		if IsLinux() {
			t.Error("IsLinux() should return false on macOS")
		}
	case "linux":
		if detectedOS != "linux" {
			t.Errorf("Expected linux, got %s", detectedOS)
		}
		if IsMacOS() {
			t.Error("IsMacOS() should return false on Linux")
		}
		if !IsLinux() {
			t.Error("IsLinux() should return true on Linux")
		}
	case "windows":
		if detectedOS != "windows" {
			t.Errorf("Expected windows, got %s", detectedOS)
		}
		if IsMacOS() {
			t.Error("IsMacOS() should return false on Windows")
		}
		if IsLinux() {
			t.Error("IsLinux() should return false on Windows")
		}
	}
}

func TestGetFirstAvailablePackageManagerEdgeCases(t *testing.T) {
	tests := []struct {
		name        string
		installCmds map[string]string
		managers    map[string]PackageManager
		wantManager string
		wantAvailable bool
	}{
		{
			name:        "empty install commands",
			installCmds: map[string]string{},
			managers: map[string]PackageManager{
				"brew": {Name: "brew", Available: true, Path: "/usr/bin/brew"},
			},
			wantManager:   "",
			wantAvailable: false,
		},
		{
			name: "empty managers",
			installCmds: map[string]string{
				"brew": "brew install test",
			},
			managers:      map[string]PackageManager{},
			wantManager:   "",
			wantAvailable: false,
		},
		{
			name: "command not in managers",
			installCmds: map[string]string{
				"unknown": "unknown install test",
			},
			managers: map[string]PackageManager{
				"brew": {Name: "brew", Available: true, Path: "/usr/bin/brew"},
			},
			wantManager:   "",
			wantAvailable: false,
		},
		{
			name: "manager not available",
			installCmds: map[string]string{
				"brew": "brew install test",
			},
			managers: map[string]PackageManager{
				"brew": {Name: "brew", Available: false, Path: ""},
			},
			wantManager:   "",
			wantAvailable: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			gotManager, _, gotAvailable := GetFirstAvailablePackageManager(tt.installCmds, tt.managers)
			
			if gotManager != tt.wantManager {
				t.Errorf("GetFirstAvailablePackageManager() manager = %v, want %v", gotManager, tt.wantManager)
			}
			
			if gotAvailable != tt.wantAvailable {
				t.Errorf("GetFirstAvailablePackageManager() available = %v, want %v", gotAvailable, tt.wantAvailable)
			}
		})
	}
}

func TestDefaultsManager(t *testing.T) {
	tmpDir := t.TempDir()
	
	manager := NewDefaultsManager(tmpDir, false, false)
	if manager == nil {
		t.Fatal("NewDefaultsManager returned nil")
	}

	// Test with dry run
	dryManager := NewDefaultsManager(tmpDir, true, false)
	if dryManager == nil {
		t.Fatal("NewDefaultsManager with dry run returned nil")
	}

	// Test with verbose
	verboseManager := NewDefaultsManager(tmpDir, false, true)
	if verboseManager == nil {
		t.Fatal("NewDefaultsManager with verbose returned nil")
	}
}

func TestDefaultsManagerCompareDefaults(t *testing.T) {
	tmpDir := t.TempDir()
	manager := NewDefaultsManager(tmpDir, false, false)

	// Test with empty defaults
	results, err := manager.CompareDefaults(map[string]string{})
	if err != nil {
		t.Errorf("CompareDefaults() with empty defaults error = %v", err)
	}
	
	if len(results) != 0 {
		t.Errorf("CompareDefaults() with empty defaults should return 0 results, got %d", len(results))
	}

	// Test with sample defaults
	sampleDefaults := map[string]string{
		"com.example.test": "~/test.plist",
	}

	results, err = manager.CompareDefaults(sampleDefaults)
	if err != nil {
		t.Errorf("CompareDefaults() error = %v", err)
	}
	
	// Should have at least one result for the domain
	if len(results) == 0 {
		t.Error("CompareDefaults() should return at least one result")
	}
}

func TestDefaultsManagerExportImport(t *testing.T) {
	tmpDir := t.TempDir()
	manager := NewDefaultsManager(tmpDir, false, false)

	// Test ExportDefaults
	sampleDefaults := map[string]string{
		"com.example.test": "~/test.plist",
	}
	
	results, err := manager.ExportDefaults(sampleDefaults)
	if err != nil {
		t.Errorf("ExportDefaults() error = %v", err)
	}
	
	if len(results) == 0 {
		t.Error("ExportDefaults() should return at least one result")
	}

	// Test ImportDefaults
	results, err = manager.ImportDefaults(sampleDefaults)
	if err != nil {
		t.Errorf("ImportDefaults() error = %v", err)
	}
	
	if len(results) == 0 {
		t.Error("ImportDefaults() should return at least one result")
	}
}

func TestPackageManagerAvailability(t *testing.T) {
	managers := DiscoverPackageManagers()
	
	// Test that at least one common package manager is detected
	// This will vary by system, but at least one should typically be available
	anyAvailable := false
	for _, manager := range managers {
		if manager.Available {
			anyAvailable = true
			
			// If available, path should not be empty
			if manager.Path == "" {
				t.Errorf("Available package manager %s has empty path", manager.Name)
			}
			
			// Path should exist
			if _, err := os.Stat(manager.Path); os.IsNotExist(err) {
				t.Errorf("Package manager %s path %s does not exist", manager.Name, manager.Path)
			}
		}
	}
	
	// This test might be too strict for CI environments, so just log for now
	if !anyAvailable {
		t.Logf("No package managers detected as available (this might be expected in CI)")
	}
}

func TestNormalizeOSNameEdgeCases(t *testing.T) {
	tests := []struct {
		input string
		want  string
	}{
		{"", ""},
		{"WINDOWS", "windows"},
		{"Windows 10", "windows"},
		{"macOS Monterey", "darwin"},
		{"Ubuntu 20.04", "linux"},
		{"Red Hat Enterprise Linux", "linux"},
		{"RANDOM_OS", "random_os"},
		{"123", "123"},
		{"os-with-dashes", "os-with-dashes"},
		{"os_with_underscores", "os_with_underscores"},
	}
	
	for _, tt := range tests {
		t.Run(tt.input, func(t *testing.T) {
			if got := NormalizeOSName(tt.input); got != tt.want {
				t.Errorf("NormalizeOSName(%s) = %v, want %v", tt.input, got, tt.want)
			}
		})
	}
}