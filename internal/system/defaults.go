package system

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
)

type DefaultsManager struct {
	baseDir string
	dryRun  bool
	verbose bool
}

func NewDefaultsManager(baseDir string, dryRun, verbose bool) *DefaultsManager {
	return &DefaultsManager{
		baseDir: baseDir,
		dryRun:  dryRun,
		verbose: verbose,
	}
}

type DefaultsResult struct {
	AppID   string
	PlistPath string
	Action  string // "exported", "imported", "compared", "error", "skipped"
	Changed bool
	Error   error
}

func (dm *DefaultsManager) ExportDefaults(defaults map[string]string) ([]DefaultsResult, error) {
	if !IsMacOS() {
		return nil, fmt.Errorf("defaults operations are only supported on macOS")
	}
	
	var results []DefaultsResult
	
	for appID, plistPath := range defaults {
		result := dm.exportDefault(appID, plistPath)
		results = append(results, result)
	}
	
	return results, nil
}

func (dm *DefaultsManager) ImportDefaults(defaults map[string]string) ([]DefaultsResult, error) {
	if !IsMacOS() {
		return nil, fmt.Errorf("defaults operations are only supported on macOS")
	}
	
	var results []DefaultsResult
	
	for appID, plistPath := range defaults {
		result := dm.importDefault(appID, plistPath)
		results = append(results, result)
	}
	
	return results, nil
}

func (dm *DefaultsManager) CompareDefaults(defaults map[string]string) ([]DefaultsResult, error) {
	if !IsMacOS() {
		return nil, fmt.Errorf("defaults operations are only supported on macOS")
	}
	
	var results []DefaultsResult
	
	for appID, plistPath := range defaults {
		result := dm.compareDefault(appID, plistPath)
		results = append(results, result)
	}
	
	return results, nil
}

func (dm *DefaultsManager) exportDefault(appID, plistPath string) DefaultsResult {
	resolvedPath := dm.resolvePlistPath(plistPath)
	
	if dm.verbose {
		fmt.Printf("Exporting defaults for %s to %s\n", appID, resolvedPath)
	}
	
	if dm.dryRun {
		return DefaultsResult{
			AppID:     appID,
			PlistPath: resolvedPath,
			Action:    "would_export",
		}
	}
	
	// Create parent directory if it doesn't exist
	parentDir := filepath.Dir(resolvedPath)
	if err := os.MkdirAll(parentDir, 0755); err != nil {
		return DefaultsResult{
			AppID:     appID,
			PlistPath: resolvedPath,
			Action:    "error",
			Error:     fmt.Errorf("failed to create parent directory: %w", err),
		}
	}
	
	// Export defaults using the defaults command
	cmd := exec.Command("defaults", "export", appID, resolvedPath)
	output, err := cmd.CombinedOutput()
	
	if err != nil {
		return DefaultsResult{
			AppID:     appID,
			PlistPath: resolvedPath,
			Action:    "error",
			Error:     fmt.Errorf("defaults export failed: %w, output: %s", err, string(output)),
		}
	}
	
	return DefaultsResult{
		AppID:     appID,
		PlistPath: resolvedPath,
		Action:    "exported",
	}
}

func (dm *DefaultsManager) importDefault(appID, plistPath string) DefaultsResult {
	resolvedPath := dm.resolvePlistPath(plistPath)
	
	if dm.verbose {
		fmt.Printf("Importing defaults for %s from %s\n", appID, resolvedPath)
	}
	
	// Check if plist file exists
	if _, err := os.Stat(resolvedPath); os.IsNotExist(err) {
		return DefaultsResult{
			AppID:     appID,
			PlistPath: resolvedPath,
			Action:    "error",
			Error:     fmt.Errorf("plist file does not exist: %s", resolvedPath),
		}
	}
	
	if dm.dryRun {
		return DefaultsResult{
			AppID:     appID,
			PlistPath: resolvedPath,
			Action:    "would_import",
		}
	}
	
	// Import defaults using the defaults command
	cmd := exec.Command("defaults", "import", appID, resolvedPath)
	output, err := cmd.CombinedOutput()
	
	if err != nil {
		return DefaultsResult{
			AppID:     appID,
			PlistPath: resolvedPath,
			Action:    "error",
			Error:     fmt.Errorf("defaults import failed: %w, output: %s", err, string(output)),
		}
	}
	
	return DefaultsResult{
		AppID:     appID,
		PlistPath: resolvedPath,
		Action:    "imported",
	}
}

