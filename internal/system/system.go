package system

import (
	"os/exec"
	"runtime"
	"strings"
)

type PackageManager struct {
	Name      string
	Available bool
	Path      string
}

func DetectOS() string {
	switch runtime.GOOS {
	case "darwin":
		return "darwin"
	case "linux":
		return "linux"
	default:
		return runtime.GOOS
	}
}

func IsMacOS() bool {
	return runtime.GOOS == "darwin"
}

func IsLinux() bool {
	return runtime.GOOS == "linux"
}

func DiscoverPackageManagers() map[string]PackageManager {
	managers := map[string]PackageManager{
		"brew": {Name: "brew"},
		"apt":  {Name: "apt"},
		"yum":  {Name: "yum"},
		"dnf":  {Name: "dnf"},
		"pacman": {Name: "pacman"},
		"snap": {Name: "snap"},
		"pip":  {Name: "pip"},
		"pip3": {Name: "pip3"},
		"npm":  {Name: "npm"},
		"cargo": {Name: "cargo"},
		"go":   {Name: "go"},
	}

	for name, manager := range managers {
		path, err := exec.LookPath(name)
		if err == nil {
			manager.Available = true
			manager.Path = path
		}
		managers[name] = manager
	}

	return managers
}

func GetFirstAvailablePackageManager(installCommands map[string]string, managers map[string]PackageManager) (string, string, bool) {
	// Try any available manager
	for managerName, cmd := range installCommands {
		if manager, available := managers[managerName]; available && manager.Available {
			return managerName, cmd, true
		}
	}
	
	return "", "", false
}

// GetFirstAvailableCommand finds the first install command that has an available binary
func GetFirstAvailableCommand(installCommands map[string]string) (string, string, bool) {
	// Try any available command
	for commandName, cmd := range installCommands {
		if CommandExists(commandName) {
			return commandName, cmd, true
		}
	}
	
	return "", "", false
}

func CommandExists(command string) bool {
	_, err := exec.LookPath(command)
	return err == nil
}

func GetCommandPath(command string) string {
	path, err := exec.LookPath(command)
	if err != nil {
		return ""
	}
	return path
}

// NormalizeOSName converts various OS name formats to standardized names
func NormalizeOSName(osName string) string {
	normalized := strings.ToLower(strings.TrimSpace(osName))
	switch normalized {
	case "mac", "macos", "osx":
		return "darwin"
	case "ubuntu", "debian", "fedora", "centos", "rhel", "arch", "manjaro":
		return "linux"
	default:
		return normalized
	}
}