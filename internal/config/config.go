package config

import (
	"fmt"
	"os"

	"gopkg.in/yaml.v3"
)

type Config struct {
	Profiles map[string]Profile `yaml:"profiles"`
}

type Profile map[string]Component

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

func validate(config *Config) error {
	if config.Profiles == nil {
		return fmt.Errorf("no profiles defined")
	}

	for profileName, profile := range config.Profiles {
		if profileName == "" {
			return fmt.Errorf("profile name cannot be empty")
		}

		for componentName, component := range profile {
			if componentName == "" {
				return fmt.Errorf("component name cannot be empty in profile %s", profileName)
			}

			// Validate OS restrictions
			for _, osName := range component.OS {
				if osName != "mac" && osName != "darwin" && osName != "linux" {
					return fmt.Errorf("invalid OS restriction '%s' in component %s.%s, must be 'mac', 'darwin', or 'linux'", osName, profileName, componentName)
				}
			}

			// At least one action must be defined
			if len(component.Install) == 0 && len(component.Link) == 0 && len(component.Defaults) == 0 {
				return fmt.Errorf("component %s.%s must define at least one action (install, link, or defaults)", profileName, componentName)
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