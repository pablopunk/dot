package link

import (
	"os"
	"path/filepath"
	"testing"
)

func TestNewManager(t *testing.T) {
	baseDir := "/test/base"
	manager := NewManager(baseDir, true, false)

	if manager.baseDir != baseDir {
		t.Errorf("Manager baseDir = %v, want %v", manager.baseDir, baseDir)
	}

	if !manager.dryRun {
		t.Error("Manager dryRun should be true")
	}

	if manager.verbose {
		t.Error("Manager verbose should be false")
	}
}

func TestCreateLinks(t *testing.T) {
	// Create temporary directories for testing
	tmpDir := t.TempDir()
	baseDir := filepath.Join(tmpDir, "dotfiles")
	homeDir := filepath.Join(tmpDir, "home")

	// Create source files
	if err := os.MkdirAll(filepath.Join(baseDir, "bash"), 0755); err != nil {
		t.Fatalf("Failed to create source dir: %v", err)
	}

	sourceFile := filepath.Join(baseDir, "bash", ".bashrc")
	if err := os.WriteFile(sourceFile, []byte("echo 'test'"), 0644); err != nil {
		t.Fatalf("Failed to create source file: %v", err)
	}

	// Create home directory
	if err := os.MkdirAll(homeDir, 0755); err != nil {
		t.Fatalf("Failed to create home dir: %v", err)
	}

	manager := NewManager(baseDir, false, false)

	linkMap := map[string]string{
		"bash/.bashrc": filepath.Join(homeDir, ".bashrc"),
	}

	results, err := manager.CreateLinks(linkMap)
	if err != nil {
		t.Fatalf("CreateLinks() error = %v", err)
	}

	if len(results) != 1 {
		t.Fatalf("CreateLinks() results count = %v, want 1", len(results))
	}

	result := results[0]
	if result.Action != "created" {
		t.Errorf("Link action = %v, want 'created'", result.Action)
	}

	if result.Error != nil {
		t.Errorf("Link error = %v, want nil", result.Error)
	}

	// Verify symlink was created
	targetFile := filepath.Join(homeDir, ".bashrc")
	linkInfo, err := os.Lstat(targetFile)
	if err != nil {
		t.Fatalf("Failed to stat target file: %v", err)
	}

	if linkInfo.Mode()&os.ModeSymlink == 0 {
		t.Error("Target is not a symlink")
	}

	// Verify symlink points to correct source
	linkedPath, err := os.Readlink(targetFile)
	if err != nil {
		t.Fatalf("Failed to read symlink: %v", err)
	}

	expectedPath := filepath.Join(baseDir, "bash", ".bashrc")
	if linkedPath != expectedPath {
		t.Errorf("Symlink points to %v, want %v", linkedPath, expectedPath)
	}
}

func TestCreateLinksExistingCorrectLink(t *testing.T) {
	tmpDir := t.TempDir()
	baseDir := filepath.Join(tmpDir, "dotfiles")
	homeDir := filepath.Join(tmpDir, "home")

	// Create source file
	if err := os.MkdirAll(filepath.Join(baseDir, "bash"), 0755); err != nil {
		t.Fatalf("Failed to create source dir: %v", err)
	}

	sourceFile := filepath.Join(baseDir, "bash", ".bashrc")
	if err := os.WriteFile(sourceFile, []byte("echo 'test'"), 0644); err != nil {
		t.Fatalf("Failed to create source file: %v", err)
	}

	// Create home directory and existing correct symlink
	if err := os.MkdirAll(homeDir, 0755); err != nil {
		t.Fatalf("Failed to create home dir: %v", err)
	}

	targetFile := filepath.Join(homeDir, ".bashrc")
	if err := os.Symlink(sourceFile, targetFile); err != nil {
		t.Fatalf("Failed to create existing symlink: %v", err)
	}

	manager := NewManager(baseDir, false, false)

	linkMap := map[string]string{
		"bash/.bashrc": targetFile,
	}

	results, err := manager.CreateLinks(linkMap)
	if err != nil {
		t.Fatalf("CreateLinks() error = %v", err)
	}

	if len(results) != 1 {
		t.Fatalf("CreateLinks() results count = %v, want 1", len(results))
	}

	result := results[0]
	if result.Action != "exists" {
		t.Errorf("Link action = %v, want 'exists'", result.Action)
	}
}

