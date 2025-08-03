package link

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

type Manager struct {
	baseDir string
	dryRun  bool
	verbose bool
}

func NewManager(baseDir string, dryRun, verbose bool) *Manager {
	return &Manager{
		baseDir: baseDir,
		dryRun:  dryRun,
		verbose: verbose,
	}
}

type LinkResult struct {
	Source  string
	Target  string
	Action  string // "created", "exists", "skipped", "error"
	Error   error
}

func (m *Manager) CreateLinks(linkMap map[string]string) ([]LinkResult, error) {
	var results []LinkResult
	
	for source, target := range linkMap {
		result := m.createLink(source, target)
		results = append(results, result)
	}
	
	return results, nil
}

// NeedsLinking checks if any of the links in linkMap need to be created or updated
// Returns true if at least one link needs work, false if all links already exist correctly
func (m *Manager) NeedsLinking(linkMap map[string]string) bool {
	for source, target := range linkMap {
		if m.needsLinking(source, target) {
			return true
		}
	}
	return false
}

// needsLinking checks if a single link needs to be created or updated
func (m *Manager) needsLinking(source, target string) bool {
	// Resolve source path relative to base directory
	sourcePath := filepath.Join(m.baseDir, source)
	
	// Expand target path (handle ~ for home directory)
	expandedTarget, err := expandPath(target)
	if err != nil {
		return true // Error expanding path means we need to try linking
	}
	
	// Check if source exists
	if _, err := os.Stat(sourcePath); os.IsNotExist(err) {
		return true // Source doesn't exist, we'll need to handle this
	}
	
	// Check if target already exists and is the correct symlink
	if linkInfo, err := os.Lstat(expandedTarget); err == nil {
		if linkInfo.Mode()&os.ModeSymlink != 0 {
			// It's a symlink, check if it points to the right place
			currentTarget, err := os.Readlink(expandedTarget)
			if err == nil {
				// Resolve to absolute path for comparison
				absCurrentTarget, _ := filepath.Abs(currentTarget)
				absSourcePath, _ := filepath.Abs(sourcePath)
				
				if absCurrentTarget == absSourcePath {
					return false // Link already exists and points to correct location
				}
			}
		}
	}
	
	return true // Link needs to be created or updated
}

func (m *Manager) createLink(source, target string) LinkResult {
	// Resolve source path relative to base directory
	sourcePath := filepath.Join(m.baseDir, source)
	
	// Expand target path (handle ~ for home directory)
	expandedTarget, err := expandPath(target)
	if err != nil {
		return LinkResult{
			Source: source,
			Target: target,
			Action: "error",
			Error:  fmt.Errorf("failed to expand target path: %w", err),
		}
	}
	
	// Check if source exists
	if _, err := os.Stat(sourcePath); os.IsNotExist(err) {
		return LinkResult{
			Source: source,
			Target: expandedTarget,
			Action: "error",
			Error:  fmt.Errorf("source file does not exist: %s", sourcePath),
		}
	}
	
	// Check if target already exists and is the correct symlink
	if linkInfo, err := os.Lstat(expandedTarget); err == nil {
		if linkInfo.Mode()&os.ModeSymlink != 0 {
			// It's a symlink, check if it points to the right place
			currentTarget, err := os.Readlink(expandedTarget)
			if err == nil {
				// Resolve to absolute path for comparison
				absCurrentTarget, _ := filepath.Abs(currentTarget)
				absSourcePath, _ := filepath.Abs(sourcePath)
				
				if absCurrentTarget == absSourcePath {
					return LinkResult{
						Source: source,
						Target: expandedTarget,
						Action: "exists",
					}
				}
			}
		}
		
		// Target exists but is not the correct symlink
		if m.dryRun {
			return LinkResult{
				Source: source,
				Target: expandedTarget,
				Action: "would_replace",
			}
		}
		
		// Remove existing file/link
		if err := os.Remove(expandedTarget); err != nil {
			return LinkResult{
				Source: source,
				Target: expandedTarget,
				Action: "error",
				Error:  fmt.Errorf("failed to remove existing target: %w", err),
			}
		}
	}
	
	if m.dryRun {
		return LinkResult{
			Source: source,
			Target: expandedTarget,
			Action: "would_create",
		}
	}
	
	// Create parent directory if it doesn't exist
	parentDir := filepath.Dir(expandedTarget)
	if err := os.MkdirAll(parentDir, 0755); err != nil {
		return LinkResult{
			Source: source,
			Target: expandedTarget,
			Action: "error",
			Error:  fmt.Errorf("failed to create parent directory: %w", err),
		}
	}
	
	// Create the symlink
	if err := os.Symlink(sourcePath, expandedTarget); err != nil {
		return LinkResult{
			Source: source,
			Target: expandedTarget,
			Action: "error",
			Error:  fmt.Errorf("failed to create symlink: %w", err),
		}
	}
	
	return LinkResult{
		Source: source,
		Target: expandedTarget,
		Action: "created",
	}
}

