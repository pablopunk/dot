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
	seenComponents := make(map[string]bool) // Track already-added components to deduplicate

	// If fuzzy search is provided, track which terms match
	var searchTerms []string
	if fuzzySearch != "" {
		searchTerms = strings.Fields(strings.ToLower(fuzzySearch))
		unmatchedTerms = make([]string, len(searchTerms))
		copy(unmatchedTerms, searchTerms)
	}

	// Always include the "*" profile if it exists
	if _, exists := m.config.Profiles["*"]; exists {
		if err := m.addProfileComponents("*", &components, &seenComponents, searchTerms, &unmatchedTerms, fuzzySearch); err != nil {
			return nil, err
		}
	}

	// Add components from explicitly requested profiles
	for _, profileName := range activeProfiles {
		if profileName == "*" {
			continue // Already handled above
		}

		if _, exists := m.config.Profiles[profileName]; !exists {
			return nil, fmt.Errorf("profile '%s' not found", profileName)
		}

		if err := m.addProfileComponents(profileName, &components, &seenComponents, searchTerms, &unmatchedTerms, fuzzySearch); err != nil {
			return nil, err
		}
	}

	return &SearchResult{
		Components:     components,
		UnmatchedTerms: unmatchedTerms,
	}, nil
}

// addProfileComponents adds all tools from a profile to the components list
// It expands nested config containers and deduplicates
func (m *Manager) addProfileComponents(profileName string, components *[]ComponentInfo, seenComponents *map[string]bool, searchTerms []string, unmatchedTerms *[]string, fuzzySearch string) error {
	profileComponents, err := m.config.GetComponentsForProfileTools(profileName)
	if err != nil {
		return err
	}

	// Get sorted tool names to maintain consistent order
	var toolNames []string
	for toolName := range profileComponents {
		toolNames = append(toolNames, toolName)
	}
	sort.Strings(toolNames)

	for _, toolName := range toolNames {
		// Skip if we've already added this component
		if (*seenComponents)[toolName] {
			continue
		}
		(*seenComponents)[toolName] = true

		component := profileComponents[toolName]
		if component.MatchesOS(m.currentOS) {
			if fuzzySearch == "" {
				*components = append(*components, ComponentInfo{
					ProfileName:   profileName,
					ComponentName: toolName,
					Component:     component,
				})
			} else {
				matchingTerm := m.getMatchingTerm(toolName, searchTerms)
				if matchingTerm != "" {
					*components = append(*components, ComponentInfo{
						ProfileName:   profileName,
						ComponentName: toolName,
						Component:     component,
					})
					// Remove this term from unmatched list
					for i, term := range *unmatchedTerms {
						if term == matchingTerm {
							*unmatchedTerms = append((*unmatchedTerms)[:i], (*unmatchedTerms)[i+1:]...)
							break
						}
					}
				}
			}
		}
	}

	return nil
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
	if _, exists := m.config.Profiles[profileName]; !exists {
		return nil, fmt.Errorf("profile '%s' not found", profileName)
	}
	return m.config.GetComponentsForProfileTools(profileName)
}

func (m *Manager) FindComponentsByFuzzySearch(search string) []ComponentInfo {
	var matches []ComponentInfo
	seenComponents := make(map[string]bool)

	// Iterate through all profiles
	for profileName := range m.config.Profiles {
		profileComponents, err := m.config.GetComponentsForProfileTools(profileName)
		if err != nil {
			// Skip profiles that have errors
			continue
		}

		// Get sorted tool names to maintain consistent order
		var toolNames []string
		for toolName := range profileComponents {
			toolNames = append(toolNames, toolName)
		}
		sort.Strings(toolNames)

		for _, toolName := range toolNames {
			// Skip if we've already added this component
			if seenComponents[toolName] {
				continue
			}
			seenComponents[toolName] = true

			component := profileComponents[toolName]
			if component.MatchesOS(m.currentOS) && m.matchesFuzzySearch(toolName, search) {
				matches = append(matches, ComponentInfo{
					ProfileName:   profileName,
					ComponentName: toolName,
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
