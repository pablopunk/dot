package component

import (
	"fmt"
	"strings"

	"github.com/pablopunk/dot/internal/config"
	"github.com/pablopunk/dot/internal/exec"
	"github.com/pablopunk/dot/internal/link"
	"github.com/pablopunk/dot/internal/profile"
	"github.com/pablopunk/dot/internal/state"
	"github.com/pablopunk/dot/internal/system"
	"github.com/pablopunk/dot/internal/ui"
)

type Manager struct {
	baseDir         string
	profileManager  *profile.Manager
	stateManager    *state.Manager
	linkManager     *link.Manager
	execManager     *exec.Manager
	defaultsManager *system.DefaultsManager
	packageManagers map[string]system.PackageManager
	verbose         bool
	dryRun          bool
}

type InstallResult struct {
	Component       profile.ComponentInfo
	InstallResult   *exec.ExecResult
	LinkResults     []link.LinkResult
	PostInstallResult *exec.ExecResult
	PostLinkResult  *exec.ExecResult
	DefaultsResults []system.DefaultsResult
	Skipped         bool
	Error           error
}

func NewManager(cfg *config.Config, baseDir string, verbose, dryRun bool) (*Manager, error) {
	stateManager, err := state.NewManager()
	if err != nil {
		return nil, fmt.Errorf("failed to create state manager: %w", err)
	}

	return &Manager{
		baseDir:         baseDir,
		profileManager:  profile.NewManager(cfg),
		stateManager:    stateManager,
		linkManager:     link.NewManager(baseDir, dryRun, verbose),
		execManager:     exec.NewManager(dryRun, verbose),
		defaultsManager: system.NewDefaultsManager(baseDir, dryRun, verbose),
		packageManagers: system.DiscoverPackageManagers(),
		verbose:         verbose,
		dryRun:          dryRun,
	}, nil
}

func (m *Manager) InstallComponents(activeProfiles []string, fuzzySearch string, forceInstall bool) ([]InstallResult, error) {
	return m.installComponents(activeProfiles, fuzzySearch, forceInstall, true)
}

func (m *Manager) InstallComponentsWithoutSaving(activeProfiles []string, fuzzySearch string, forceInstall bool) ([]InstallResult, error) {
	return m.installComponents(activeProfiles, fuzzySearch, forceInstall, false)
}

func (m *Manager) installComponents(activeProfiles []string, fuzzySearch string, forceInstall bool, saveProfiles bool) ([]InstallResult, error) {
	components, err := m.profileManager.GetActiveComponents(activeProfiles, fuzzySearch)
	if err != nil {
		return nil, err
	}

	// Quick early check for idempotency
	if !forceInstall && m.verbose {
		skipCount := 0
		for _, comp := range components {
			needsInstall := !m.stateManager.IsComponentInstalled(comp) || m.stateManager.HasInstallChanged(comp, comp.Component.Install)
			hasLinks := len(comp.Component.Link) > 0
			if !needsInstall && !hasLinks {
				skipCount++
			}
		}
		if skipCount > 0 {
			fmt.Printf("   %d components already up-to-date (will be skipped)\n", skipCount)
		}
	}

	var results []InstallResult

	for _, comp := range components {
		result := m.installComponent(comp, forceInstall)
		results = append(results, result)
	}

	// Save state after installation
	if !m.dryRun {
		if saveProfiles {
			m.stateManager.SetActiveProfiles(activeProfiles)
			if m.verbose && len(activeProfiles) > 0 {
				fmt.Printf("💾 Saving profiles to state: %s\n", strings.Join(activeProfiles, ", "))
			}
		}
		if err := m.stateManager.Save(); err != nil {
			return results, fmt.Errorf("failed to save state: %w", err)
		}
	}

	return results, nil
}

// InstallComponentsWithProgress installs components with live progress updates
func (m *Manager) InstallComponentsWithProgress(activeProfiles []string, fuzzySearch string, forceInstall bool, progressManager *ui.ProgressManager) ([]InstallResult, error) {
	return m.installComponentsWithProgress(activeProfiles, fuzzySearch, forceInstall, progressManager, true)
}

// InstallComponentsWithProgressWithoutSaving installs components with live progress updates but doesn't save profiles
func (m *Manager) InstallComponentsWithProgressWithoutSaving(activeProfiles []string, fuzzySearch string, forceInstall bool, progressManager *ui.ProgressManager) ([]InstallResult, error) {
	return m.installComponentsWithProgress(activeProfiles, fuzzySearch, forceInstall, progressManager, false)
}

