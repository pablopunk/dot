package state

import (
	"fmt"
	"os"
	"path/filepath"
	"time"

	"gopkg.in/yaml.v3"

	"github.com/pablopunk/dot/internal/profile"
)

type LockFile struct {
	Version         string                    `yaml:"version"`
	LastUpdated     time.Time                 `yaml:"last_updated"`
	ActiveProfiles  []string                  `yaml:"active_profiles"`
	InstalledComponents map[string]ComponentState `yaml:"installed_components"`
}

type ComponentState struct {
	ProfileName     string            `yaml:"profile_name"`
	ComponentName   string            `yaml:"component_name"`
	InstalledAt     time.Time         `yaml:"installed_at"`
	PackageManager  string            `yaml:"package_manager,omitempty"`
	InstallCommand  string            `yaml:"install_command,omitempty"`
	Links           map[string]string `yaml:"links,omitempty"`
	PostInstallRan  bool              `yaml:"post_install_ran"`
	PostLinkRan     bool              `yaml:"post_link_ran"`
}

type Manager struct {
	lockFilePath string
	lockFile     *LockFile
}

const LockFileVersion = "1.0"

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

func (m *Manager) MarkComponentInstalled(componentInfo profile.ComponentInfo, packageManager, installCommand string, links map[string]string) {
	key := componentInfo.FullName()
	m.lockFile.InstalledComponents[key] = ComponentState{
		ProfileName:    componentInfo.ProfileName,
		ComponentName:  componentInfo.ComponentName,
		InstalledAt:    time.Now(),
		PackageManager: packageManager,
		InstallCommand: installCommand,
		Links:          links,
		PostInstallRan: false,
		PostLinkRan:    false,
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
	for _, comp := range currentComponents {
		currentKeys[comp.FullName()] = true
	}
	
	// Find components in lock file that are not in current components
	for key, state := range m.lockFile.InstalledComponents {
		if !currentKeys[key] {
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

func (m *Manager) HasChangedSince(componentInfo profile.ComponentInfo, links map[string]string) bool {
	state, exists := m.GetComponentState(componentInfo)
	if !exists {
		return true // Not installed, so it's a change
	}
	
	// Check if links have changed
	if len(state.Links) != len(links) {
		return true
	}
	
	for source, target := range links {
		if stateTarget, exists := state.Links[source]; !exists || stateTarget != target {
			return true
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
	// Future migration logic would go here
	m.lockFile.Version = LockFileVersion
	return m.Save()
}

func (m *Manager) GetLockFilePath() string {
	return m.lockFilePath
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