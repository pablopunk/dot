package profile

import (
	"fmt"
	"sort"
	"strings"

	"github.com/pablopunk/dot/internal/config"
	"github.com/pablopunk/dot/internal/system"
)

type Manager struct {
	config    *config.Config
	currentOS string
}

type ComponentInfo struct {
	ProfileName   string
	ComponentName string
	Component     config.Component
}

func NewManager(cfg *config.Config) *Manager {
	return &Manager{
		config:    cfg,
		currentOS: system.DetectOS(),
	}
}

func (m *Manager) GetActiveComponents(activeProfiles []string, fuzzySearch string) ([]ComponentInfo, error) {
	var components []ComponentInfo
	
	// Always include the "*" profile if it exists
	if defaultProfile, exists := m.config.Profiles["*"]; exists {
		profileComponents := defaultProfile.GetComponents()
		
		// Get sorted component paths to maintain consistent order
		var paths []string
		for componentPath := range profileComponents {
			paths = append(paths, componentPath)
		}
		sort.Strings(paths)
		
		for _, componentPath := range paths {
			component := profileComponents[componentPath]
			if component.MatchesOS(m.currentOS) {
				if fuzzySearch == "" || m.matchesFuzzySearch(componentPath, fuzzySearch) {
					components = append(components, ComponentInfo{
						ProfileName:   "*",
						ComponentName: componentPath,
						Component:     component,
					})
				}
			}
		}
	}
	
	// Add components from explicitly requested profiles
	for _, profileName := range activeProfiles {
		if profileName == "*" {
			continue // Already handled above
		}
		
		profile, exists := m.config.Profiles[profileName]
		if !exists {
			return nil, fmt.Errorf("profile '%s' not found", profileName)
		}
		
		profileComponents := profile.GetComponents()
		
		// Get sorted component paths to maintain consistent order
		var paths []string
		for componentPath := range profileComponents {
			paths = append(paths, componentPath)
		}
		sort.Strings(paths)
		
		for _, componentPath := range paths {
			component := profileComponents[componentPath]
			if component.MatchesOS(m.currentOS) {
				if fuzzySearch == "" || m.matchesFuzzySearch(componentPath, fuzzySearch) {
					components = append(components, ComponentInfo{
						ProfileName:   profileName,
						ComponentName: componentPath,
						Component:     component,
					})
				}
			}
		}
	}
	
	return components, nil
}

func (m *Manager) ListProfiles() []string {
	var profiles []string
	for profileName := range m.config.Profiles {
		profiles = append(profiles, profileName)
	}
	return profiles
}

func (m *Manager) ProfileExists(profileName string) bool {
	_, exists := m.config.Profiles[profileName]
	return exists
}

func (m *Manager) GetComponentsInProfile(profileName string) (config.ComponentMap, error) {
	profile, exists := m.config.Profiles[profileName]
	if !exists {
		return nil, fmt.Errorf("profile '%s' not found", profileName)
	}
	return profile.GetComponents(), nil
}

func (m *Manager) FindComponentsByFuzzySearch(search string) []ComponentInfo {
	var matches []ComponentInfo
	
	search = strings.ToLower(search)
	
	for profileName, profile := range m.config.Profiles {
		profileComponents := profile.GetComponents()
		
		// Get sorted component paths to maintain consistent order
		var paths []string
		for componentPath := range profileComponents {
			paths = append(paths, componentPath)
		}
		sort.Strings(paths)
		
		for _, componentPath := range paths {
			component := profileComponents[componentPath]
			if component.MatchesOS(m.currentOS) && m.matchesFuzzySearch(componentPath, search) {
				matches = append(matches, ComponentInfo{
					ProfileName:   profileName,
					ComponentName: componentPath,
					Component:     component,
				})
			}
		}
	}
	
	return matches
}

func (m *Manager) matchesFuzzySearch(componentName, search string) bool {
	if search == "" {
		return true
	}
	
	componentLower := strings.ToLower(componentName)
	searchLower := strings.ToLower(search)
	
	// Exact match
	if componentLower == searchLower {
		return true
	}
	
	// Contains match
	if strings.Contains(componentLower, searchLower) {
		return true
	}
	
	// Simple fuzzy matching - check if all characters of search appear in order
	searchIdx := 0
	for _, char := range componentLower {
		if searchIdx < len(searchLower) && char == rune(searchLower[searchIdx]) {
			searchIdx++
		}
	}
	
	return searchIdx == len(searchLower)
}

func (m *Manager) ValidateProfiles(profileNames []string) error {
	for _, profileName := range profileNames {
		if !m.ProfileExists(profileName) {
			return fmt.Errorf("profile '%s' does not exist", profileName)
		}
	}
	return nil
}

func (c *ComponentInfo) FullName() string {
	return fmt.Sprintf("%s.%s", c.ProfileName, c.ComponentName)
}