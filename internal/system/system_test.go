package system

import (
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
	if !IsMacOS() {
		t.Skip("Skipping defaults test on non-macOS platform")
	}

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
	if !IsMacOS() {
		t.Skip("Skipping defaults test on non-macOS platform")
	}

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