func (m *Manager) RemoveLinks(linkMap map[string]string) ([]LinkResult, error) {
	var results []LinkResult
	
	for source, target := range linkMap {
		result := m.removeLink(source, target)
		results = append(results, result)
	}
	
	return results, nil
}

func (m *Manager) removeLink(source, target string) LinkResult {
	expandedTarget, err := expandPath(target)
	if err != nil {
		return LinkResult{
			Source: source,
			Target: target,
			Action: "error",
			Error:  fmt.Errorf("failed to expand target path: %w", err),
		}
	}
	
	// Check if target exists and is a symlink
	linkInfo, err := os.Lstat(expandedTarget)
	if os.IsNotExist(err) {
		return LinkResult{
			Source: source,
			Target: expandedTarget,
			Action: "not_exists",
		}
	}
	
	if err != nil {
		return LinkResult{
			Source: source,
			Target: expandedTarget,
			Action: "error",
			Error:  fmt.Errorf("failed to check target: %w", err),
		}
	}
	
	if linkInfo.Mode()&os.ModeSymlink == 0 {
		return LinkResult{
			Source: source,
			Target: expandedTarget,
			Action: "not_symlink",
		}
	}
	
	if m.dryRun {
		return LinkResult{
			Source: source,
			Target: expandedTarget,
			Action: "would_remove",
		}
	}
	
	if err := os.Remove(expandedTarget); err != nil {
		return LinkResult{
			Source: source,
			Target: expandedTarget,
			Action: "error",
			Error:  fmt.Errorf("failed to remove symlink: %w", err),
		}
	}
	
	return LinkResult{
		Source: source,
		Target: expandedTarget,
		Action: "removed",
	}
}

func expandPath(path string) (string, error) {
	if strings.HasPrefix(path, "~/") {
		homeDir, err := os.UserHomeDir()
		if err != nil {
			return "", err
		}
		return filepath.Join(homeDir, path[2:]), nil
	}
	return path, nil
}

func (r *LinkResult) WasSuccessful() bool {
	return r.Error == nil && (r.Action == "created" || r.Action == "exists" || r.Action == "removed" || r.Action == "would_create" || r.Action == "would_replace" || r.Action == "would_remove")
}

func (r *LinkResult) String() string {
	switch r.Action {
	case "created":
		return fmt.Sprintf("✓ Linked %s -> %s", r.Source, r.Target)
	case "exists":
		return fmt.Sprintf("✓ Link exists %s -> %s", r.Source, r.Target)
	case "removed":
		return fmt.Sprintf("✓ Removed link %s", r.Target)
	case "would_create":
		return fmt.Sprintf("Would link %s -> %s", r.Source, r.Target)
	case "would_replace":
		return fmt.Sprintf("Would replace %s -> %s", r.Source, r.Target)
	case "would_remove":
		return fmt.Sprintf("Would remove link %s", r.Target)
	case "not_exists":
		return fmt.Sprintf("Link does not exist %s", r.Target)
	case "not_symlink":
		return fmt.Sprintf("Target is not a symlink %s", r.Target)
	case "skipped":
		return fmt.Sprintf("Skipped %s -> %s", r.Source, r.Target)
	case "error":
		return fmt.Sprintf("✗ Error linking %s -> %s: %v", r.Source, r.Target, r.Error)
	default:
		return fmt.Sprintf("Unknown action %s for %s -> %s", r.Action, r.Source, r.Target)
	}
}