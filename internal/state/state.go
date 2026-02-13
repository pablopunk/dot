package state

import (
	"fmt"
	"os"
	"path/filepath"
	"time"

	"gopkg.in/yaml.v3"

	"github.com/pablopunk/dot/internal/config"
	"github.com/pablopunk/dot/internal/profile"
)

type LockFile struct {
	Version             string                    `yaml:"version"`
	LastUpdated         time.Time                 `yaml:"last_updated"`
	ActiveProfiles      []string                  `yaml:"active_profiles"`
	InstalledComponents map[string]ComponentState `yaml:"installed_components"`
}

type ComponentState struct {
	ProfileName       string            `yaml:"profile_name"`
	ComponentName     string            `yaml:"component_name"`
	InstalledAt       time.Time         `yaml:"installed_at"`
	PackageManager    string            `yaml:"package_manager,omitempty"`
	InstallCommand    string            `yaml:"install_command,omitempty"`
	UninstallCommands map[string]string `yaml:"uninstall_commands,omitempty"` // Store uninstall commands for when component is removed
	Links             config.LinkMap    `yaml:"links,omitempty"`
	PostInstallRan    bool              `yaml:"post_install_ran"`
	PostLinkRan       bool              `yaml:"post_link_ran"`
	ContentHash       string            `yaml:"content_hash,omitempty"` // Hash of component content for rename detection
}

type Manager struct {
	lockFilePath string
	lockFile     *LockFile
}

const LockFileVersion = "1.2"

func NewManager() (*Manager, error) {
	homeDir, err := os.UserHomeDir()
	if err != nil {
		return nil, fmt.Errorf("failed to get home directory: %w", err)
	}

	lockFilePath := filepath.Join(homeDir, ".local", "state", "dot", "lock.yaml")

	manager := &Manager{
		lockFilePath: lockFilePath,
	}

	if err := manager.Load(); err != nil {
		return nil, err
	}

	return manager, nil
}

func (m *Manager) Load() error {
	// Create directory if it doesn't exist
	if err := os.MkdirAll(filepath.Dir(m.lockFilePath), 0755); err != nil {
		return fmt.Errorf("failed to create lock file directory: %w", err)
	}

	// If lock file doesn't exist, create a new one
	if _, err := os.Stat(m.lockFilePath); os.IsNotExist(err) {
		m.lockFile = &LockFile{
			Version:             LockFileVersion,
			LastUpdated:         time.Now(),
			ActiveProfiles:      []string{},
			InstalledComponents: make(map[string]ComponentState),
		}
		return m.Save()
	}

	data, err := os.ReadFile(m.lockFilePath)
	if err != nil {
		return fmt.Errorf("failed to read lock file: %w", err)
	}

	var lockFile LockFile
	if err := yaml.Unmarshal(data, &lockFile); err != nil {
		return fmt.Errorf("failed to parse lock file: %w", err)
	}

	m.lockFile = &lockFile

	// Migrate if necessary
	if m.lockFile.Version != LockFileVersion {
		if err := m.migrate(); err != nil {
			return fmt.Errorf("failed to migrate lock file: %w", err)
		}
	}

	return nil
}

func (m *Manager) Save() error {
	m.lockFile.LastUpdated = time.Now()

	data, err := yaml.Marshal(m.lockFile)
	if err != nil {
		return fmt.Errorf("failed to marshal lock file: %w", err)
	}

	if err := os.WriteFile(m.lockFilePath, data, 0644); err != nil {
		return fmt.Errorf("failed to write lock file: %w", err)
	}

	return nil
}

func (m *Manager) IsComponentInstalled(componentInfo profile.ComponentInfo) bool {
	key := componentInfo.FullName()
	_, exists := m.lockFile.InstalledComponents[key]
	return exists
}

func (m *Manager) MarkComponentInstalled(componentInfo profile.ComponentInfo, packageManager, installCommand string, links config.LinkMap) {
	key := componentInfo.FullName()
	m.lockFile.InstalledComponents[key] = ComponentState{
		ProfileName:       componentInfo.ProfileName,
		ComponentName:     componentInfo.ComponentName,
		InstalledAt:       time.Now(),
		PackageManager:    packageManager,
		InstallCommand:    installCommand,
		UninstallCommands: componentInfo.Component.Uninstall, // Store uninstall commands for later use
		Links:             links,
		PostInstallRan:    false,
		PostLinkRan:       false,
		ContentHash:       componentInfo.Component.ContentHash(),
	}
}

func (m *Manager) MarkPostInstallRan(componentInfo profile.ComponentInfo) {
	key := componentInfo.FullName()
	if state, exists := m.lockFile.InstalledComponents[key]; exists {
		state.PostInstallRan = true
		m.lockFile.InstalledComponents[key] = state
	}
}

func (m *Manager) MarkPostLinkRan(componentInfo profile.ComponentInfo) {
	key := componentInfo.FullName()
	if state, exists := m.lockFile.InstalledComponents[key]; exists {
		state.PostLinkRan = true
		m.lockFile.InstalledComponents[key] = state
	}
}