func TestCreateLinksDryRun(t *testing.T) {
	tmpDir := t.TempDir()
	baseDir := filepath.Join(tmpDir, "dotfiles")
	homeDir := filepath.Join(tmpDir, "home")

	// Create source file
	if err := os.MkdirAll(filepath.Join(baseDir, "bash"), 0755); err != nil {
		t.Fatalf("Failed to create source dir: %v", err)
	}

	sourceFile := filepath.Join(baseDir, "bash", ".bashrc")
	if err := os.WriteFile(sourceFile, []byte("echo 'test'"), 0644); err != nil {
		t.Fatalf("Failed to create source file: %v", err)
	}

	// Create home directory
	if err := os.MkdirAll(homeDir, 0755); err != nil {
		t.Fatalf("Failed to create home dir: %v", err)
	}

	manager := NewManager(baseDir, true, false) // dry run enabled

	linkMap := map[string]string{
		"bash/.bashrc": filepath.Join(homeDir, ".bashrc"),
	}

	results, err := manager.CreateLinks(linkMap)
	if err != nil {
		t.Fatalf("CreateLinks() error = %v", err)
	}

	if len(results) != 1 {
		t.Fatalf("CreateLinks() results count = %v, want 1", len(results))
	}

	result := results[0]
	if result.Action != "would_create" {
		t.Errorf("Link action = %v, want 'would_create'", result.Action)
	}

	// Verify no symlink was actually created
	targetFile := filepath.Join(homeDir, ".bashrc")
	if _, err := os.Lstat(targetFile); !os.IsNotExist(err) {
		t.Error("Symlink should not exist in dry run mode")
	}
}

func TestRemoveLinks(t *testing.T) {
	tmpDir := t.TempDir()
	baseDir := filepath.Join(tmpDir, "dotfiles")
	homeDir := filepath.Join(tmpDir, "home")

	// Create source file
	if err := os.MkdirAll(filepath.Join(baseDir, "bash"), 0755); err != nil {
		t.Fatalf("Failed to create source dir: %v", err)
	}

	sourceFile := filepath.Join(baseDir, "bash", ".bashrc")
	if err := os.WriteFile(sourceFile, []byte("echo 'test'"), 0644); err != nil {
		t.Fatalf("Failed to create source file: %v", err)
	}

	// Create home directory and symlink
	if err := os.MkdirAll(homeDir, 0755); err != nil {
		t.Fatalf("Failed to create home dir: %v", err)
	}

	targetFile := filepath.Join(homeDir, ".bashrc")
	if err := os.Symlink(sourceFile, targetFile); err != nil {
		t.Fatalf("Failed to create symlink: %v", err)
	}

	manager := NewManager(baseDir, false, false)

	linkMap := map[string]string{
		"bash/.bashrc": targetFile,
	}

	results, err := manager.RemoveLinks(linkMap)
	if err != nil {
		t.Fatalf("RemoveLinks() error = %v", err)
	}

	if len(results) != 1 {
		t.Fatalf("RemoveLinks() results count = %v, want 1", len(results))
	}

	result := results[0]
	if result.Action != "removed" {
		t.Errorf("Link action = %v, want 'removed'", result.Action)
	}

	// Verify symlink was removed
	if _, err := os.Lstat(targetFile); !os.IsNotExist(err) {
		t.Error("Symlink should have been removed")
	}
}

func TestExpandPath(t *testing.T) {
	tests := []struct {
		name    string
		path    string
		wantErr bool
		checkFn func(string) bool
	}{
		{
			name:    "tilde expansion",
			path:    "~/test.txt",
			wantErr: false,
			checkFn: func(result string) bool {
				return result != "~/test.txt" && len(result) > len("~/test.txt")
			},
		},
		{
			name:    "absolute path unchanged",
			path:    "/absolute/path",
			wantErr: false,
			checkFn: func(result string) bool {
				return result == "/absolute/path"
			},
		},
		{
			name:    "relative path unchanged",
			path:    "relative/path",
			wantErr: false,
			checkFn: func(result string) bool {
				return result == "relative/path"
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result, err := expandPath(tt.path)
			if (err != nil) != tt.wantErr {
				t.Errorf("expandPath() error = %v, wantErr %v", err, tt.wantErr)
				return
			}

			if !tt.wantErr && !tt.checkFn(result) {
				t.Errorf("expandPath() result = %v does not meet check criteria", result)
			}
		})
	}
}

func TestLinkResultWasSuccessful(t *testing.T) {
	tests := []struct {
		name   string
		result LinkResult
		want   bool
	}{
		{
			name:   "created successfully",
			result: LinkResult{Action: "created", Error: nil},
			want:   true,
		},
		{
			name:   "exists successfully",
			result: LinkResult{Action: "exists", Error: nil},
			want:   true,
		},
		{
			name:   "removed successfully",
			result: LinkResult{Action: "removed", Error: nil},
			want:   true,
		},
		{
			name:   "error result",
			result: LinkResult{Action: "error", Error: os.ErrNotExist},
			want:   false,
		},
		{
			name:   "would_create",
			result: LinkResult{Action: "would_create", Error: nil},
			want:   true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := tt.result.WasSuccessful(); got != tt.want {
				t.Errorf("LinkResult.WasSuccessful() = %v, want %v", got, tt.want)
			}
		})
	}
}
