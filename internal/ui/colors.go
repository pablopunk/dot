package ui

import (
	"os"
	"runtime"
)

// ANSI color codes
const (
	Reset  = "\033[0m"
	Red    = "\033[31m"
	Green  = "\033[32m"
	Yellow = "\033[33m"
	Blue   = "\033[34m"
	Purple = "\033[35m"
	Cyan   = "\033[36m"
	Gray   = "\033[37m"
	White  = "\033[97m"
)

// ColorEnabled checks if colors should be enabled
func ColorEnabled() bool {
	// Disable colors on Windows unless explicitly enabled
	if runtime.GOOS == "windows" {
		return os.Getenv("FORCE_COLOR") != ""
	}

	// Check if output is a terminal
	if os.Getenv("NO_COLOR") != "" {
		return false
	}

	// Enable colors by default on Unix-like systems
	return true
}

// Colorize wraps text with color codes if colors are enabled
func Colorize(color, text string) string {
	if !ColorEnabled() {
		return text
	}
	return color + text + Reset
}

// Success returns a green checkmark
func Success(text string) string {
	checkmark := Colorize(Green, "✓")
	if text == "" {
		return checkmark
	}
	return checkmark + " " + text
}

// Error returns a red cross mark
func Error(text string) string {
	cross := Colorize(Red, "✗")
	if text == "" {
		return cross
	}
	return cross + " " + Colorize(Red, text)
}

// Warning returns a yellow warning symbol
func Warning(text string) string {
	warning := Colorize(Yellow, "⚠")
	if text == "" {
		return warning
	}
	return warning + " " + text
}

// Info returns a blue info symbol
func Info(text string) string {
	info := Colorize(Blue, "ℹ")
	if text == "" {
		return info
	}
	return info + " " + text
}

// Skip returns a colored skip symbol
func Skip(text string) string {
	skip := Colorize(Yellow, "⏭")
	if text == "" {
		return skip
	}
	return skip + " " + text
}

// Processing returns a colored processing symbol
func Processing(text string) string {
	processing := Colorize(Blue, "🔄")
	if text == "" {
		return processing
	}
	return processing + " " + text
}

// Red text helper
func RedText(text string) string {
	return Colorize(Red, text)
}

// Green text helper
func GreenText(text string) string {
	return Colorize(Green, text)
}

// Yellow text helper
func YellowText(text string) string {
	return Colorize(Yellow, text)
}

// Blue text helper
func BlueText(text string) string {
	return Colorize(Blue, text)
}
