package state

import (
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/pablopunk/dot/internal/profile"
)

func TestNewManager(t *testing.T) {
	// Use temp directory for testing
	tmpDir := t.TempDir()
	originalHome := os.Getenv("HOME")
	os.Setenv("HOME", tmpDir)
	defer os.Setenv("HOME", originalHome)

	manager, err := NewManager()
	if err != nil {
		t.Fatalf("NewManager() error = %v", err)
	}

	expectedPath := filepath.Join(tmpDir, ".local", "state", "dot", "lock.yaml")
	if manager.lockFilePath != expectedPath {
		t.Errorf("NewManager() lockFilePath = %v, want %v", manager.lockFilePath, expectedPath)
	}

	// Verify lock file was created
	if _, err := os.Stat(expectedPath); os.IsNotExist(err) {
		t.Error("Lock file should have been created")
	}
}

func TestLoadAndSave(t *testing.T) {
	tmpDir := t.TempDir()
	manager := &Manager{
		lockFilePath: filepath.Join(tmpDir, "lock.yaml"),
	}

	// Initial load should create a new lock file
	err := manager.Load()
	if err != nil {
		t.Fatalf("Load() error = %v", err)
	}

	if manager.lockFile.Version != LockFileVersion {
		t.Errorf("Load() version = %v, want %v", manager.lockFile.Version, LockFileVersion)
	}

	// Test save
	manager.lockFile.ActiveProfiles = []string{"work", "laptop"}
	err = manager.Save()
	if err != nil {
		t.Fatalf("Save() error = %v", err)
	}

	// Load again and verify persistence
	manager2 := &Manager{
		lockFilePath: manager.lockFilePath,
	}
	err = manager2.Load()
	if err != nil {
		t.Fatalf("Second Load() error = %v", err)
	}

	if len(manager2.lockFile.ActiveProfiles) != 2 {
		t.Errorf("Loaded ActiveProfiles length = %v, want 2", len(manager2.lockFile.ActiveProfiles))
	}
}

func TestComponentTracking(t *testing.T) {
	tmpDir := t.TempDir()
	manager := &Manager{
		lockFilePath: filepath.Join(tmpDir, "lock.yaml"),
		lockFile: &LockFile{
			Version:             LockFileVersion,
			LastUpdated:         time.Now(),
			ActiveProfiles:      []string{},
			InstalledComponents: make(map[string]ComponentState),
		},
	}

	component := profile.ComponentInfo{
		ProfileName:   "work",
		ComponentName: "git",
	}

	// Initially not installed
	if manager.IsComponentInstalled(component) {
		t.Error("Component should not be installed initially")
	}

	// Mark as installed
	links := map[string]string{"git/.gitconfig": "~/.gitconfig"}
	manager.MarkComponentInstalled(component, "brew", "brew install git", links)

	// Should now be installed
	if !manager.IsComponentInstalled(component) {
		t.Error("Component should be installed after marking")
	}

	// Verify state
	state, exists := manager.GetComponentState(component)
	if !exists {
		t.Error("Component state should exist")
	}

	if state.PackageManager != "brew" {
		t.Errorf("Component PackageManager = %v, want brew", state.PackageManager)
	}

	if state.InstallCommand != "brew install git" {
		t.Errorf("Component InstallCommand = %v, want 'brew install git'", state.InstallCommand)
	}

	// Test hooks
	if state.PostInstallRan {
		t.Error("PostInstallRan should be false initially")
	}

	manager.MarkPostInstallRan(component)
	state, _ = manager.GetComponentState(component)
	if !state.PostInstallRan {
		t.Error("PostInstallRan should be true after marking")
	}

	// Test removal
	manager.RemoveComponent(component)
	if manager.IsComponentInstalled(component) {
		t.Error("Component should not be installed after removal")
	}
}