func (m *Manager) installComponentsWithProgress(activeProfiles []string, fuzzySearch string, forceInstall bool, progressManager *ui.ProgressManager, saveProfiles bool) ([]InstallResult, error) {
	components, err := m.profileManager.GetActiveComponents(activeProfiles, fuzzySearch)
	if err != nil {
		return nil, err
	}

	var results []InstallResult

	for _, comp := range components {
		result := m.installComponentWithProgress(comp, forceInstall, progressManager)
		results = append(results, result)
	}

	// Save state after installation
	if !m.dryRun {
		if saveProfiles {
			m.stateManager.SetActiveProfiles(activeProfiles)
			if m.verbose && len(activeProfiles) > 0 {
				fmt.Printf("💾 Saving profiles to state: %s\n", strings.Join(activeProfiles, ", "))
			}
		}
		if err := m.stateManager.Save(); err != nil {
			return results, fmt.Errorf("failed to save state: %w", err)
		}
	}

	return results, nil
}

func (m *Manager) installComponent(comp profile.ComponentInfo, forceInstall bool) InstallResult {
	result := InstallResult{Component: comp}

	// Check if component needs install work (linking always runs)
	needsInstall := forceInstall || !m.stateManager.IsComponentInstalled(comp) || m.stateManager.HasInstallChanged(comp, comp.Component.Install)
	hasLinks := len(comp.Component.Link) > 0

	// If no install needed and no links, mark as successful (already in desired state)
	if !needsInstall && !hasLinks {
		return result
	}

	// Install packages only if install changed
	if len(comp.Component.Install) > 0 && needsInstall {
		if m.verbose {
			fmt.Printf("   Installing packages for %s...\n", comp.FullName())
		}
		
		commandName, command, available := system.GetFirstAvailableCommand(comp.Component.Install)
		if !available {
			result.Error = fmt.Errorf("no available command for component %s (tried: %v)", comp.FullName(), getCommandNames(comp.Component.Install))
			return result
		}

		installResult := m.execManager.ExecuteShellCommand(command)
		result.InstallResult = &installResult

		if !installResult.Success {
			result.Error = fmt.Errorf("install failed: %w", installResult.Error)
			return result
		}

		// Mark as installed in state
		if !m.dryRun {
			m.stateManager.MarkComponentInstalled(comp, commandName, command, comp.Component.Link)
		}
	} else if len(comp.Component.Install) > 0 && !needsInstall {
		// Packages already installed and unchanged, skip install step
		if m.verbose {
			fmt.Printf("   Packages for %s already installed and up-to-date\n", comp.FullName())
		}
	}

	// Create links
	if len(comp.Component.Link) > 0 {
		linkResults, err := m.linkManager.CreateLinks(comp.Component.Link)
		result.LinkResults = linkResults

		if err != nil {
			result.Error = fmt.Errorf("linking failed: %w", err)
			return result
		}

		// Check if any link failed
		for _, linkResult := range linkResults {
			if !linkResult.WasSuccessful() {
				result.Error = fmt.Errorf("linking failed: %v", linkResult.Error)
				return result
			}
		}

		// Mark as installed in state if only links (no install commands)
		if len(comp.Component.Install) == 0 && !m.dryRun {
			m.stateManager.MarkComponentInstalled(comp, "", "", comp.Component.Link)
		}
	}

	// Handle macOS defaults
	if len(comp.Component.Defaults) > 0 && system.IsMacOS() {
		defaultsResults, err := m.defaultsManager.CompareDefaults(comp.Component.Defaults)
		result.DefaultsResults = defaultsResults

		if err != nil {
			result.Error = fmt.Errorf("defaults comparison failed: %w", err)
			return result
		}

		// Store defaults results for later reporting
	}

	// Run post-install hook
	if comp.Component.PostInstall != "" && result.InstallResult != nil && result.InstallResult.Success {
		postInstallResult := m.execManager.ExecuteShellCommand(comp.Component.PostInstall)
		result.PostInstallResult = &postInstallResult

		if !postInstallResult.Success {
			result.Error = fmt.Errorf("post-install hook failed: %w", postInstallResult.Error)
			return result
		}

		if !m.dryRun {
			m.stateManager.MarkPostInstallRan(comp)
		}
	}

	// Run post-link hook
	if comp.Component.PostLink != "" && len(result.LinkResults) > 0 {
		postLinkResult := m.execManager.ExecuteShellCommand(comp.Component.PostLink)
		result.PostLinkResult = &postLinkResult

		if !postLinkResult.Success {
			result.Error = fmt.Errorf("post-link hook failed: %w", postLinkResult.Error)
			return result
		}

		if !m.dryRun {
			m.stateManager.MarkPostLinkRan(comp)
		}
	}

	return result
}

