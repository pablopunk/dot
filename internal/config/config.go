package config

import (
	"crypto/sha256"
	"fmt"
	"os"
	"sort"

	"gopkg.in/yaml.v3"
)

type Config struct {
	Profiles  map[string][]interface{} `yaml:"profiles"`
	Config    map[string]interface{}   `yaml:"config"` // Allow nested structures
	RawConfig map[string]Component     // Flattened config for fast lookup
}

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

	// Flatten nested config into RawConfig
	config.RawConfig = make(map[string]Component)
	if err := flattenConfig(config.Config, config.RawConfig); err != nil {
		return nil, fmt.Errorf("failed to process config: %w", err)
	}

	if err := validate(&config); err != nil {
		return nil, fmt.Errorf("config validation failed: %w", err)
	}

	return &config, nil
}

// flattenConfig recursively flattens nested config structures into a flat map of Components
func flattenConfig(source map[string]interface{}, target map[string]Component) error {
	for key, value := range source {
		if component, ok := value.(Component); ok {
			// It's already a Component - add it directly
			target[key] = component
		} else if mapVal, ok := value.(map[string]interface{}); ok {
			// It's a nested map - try to unmarshal as Component first
			data, err := yaml.Marshal(mapVal)
			if err != nil {
				return fmt.Errorf("failed to marshal value for key '%s': %w", key, err)
			}

			var comp Component
			if err := yaml.Unmarshal(data, &comp); err != nil {
				return fmt.Errorf("failed to unmarshal value for key '%s': %w", key, err)
			}

			// Check if it has any action fields (Install, Link, Defaults, Uninstall)
			hasActions := len(comp.Install) > 0 || len(comp.Link) > 0 || len(comp.Defaults) > 0 || len(comp.Uninstall) > 0
			// Check if it has only metadata (OS) without any actions
			hasOnlyMetadata := (len(comp.Install) == 0 && len(comp.Link) == 0 && len(comp.Defaults) == 0 && len(comp.Uninstall) == 0) &&
				(len(comp.OS) > 0 || len(comp.PostInstall) > 0 || len(comp.PostLink) > 0)

			if hasActions {
				// It's a component with actions - add it directly
				target[key] = comp
			} else if hasOnlyMetadata {
				// It's an invalid component (has metadata but no actions) - still add to RawConfig so validation catches it
				target[key] = comp
			} else {
				// It's likely a container (no actions and no metadata) - recursively flatten
				nestedComponents := make(map[string]Component)
				if err := flattenConfig(mapVal, nestedComponents); err != nil {
					return err
				}
				// Add nested components to target
				for nestedKey, nestedComp := range nestedComponents {
					target[nestedKey] = nestedComp
				}
			}
		}
	}
	return nil
}

// GetComponentsForProfileTools resolves tools from a profile and returns their configurations
// It expands container references and deduplicates tool names
func (c *Config) GetComponentsForProfileTools(profileName string) (ComponentMap, error) {
	visited := make(map[string]bool)
	toolNames := make(map[string]bool)
	var tools []string

	if err := c.expandProfileTools(profileName, &visited, toolNames, &tools); err != nil {
		return nil, err
	}

	// Map tool names to components from flattened config
	components := make(ComponentMap)
	for _, toolName := range tools {
		if component, exists := c.RawConfig[toolName]; exists {
			components[toolName] = component
		} else {
			return nil, fmt.Errorf("tool '%s' referenced in profile '%s' has no config defined", toolName, profileName)
		}
	}
	return components, nil
}

// expandProfileTools expands a profile to get all tool names
// Profiles can reference tools in RawConfig or containers in Config
func (c *Config) expandProfileTools(profileName string, visited *map[string]bool, toolNames map[string]bool, tools *[]string) error {
	// Track visited profiles to ensure each is processed only once
	if (*visited)[profileName] {
		return nil
	}
	(*visited)[profileName] = true

	profile, exists := c.Profiles[profileName]
	if !exists {
		return fmt.Errorf("profile '%s' not found", profileName)
	}

	for _, item := range profile {
		itemStr, ok := item.(string)
		if !ok {
			return fmt.Errorf("profile items must be strings, got %T in profile '%s'", item, profileName)
		}

		if _, isInRawConfig := c.RawConfig[itemStr]; isInRawConfig {
			// It's a tool in RawConfig - add to tools list if not already seen
			if !toolNames[itemStr] {
				toolNames[itemStr] = true
				*tools = append(*tools, itemStr)
			}
		} else if configItem, isContainer := c.Config[itemStr]; isContainer {
			// It's a container in Config - expand all tools under it
			if err := c.expandConfigContainer(itemStr, configItem, toolNames, tools); err != nil {
				return err
			}
		} else {
			return fmt.Errorf("profile item '%s' in profile '%s' not found in config or as a container", itemStr, profileName)
		}
	}

	return nil
}