func (dm *DefaultsManager) compareDefault(appID, plistPath string) DefaultsResult {
	resolvedPath := dm.resolvePlistPath(plistPath)
	
	if dm.verbose {
		fmt.Printf("Comparing defaults for %s with %s\n", appID, resolvedPath)
	}
	
	// Check if plist file exists
	if _, err := os.Stat(resolvedPath); os.IsNotExist(err) {
		return DefaultsResult{
			AppID:     appID,
			PlistPath: resolvedPath,
			Action:    "error",
			Error:     fmt.Errorf("plist file does not exist: %s", resolvedPath),
		}
	}
	
	// Export current defaults to a temporary file
	tempFile, err := os.CreateTemp("", "dot-defaults-*.plist")
	if err != nil {
		return DefaultsResult{
			AppID:     appID,
			PlistPath: resolvedPath,
			Action:    "error",
			Error:     fmt.Errorf("failed to create temp file: %w", err),
		}
	}
	defer os.Remove(tempFile.Name())
	tempFile.Close()
	
	// Export current defaults
	cmd := exec.Command("defaults", "export", appID, tempFile.Name())
	if err := cmd.Run(); err != nil {
		return DefaultsResult{
			AppID:     appID,
			PlistPath: resolvedPath,
			Action:    "error",
			Error:     fmt.Errorf("failed to export current defaults: %w", err),
		}
	}
	
	// Compare files
	cmd = exec.Command("diff", "-q", resolvedPath, tempFile.Name())
	err = cmd.Run()
	
	changed := err != nil // diff returns non-zero exit code if files differ
	
	return DefaultsResult{
		AppID:     appID,
		PlistPath: resolvedPath,
		Action:    "compared",
		Changed:   changed,
	}
}

func (dm *DefaultsManager) resolvePlistPath(plistPath string) string {
	if filepath.IsAbs(plistPath) {
		return plistPath
	}
	return filepath.Join(dm.baseDir, plistPath)
}

func (r *DefaultsResult) String() string {
	switch r.Action {
	case "exported":
		return fmt.Sprintf("✓ Exported defaults for %s to %s", r.AppID, r.PlistPath)
	case "imported":
		return fmt.Sprintf("✓ Imported defaults for %s from %s", r.AppID, r.PlistPath)
	case "compared":
		if r.Changed {
			return fmt.Sprintf("⚠ Defaults for %s differ from %s", r.AppID, r.PlistPath)
		} else {
			return fmt.Sprintf("✓ Defaults for %s match %s", r.AppID, r.PlistPath)
		}
	case "would_export":
		return fmt.Sprintf("Would export defaults for %s to %s", r.AppID, r.PlistPath)
	case "would_import":
		return fmt.Sprintf("Would import defaults for %s from %s", r.AppID, r.PlistPath)
	case "skipped":
		return fmt.Sprintf("Skipped %s (not macOS)", r.AppID)
	case "error":
		return fmt.Sprintf("✗ Error with defaults for %s: %v", r.AppID, r.Error)
	default:
		return fmt.Sprintf("Unknown action %s for %s", r.Action, r.AppID)
	}
}

func (r *DefaultsResult) WasSuccessful() bool {
	return r.Error == nil && (r.Action == "exported" || r.Action == "imported" || r.Action == "compared")
}