func (m *Manager) installComponentWithProgress(comp profile.ComponentInfo, forceInstall bool, progressManager *ui.ProgressManager) InstallResult {
	result := InstallResult{Component: comp}
	
	// Create progress tracker for this component
	progress := progressManager.NewComponentProgress(comp.ComponentName)

	// Check if component needs install work (linking always runs)
	needsInstall := forceInstall || !m.stateManager.IsComponentInstalled(comp) || m.stateManager.HasInstallChanged(comp, comp.Component.Install)
	hasLinks := len(comp.Component.Link) > 0

	// If no install needed and no links, mark as successful (already in desired state)
	if !needsInstall && !hasLinks {
		progress.CompleteSuccess()
		return result
	}

	progress.StartInstalling()

	// Install packages only if install changed
	if len(comp.Component.Install) > 0 && needsInstall {
		commandName, command, available := system.GetFirstAvailableCommand(comp.Component.Install)
		if !available {
			result.Error = fmt.Errorf("no available command for component %s (tried: %v)", comp.FullName(), getCommandNames(comp.Component.Install))
			progress.CompleteFailed(result.Error)
			return result
		}

		installResult := m.execManager.ExecuteShellCommandWithProgress(command, progress)
		result.InstallResult = &installResult

		if !installResult.Success {
			result.Error = fmt.Errorf("install failed: %w", installResult.Error)
			progress.CompleteFailed(result.Error)
			return result
		}

		// Mark as installed in state
		if !m.dryRun {
			m.stateManager.MarkComponentInstalled(comp, commandName, command, comp.Component.Link)
		}
	} else if len(comp.Component.Install) > 0 && !needsInstall {
		// Packages already installed and unchanged, skip to linking
		if m.verbose {
			fmt.Printf("   Packages for %s already installed\n", comp.FullName())
		}
	}

	// Create links
	if len(comp.Component.Link) > 0 {
		progress.StartLinking()
		linkResults, err := m.linkManager.CreateLinks(comp.Component.Link)
		result.LinkResults = linkResults

		if err != nil {
			result.Error = fmt.Errorf("linking failed: %w", err)
			progress.CompleteFailed(result.Error)
			return result
		}

		// Check if any link failed
		for _, linkResult := range linkResults {
			if !linkResult.WasSuccessful() {
				result.Error = fmt.Errorf("linking failed: %v", linkResult.Error)
				progress.CompleteFailed(result.Error)
				return result
			}
		}

		// Mark as installed in state if only links (no install commands)
		if len(comp.Component.Install) == 0 && !m.dryRun {
			m.stateManager.MarkComponentInstalled(comp, "", "", comp.Component.Link)
		}
	}

	// Handle macOS defaults
	if len(comp.Component.Defaults) > 0 && system.IsMacOS() {
		defaultsResults, err := m.defaultsManager.CompareDefaults(comp.Component.Defaults)
		result.DefaultsResults = defaultsResults

		if err != nil {
			result.Error = fmt.Errorf("defaults comparison failed: %w", err)
			progress.CompleteFailed(result.Error)
			return result
		}
	}

	// Run post-install hook
	if comp.Component.PostInstall != "" && result.InstallResult != nil && result.InstallResult.Success {
		progress.StartPostHooks()
		postInstallResult := m.execManager.ExecuteShellCommandWithProgress(comp.Component.PostInstall, progress)
		result.PostInstallResult = &postInstallResult

		if !postInstallResult.Success {
			result.Error = fmt.Errorf("post-install hook failed: %w", postInstallResult.Error)
			progress.CompleteFailed(result.Error)
			return result
		}

		if !m.dryRun {
			m.stateManager.MarkPostInstallRan(comp)
		}
	}

	// Run post-link hook
	if comp.Component.PostLink != "" && len(result.LinkResults) > 0 {
		if comp.Component.PostInstall == "" {
			progress.StartPostHooks()
		}
		postLinkResult := m.execManager.ExecuteShellCommandWithProgress(comp.Component.PostLink, progress)
		result.PostLinkResult = &postLinkResult

		if !postLinkResult.Success {
			result.Error = fmt.Errorf("post-link hook failed: %w", postLinkResult.Error)
			progress.CompleteFailed(result.Error)
			return result
		}

		if !m.dryRun {
			m.stateManager.MarkPostLinkRan(comp)
		}
	}

	progress.CompleteSuccess()
	return result
}

