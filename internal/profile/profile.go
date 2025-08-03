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

type SearchResult struct {
	Components     []ComponentInfo
	UnmatchedTerms []string
}

func (m *Manager) GetActiveComponents(activeProfiles []string, fuzzySearch string) ([]ComponentInfo, error) {
	result, err := m.GetActiveComponentsWithSearchResult(activeProfiles, fuzzySearch)
	if err != nil {
		return nil, err
	}
	return result.Components, nil
}

func (m *Manager) GetActiveComponentsWithSearchResult(activeProfiles []string, fuzzySearch string) (*SearchResult, error) {
	var components []ComponentInfo
	var unmatchedTerms []string

	// If fuzzy search is provided, track which terms match
	var searchTerms []string
	if fuzzySearch != "" {
		searchTerms = strings.Fields(strings.ToLower(fuzzySearch))
		unmatchedTerms = make([]string, len(searchTerms))
		copy(unmatchedTerms, searchTerms)
	}

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
				if fuzzySearch == "" {
					components = append(components, ComponentInfo{
						ProfileName:   "*",
						ComponentName: componentPath,
						Component:     component,
					})
				} else {
					matchingTerm := m.getMatchingTerm(componentPath, searchTerms)
					if matchingTerm != "" {
						components = append(components, ComponentInfo{
							ProfileName:   "*",
							ComponentName: componentPath,
							Component:     component,
						})
						// Remove this term from unmatched list
						for i, term := range unmatchedTerms {
							if term == matchingTerm {
								unmatchedTerms = append(unmatchedTerms[:i], unmatchedTerms[i+1:]...)
								break
							}
						}
					}
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
				if fuzzySearch == "" {
					components = append(components, ComponentInfo{
						ProfileName:   profileName,
						ComponentName: componentPath,
						Component:     component,
					})
				} else {
					matchingTerm := m.getMatchingTerm(componentPath, searchTerms)
					if matchingTerm != "" {
						components = append(components, ComponentInfo{
							ProfileName:   profileName,
							ComponentName: componentPath,
							Component:     component,
						})
						// Remove this term from unmatched list
						for i, term := range unmatchedTerms {
							if term == matchingTerm {
								unmatchedTerms = append(unmatchedTerms[:i], unmatchedTerms[i+1:]...)
								break
							}
						}
					}
				}
			}
		}
	}

	return &SearchResult{
		Components:     components,
		UnmatchedTerms: unmatchedTerms,
	}, nil
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

	// Split search into multiple terms
	searchTerms := strings.Fields(strings.ToLower(search))

	// Check if component matches any of the search terms
	for _, term := range searchTerms {
		if m.matchesSingleTerm(componentLower, term) {
			return true
		}
	}

	return false
}

// getMatchingTerm returns the first search term that matches the component, or empty string if none match
func (m *Manager) getMatchingTerm(componentName string, searchTerms []string) string {
	componentLower := strings.ToLower(componentName)

	for _, term := range searchTerms {
		if m.matchesSingleTerm(componentLower, term) {
			return term
		}
	}

	return ""
}

func (m *Manager) matchesSingleTerm(componentName, searchTerm string) bool {
	// Exact match
	if componentName == searchTerm {
		return true
	}

	// Contains match
	if strings.Contains(componentName, searchTerm) {
		return true
	}

	// Simple fuzzy matching - check if all characters of search appear in order
	searchIdx := 0
	for _, char := range componentName {
		if searchIdx < len(searchTerm) && char == rune(searchTerm[searchIdx]) {
			searchIdx++
		}
	}

	return searchIdx == len(searchTerm)
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