func (m *Manager) RemoveComponent(componentInfo profile.ComponentInfo) {
	key := componentInfo.FullName()
	delete(m.lockFile.InstalledComponents, key)
}

func (m *Manager) GetInstalledComponents() map[string]ComponentState {
	return m.lockFile.InstalledComponents
}

func (m *Manager) SetActiveProfiles(profiles []string) {
	m.lockFile.ActiveProfiles = profiles
}

func (m *Manager) GetActiveProfiles() []string {
	return m.lockFile.ActiveProfiles
}

func (m *Manager) GetRemovedComponents(currentComponents []profile.ComponentInfo) []ComponentState {
	var removed []ComponentState

	// Create a set of current component keys
	currentKeys := make(map[string]bool)
	// Create a map of content hash to current component for rename detection
	currentContentHashes := make(map[string]profile.ComponentInfo)

	for _, comp := range currentComponents {
		currentKeys[comp.FullName()] = true
		contentHash := comp.Component.ContentHash()
		if contentHash != "" {
			currentContentHashes[contentHash] = comp
		}
	}

	// Find components in lock file that are not in current components
	for key, state := range m.lockFile.InstalledComponents {
		if !currentKeys[key] {
			// Component not found by name, check if it was renamed by content hash
			if state.ContentHash != "" {
				if renamedComponent, exists := currentContentHashes[state.ContentHash]; exists {
					// This component was renamed! Update the state to use the new name
					m.migrateRenamedComponent(key, renamedComponent, state)
					continue // Don't add to removed list
				}
			}
			// Component was truly removed
			removed = append(removed, state)
		}
	}

	return removed
}

func (m *Manager) GetComponentState(componentInfo profile.ComponentInfo) (ComponentState, bool) {
	key := componentInfo.FullName()
	state, exists := m.lockFile.InstalledComponents[key]
	return state, exists
}

func (m *Manager) HasChangedSince(componentInfo profile.ComponentInfo, links config.LinkMap) bool {
	state, exists := m.GetComponentState(componentInfo)
	if !exists {
		return true // Not installed, so it's a change
	}

	// Check if links have changed
	if len(state.Links) != len(links) {
		return true
	}

	for source, targets := range links {
		stateTargets, exists := state.Links[source]
		if !exists {
			return true
		}
		if len(stateTargets) != len(targets) {
			return true
		}
		// Check each target matches
		for i, target := range targets {
			if stateTargets[i] != target {
				return true
			}
		}
	}

	return false
}

// HasInstallChanged checks if the install commands have changed for a component
func (m *Manager) HasInstallChanged(componentInfo profile.ComponentInfo, installCommands map[string]string) bool {
	state, exists := m.GetComponentState(componentInfo)
	if !exists {
		return true // Not installed, so install is needed
	}

	// If component has no install commands now but had them before, it's a change
	if len(installCommands) == 0 && state.PackageManager != "" {
		return true
	}

	// If component has install commands now but didn't before, it's a change
	if len(installCommands) > 0 && state.PackageManager == "" {
		return true
	}

	// If no install commands either way, no change in install
	if len(installCommands) == 0 {
		return false
	}

	// Check if the actual install command changed
	for packageManager, command := range installCommands {
		if state.PackageManager == packageManager && state.InstallCommand == command {
			return false // Found matching install command, no change
		}
	}

	return true // Install commands changed
}

func (m *Manager) migrate() error {
	// Migrate from 1.0 to 1.1: ContentHash field added
	// Migrate from 1.1 to 1.2: UninstallCommands field added
	// Both fields will be populated on next component update
	m.lockFile.Version = LockFileVersion
	return m.Save()
}

func (m *Manager) GetLockFilePath() string {
	return m.lockFilePath
}

// migrateRenamedComponent moves a component from old name to new name in the state
// This handles the case where a component was renamed/moved but has identical core functionality
func (m *Manager) migrateRenamedComponent(oldKey string, newComponent profile.ComponentInfo, oldState ComponentState) {
	newKey := newComponent.FullName()

	// Create new state preserving installation state but resetting link state
	// This ensures that links will be re-created for the new component location
	newState := ComponentState{
		ProfileName:       newComponent.ProfileName,
		ComponentName:     newComponent.ComponentName,
		InstalledAt:       oldState.InstalledAt,
		PackageManager:    oldState.PackageManager,
		InstallCommand:    oldState.InstallCommand,
		UninstallCommands: newComponent.Component.Uninstall, // Update uninstall commands to new component's
		Links:             config.LinkMap{},                 // Reset links so they get re-created
		PostInstallRan:    oldState.PostInstallRan,
		PostLinkRan:       false, // Reset post-link state since links will be re-created
		ContentHash:       newComponent.Component.ContentHash(),
	}

	// Remove old entry and add new one
	delete(m.lockFile.InstalledComponents, oldKey)
	m.lockFile.InstalledComponents[newKey] = newState
}

func (m *Manager) Reset() error {
	m.lockFile = &LockFile{
		Version:             LockFileVersion,
		LastUpdated:         time.Now(),
		ActiveProfiles:      []string{},
		InstalledComponents: make(map[string]ComponentState),
	}
	return m.Save()
}