// expandConfigContainer expands all tools under a nested config container
func (c *Config) expandConfigContainer(containerName string, containerValue interface{}, toolNames map[string]bool, tools *[]string) error {
	// The container should be a map of tools
	mapVal, ok := containerValue.(map[string]interface{})
	if !ok {
		return fmt.Errorf("container '%s' is not a map", containerName)
	}

	// For each item in the container, check if it's in RawConfig
	for nestedToolName := range mapVal {
		if _, exists := c.RawConfig[nestedToolName]; exists {
			if !toolNames[nestedToolName] {
				toolNames[nestedToolName] = true
				*tools = append(*tools, nestedToolName)
			}
		}
	}

	return nil
}

func validate(config *Config) error {
	if config.Profiles == nil {
		return fmt.Errorf("no profiles defined")
	}

	if config.Config == nil {
		return fmt.Errorf("no config section defined")
	}

	// Validate profile names are not empty
	for profileName, tools := range config.Profiles {
		if profileName == "" {
			return fmt.Errorf("profile name cannot be empty")
		}

		if len(tools) == 0 {
			return fmt.Errorf("profile %s contains no tools", profileName)
		}

		// Validate each tool/container reference in the profile
		for _, item := range tools {
			itemStr, ok := item.(string)
			if !ok {
				return fmt.Errorf("profile items must be strings, got %T in profile '%s'", item, profileName)
			}

			if itemStr == "" {
				return fmt.Errorf("profile %s contains empty tool reference", profileName)
			}

			// Check if it's a tool in RawConfig
			if _, exists := config.RawConfig[itemStr]; exists {
				continue
			}

			// Check if it's a container in the original Config
			if _, isContainer := config.Config[itemStr]; isContainer {
				// It's a container reference, which is valid
				continue
			}

			// Not found anywhere
			return fmt.Errorf("tool '%s' referenced in profile '%s' has no config defined", itemStr, profileName)
		}
	}

	// Validate all tools in RawConfig have at least one action
	for toolName, component := range config.RawConfig {
		// Validate OS restrictions
		for _, osName := range component.OS {
			if osName != "mac" && osName != "darwin" && osName != "linux" {
				return fmt.Errorf("invalid OS restriction '%s' in tool '%s', must be 'mac', 'darwin', or 'linux'", osName, toolName)
			}
		}

		// At least one action must be defined
		if len(component.Install) == 0 && len(component.Link) == 0 && len(component.Defaults) == 0 {
			return fmt.Errorf("tool '%s' must define at least one action (install, link, or defaults)", toolName)
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

// ContentHash generates a hash of the component's core functionality
// This focuses on install/uninstall commands and hooks, but excludes links and paths
// to better detect renames where the component functionality is the same
func (c *Component) ContentHash() string {
	h := sha256.New()

	// Sort and hash install commands
	if len(c.Install) > 0 {
		var installKeys []string
		for k := range c.Install {
			installKeys = append(installKeys, k)
		}
		sort.Strings(installKeys)
		for _, k := range installKeys {
			h.Write([]byte(fmt.Sprintf("install:%s:%s;", k, c.Install[k])))
		}
	}

	// Sort and hash uninstall commands
	if len(c.Uninstall) > 0 {
		var uninstallKeys []string
		for k := range c.Uninstall {
			uninstallKeys = append(uninstallKeys, k)
		}
		sort.Strings(uninstallKeys)
		for _, k := range uninstallKeys {
			h.Write([]byte(fmt.Sprintf("uninstall:%s:%s;", k, c.Uninstall[k])))
		}
	}

	// Hash post-install and post-link hooks
	if c.PostInstall != "" {
		h.Write([]byte(fmt.Sprintf("postinstall:%s;", c.PostInstall)))
	}
	if c.PostLink != "" {
		h.Write([]byte(fmt.Sprintf("postlink:%s;", c.PostLink)))
	}

	// Sort and hash OS restrictions
	if len(c.OS) > 0 {
		osSlice := make([]string, len(c.OS))
		copy(osSlice, c.OS)
		sort.Strings(osSlice)
		for _, os := range osSlice {
			h.Write([]byte(fmt.Sprintf("os:%s;", os)))
		}
	}

	// Sort and hash defaults
	if len(c.Defaults) > 0 {
		var defaultKeys []string
		for k := range c.Defaults {
			defaultKeys = append(defaultKeys, k)
		}
		sort.Strings(defaultKeys)
		for _, k := range defaultKeys {
			h.Write([]byte(fmt.Sprintf("defaults:%s:%s;", k, c.Defaults[k])))
		}
	}

	// NOTE: We intentionally exclude Link mapping from the hash because
	// component moves/renames often involve path changes in links, but
	// the core functionality (install commands, hooks) remains the same

	return fmt.Sprintf("%x", h.Sum(nil))
}