// Helper function to get command names for error messages
func getCommandNames(installCommands map[string]string) []string {
	var names []string
	for name := range installCommands {
		names = append(names, name)
	}
	return names
}

func (m *Manager) UninstallRemovedComponents() ([]InstallResult, error) {
	activeProfiles := m.stateManager.GetActiveProfiles()
	currentComponents, err := m.profileManager.GetActiveComponents(activeProfiles, "")
	if err != nil {
		return nil, err
	}

	removedComponents := m.stateManager.GetRemovedComponents(currentComponents)
	var results []InstallResult

	for _, removedState := range removedComponents {
		comp := profile.ComponentInfo{
			ProfileName:   removedState.ProfileName,
			ComponentName: removedState.ComponentName,
		}

		result := m.uninstallComponent(comp, removedState)
		results = append(results, result)
	}

	// Save state after uninstallation
	if !m.dryRun {
		if err := m.stateManager.Save(); err != nil {
			return results, fmt.Errorf("failed to save state: %w", err)
		}
	}

	return results, nil
}

func (m *Manager) uninstallComponent(comp profile.ComponentInfo, componentState state.ComponentState) InstallResult {
	result := InstallResult{Component: comp}

	// Get the original component definition to find uninstall commands
	components, err := m.profileManager.GetComponentsInProfile(comp.ProfileName)
	if err != nil {
		result.Error = fmt.Errorf("failed to get profile: %w", err)
		return result
	}

	originalComponent, exists := components[comp.ComponentName]
	if !exists {
		// Component was removed from config, we can only clean up links
		if len(componentState.Links) > 0 {
			linkResults, err := m.linkManager.RemoveLinks(componentState.Links)
			result.LinkResults = linkResults
			if err != nil {
				result.Error = fmt.Errorf("failed to remove links: %w", err)
				return result
			}
		}

		if !m.dryRun {
			m.stateManager.RemoveComponent(comp)
		}
		return result
	}

	// Run uninstall command if available
	if len(originalComponent.Uninstall) > 0 {
		packageManager, command, available := system.GetFirstAvailablePackageManager(originalComponent.Uninstall, m.packageManagers)
		if available {
			uninstallResult := m.execManager.ExecuteUninstallCommand(packageManager, command)
			result.InstallResult = &uninstallResult

			if !uninstallResult.Success {
				result.Error = fmt.Errorf("uninstall failed: %w", uninstallResult.Error)
				return result
			}
		}
	}

	// Remove links
	if len(componentState.Links) > 0 {
		linkResults, err := m.linkManager.RemoveLinks(componentState.Links)
		result.LinkResults = linkResults
		if err != nil {
			result.Error = fmt.Errorf("failed to remove links: %w", err)
			return result
		}
	}

	// Remove from state
	if !m.dryRun {
		m.stateManager.RemoveComponent(comp)
	}

	return result
}

func (m *Manager) ExportDefaults(activeProfiles []string) error {
	components, err := m.profileManager.GetActiveComponents(activeProfiles, "")
	if err != nil {
		return err
	}

	for _, comp := range components {
		if len(comp.Component.Defaults) > 0 {
			results, err := m.defaultsManager.ExportDefaults(comp.Component.Defaults)
			if err != nil {
				return fmt.Errorf("failed to export defaults for %s: %w", comp.FullName(), err)
			}

			for _, result := range results {
				fmt.Println(result.String())
			}
		}
	}

	return nil
}

func (m *Manager) ImportDefaults(activeProfiles []string) error {
	components, err := m.profileManager.GetActiveComponents(activeProfiles, "")
	if err != nil {
		return err
	}

	for _, comp := range components {
		if len(comp.Component.Defaults) > 0 {
			results, err := m.defaultsManager.ImportDefaults(comp.Component.Defaults)
			if err != nil {
				return fmt.Errorf("failed to import defaults for %s: %w", comp.FullName(), err)
			}

			for _, result := range results {
				fmt.Println(result.String())
			}
		}
	}

	return nil
}

func (m *Manager) GetBaseDir() string {
	return m.baseDir
}

func (r *InstallResult) WasSuccessful() bool {
	return r.Error == nil
}

func (r *InstallResult) String() string {
	if r.Skipped {
		return fmt.Sprintf("Skipped %s (no changes)", r.Component.FullName())
	}

	if r.Error != nil {
		return fmt.Sprintf("✗ %s: %v", r.Component.FullName(), r.Error)
	}

	return fmt.Sprintf("✓ %s", r.Component.FullName())
}