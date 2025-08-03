package config

import (
	"fmt"
	"os"
	"strings"

	"gopkg.in/yaml.v3"
)

type Config struct {
	Profiles map[string]Profile `yaml:"profiles"`
}

type Profile map[string]interface{}

type ComponentMap map[string]Component

type Component struct {
	Install     map[string]string `yaml:"install,omitempty"`
	Uninstall   map[string]string `yaml:"uninstall,omitempty"`
	Link        map[string]string `yaml:"link,omitempty"`
	PostInstall string            `yaml:"postinstall,omitempty"`
	PostLink    string            `yaml:"postlink,omitempty"`
	OS          []string          `yaml:"os,omitempty"`
	Defaults    map[string]string `yaml:"defaults,omitempty"`
}

func Load(filename string) (*Config, error) {
	data, err := os.ReadFile(filename)
	if err != nil {
		return nil, fmt.Errorf("failed to read config file %s: %w", filename, err)
	}

	var config Config
	if err := yaml.Unmarshal(data, &config); err != nil {
		return nil, fmt.Errorf("failed to parse YAML config: %w", err)
	}

	if err := validate(&config); err != nil {
		return nil, fmt.Errorf("config validation failed: %w", err)
	}

	return &config, nil
}

// GetComponents recursively extracts all components from a profile
func (p Profile) GetComponents() ComponentMap {
	components := make(ComponentMap)
	for name, value := range p {
		extractComponents(value, name, components)
	}
	return components
}


// extractComponents recursively traverses the profile structure to find components
func extractComponents(value interface{}, path string, components ComponentMap) {
	switch v := value.(type) {
	case map[string]interface{}:
		// Check if this is a component (has component properties)
		if isComponent(v) {
			// Convert to Component struct
			component, err := convertToComponent(v)
			if err == nil {
				components[path] = component
			}
		} else {
			// This is a container, recurse into it
			for key, nestedValue := range v {
				newPath := path + "." + key
				extractComponents(nestedValue, newPath, components)
			}
		}
	case Profile:
		// Handle Profile type (which is map[string]interface{})
		m := map[string]interface{}(v)
		if isComponent(m) {
			// Convert to Component struct
			component, err := convertToComponent(m)
			if err == nil {
				components[path] = component
			}
		} else {
			// This is a container, recurse into it
			for key, nestedValue := range v {
				newPath := path + "." + key
				extractComponents(nestedValue, newPath, components)
			}
		}
	case Component:
		// Direct component (backward compatibility)
		components[path] = v
	}
}

// isComponent checks if a map contains component properties
func isComponent(m map[string]interface{}) bool {
	componentKeys := []string{"install", "uninstall", "link", "postinstall", "postlink", "os", "defaults"}
	for _, key := range componentKeys {
		if _, exists := m[key]; exists {
			return true
		}
	}
	return false
}

// convertToComponent converts a map[string]interface{} to a Component struct
func convertToComponent(m map[string]interface{}) (Component, error) {
	// Marshal back to YAML and unmarshal into Component struct
	// This handles type conversion properly
	data, err := yaml.Marshal(m)
	if err != nil {
		return Component{}, err
	}
	
	var component Component
	err = yaml.Unmarshal(data, &component)
	return component, err
}

func validate(config *Config) error {
	if config.Profiles == nil {
		return fmt.Errorf("no profiles defined")
	}

	for profileName, profile := range config.Profiles {
		if profileName == "" {
			return fmt.Errorf("profile name cannot be empty")
		}

		// Extract all components from the potentially recursive profile structure
		components := profile.GetComponents()
		if len(components) == 0 {
			return fmt.Errorf("profile %s contains no components", profileName)
		}

		for componentPath, component := range components {
			if strings.Contains(componentPath, "..") || strings.HasPrefix(componentPath, ".") || strings.HasSuffix(componentPath, ".") {
				return fmt.Errorf("invalid component path '%s' in profile %s", componentPath, profileName)
			}

			// Validate OS restrictions
			for _, osName := range component.OS {
				if osName != "mac" && osName != "darwin" && osName != "linux" {
					return fmt.Errorf("invalid OS restriction '%s' in component %s.%s, must be 'mac', 'darwin', or 'linux'", osName, profileName, componentPath)
				}
			}

			// At least one action must be defined
			if len(component.Install) == 0 && len(component.Link) == 0 && len(component.Defaults) == 0 {
				return fmt.Errorf("component %s.%s must define at least one action (install, link, or defaults)", profileName, componentPath)
			}
		}
	}

	return nil
}

func (c *Component) MatchesOS(currentOS string) bool {
	if len(c.OS) == 0 {
		return true // No OS restriction means install on all
	}

	for _, osRestriction := range c.OS {
		// Normalize OS names - treat 'mac' and 'darwin' as equivalent
		normalizedRestriction := osRestriction
		if osRestriction == "mac" {
			normalizedRestriction = "darwin"
		}

		normalizedCurrent := currentOS
		if currentOS == "mac" {
			normalizedCurrent = "darwin"
		}

		if normalizedRestriction == normalizedCurrent {
			return true
		}
	}

	return false
}