func TestGetRemovedComponents(t *testing.T) {
	tmpDir := t.TempDir()
	manager := &Manager{
		lockFilePath: filepath.Join(tmpDir, "lock.yaml"),
		lockFile: &LockFile{
			Version:             LockFileVersion,
			LastUpdated:         time.Now(),
			ActiveProfiles:      []string{},
			InstalledComponents: make(map[string]ComponentState),
		},
	}

	// Add some installed components
	manager.lockFile.InstalledComponents["work.git"] = ComponentState{
		ProfileName:   "work",
		ComponentName: "git",
		InstalledAt:   time.Now(),
	}
	manager.lockFile.InstalledComponents["work.docker"] = ComponentState{
		ProfileName:   "work",
		ComponentName: "docker",
		InstalledAt:   time.Now(),
	}

	// Current components only include git
	currentComponents := []profile.ComponentInfo{
		{
			ProfileName:   "work",
			ComponentName: "git",
		},
	}

	// Should find docker as removed
	removed := manager.GetRemovedComponents(currentComponents)
	if len(removed) != 1 {
		t.Fatalf("GetRemovedComponents() count = %v, want 1", len(removed))
	}

	if removed[0].ComponentName != "docker" {
		t.Errorf("Removed component name = %v, want docker", removed[0].ComponentName)
	}
}

func TestHasChangedSince(t *testing.T) {
	tmpDir := t.TempDir()
	manager := &Manager{
		lockFilePath: filepath.Join(tmpDir, "lock.yaml"),
		lockFile: &LockFile{
			Version:             LockFileVersion,
			LastUpdated:         time.Now(),
			ActiveProfiles:      []string{},
			InstalledComponents: make(map[string]ComponentState),
		},
	}

	component := profile.ComponentInfo{
		ProfileName:   "work",
		ComponentName: "git",
	}

	// Not installed - should be changed
	links := map[string]string{"git/.gitconfig": "~/.gitconfig"}
	if !manager.HasChangedSince(component, links) {
		t.Error("HasChangedSince should return true for uninstalled component")
	}

	// Install with same links
	manager.MarkComponentInstalled(component, "brew", "brew install git", links)
	if manager.HasChangedSince(component, links) {
		t.Error("HasChangedSince should return false for unchanged component")
	}

	// Change links
	newLinks := map[string]string{
		"git/.gitconfig": "~/.gitconfig",
		"git/.gitignore": "~/.gitignore",
	}
	if !manager.HasChangedSince(component, newLinks) {
		t.Error("HasChangedSince should return true for changed links")
	}
}

func TestActiveProfiles(t *testing.T) {
	tmpDir := t.TempDir()
	manager := &Manager{
		lockFilePath: filepath.Join(tmpDir, "lock.yaml"),
		lockFile: &LockFile{
			Version:             LockFileVersion,
			LastUpdated:         time.Now(),
			ActiveProfiles:      []string{},
			InstalledComponents: make(map[string]ComponentState),
		},
	}

	// Initially empty
	profiles := manager.GetActiveProfiles()
	if len(profiles) != 0 {
		t.Errorf("GetActiveProfiles() initial count = %v, want 0", len(profiles))
	}

	// Set profiles
	testProfiles := []string{"work", "laptop"}
	manager.SetActiveProfiles(testProfiles)

	profiles = manager.GetActiveProfiles()
	if len(profiles) != 2 {
		t.Errorf("GetActiveProfiles() count = %v, want 2", len(profiles))
	}

	// Verify contents
	found := make(map[string]bool)
	for _, profile := range profiles {
		found[profile] = true
	}

	if !found["work"] || !found["laptop"] {
		t.Error("GetActiveProfiles() should contain work and laptop")
	}
}

func TestReset(t *testing.T) {
	tmpDir := t.TempDir()
	manager := &Manager{
		lockFilePath: filepath.Join(tmpDir, "lock.yaml"),
		lockFile: &LockFile{
			Version:        LockFileVersion,
			LastUpdated:    time.Now(),
			ActiveProfiles: []string{"work"},
			InstalledComponents: map[string]ComponentState{
				"work.git": {
					ProfileName:   "work",
					ComponentName: "git",
				},
			},
		},
	}

	// Reset
	err := manager.Reset()
	if err != nil {
		t.Fatalf("Reset() error = %v", err)
	}

	// Should be clean
	if len(manager.lockFile.ActiveProfiles) != 0 {
		t.Error("ActiveProfiles should be empty after reset")
	}

	if len(manager.lockFile.InstalledComponents) != 0 {
		t.Error("InstalledComponents should be empty after reset")
	}
}

func TestGetLockFilePath(t *testing.T) {
	path := "/test/path/lock.yaml"
	manager := &Manager{
		lockFilePath: path,
	}

	if manager.GetLockFilePath() != path {
		t.Errorf("GetLockFilePath() = %v, want %v", manager.GetLockFilePath(), path)
	}
}
