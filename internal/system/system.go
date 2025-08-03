package system

import (
	"os/exec"
	"runtime"
	"strings"
)

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

	// Handle Windows variants
	if strings.HasPrefix(normalized, "windows") {
		return "windows"
	}

	// Handle macOS/Darwin variants
	if strings.HasPrefix(normalized, "macos") || strings.HasPrefix(normalized, "darwin") {
		return "darwin"
	}

	// Handle Linux variants
	if strings.Contains(normalized, "ubuntu") ||
		strings.Contains(normalized, "debian") ||
		strings.Contains(normalized, "fedora") ||
		strings.Contains(normalized, "centos") ||
		strings.Contains(normalized, "rhel") ||
		strings.Contains(normalized, "red hat") ||
		strings.Contains(normalized, "arch") ||
		strings.Contains(normalized, "manjaro") ||
		strings.Contains(normalized, "linux") {
		return "linux"
	}

	// Exact matches for backward compatibility
	switch normalized {
	case "mac", "osx":
		return "darwin"
	default:
		return normalized
	}
}
