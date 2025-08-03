package main

import (
	"flag"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/pablopunk/dot/internal/component"
	"github.com/pablopunk/dot/internal/config"
	"github.com/pablopunk/dot/internal/profile"
	"github.com/pablopunk/dot/internal/state"
	"github.com/pablopunk/dot/internal/system"
	"github.com/pablopunk/dot/internal/ui"
)

func main() {
	var (
		listProfiles    = flag.Bool("profiles", false, "list available profiles")
		upgrade         = flag.Bool("upgrade", false, "upgrade the tool")
		removeProfile   = flag.String("remove-profile", "", "remove a profile from the active set")
		verbose         = flag.Bool("v", false, "verbose output")
		verboseLong     = flag.Bool("verbose", false, "verbose output")
		dryRun          = flag.Bool("dry-run", false, "preview actions without making changes")
		forceInstall    = flag.Bool("install", false, "force reinstall regardless of changes")
		forceUninstall  = flag.Bool("uninstall", false, "uninstall components")
		defaultsExport  = flag.Bool("defaults-export", false, "export macOS defaults to plist files")
		defaultsExportShort = flag.Bool("e", false, "export macOS defaults to plist files")
		defaultsImport  = flag.Bool("defaults-import", false, "import macOS defaults from plist files")
		defaultsImportShort = flag.Bool("i", false, "import macOS defaults from plist files")
	)
	flag.Parse()

	// Handle verbose flag (either -v or --verbose)
	isVerbose := *verbose || *verboseLong

	// Handle defaults flags (either short or long form)
	shouldExportDefaults := *defaultsExport || *defaultsExportShort
	shouldImportDefaults := *defaultsImport || *defaultsImportShort

	if *upgrade {
		if err := upgradeCommand(isVerbose); err != nil {
			fmt.Fprintf(os.Stderr, "%s\n", ui.Error(err.Error()))
			os.Exit(1)
		}
		return
	}

	if *listProfiles {
		if err := listProfilesCommand(); err != nil {
			fmt.Fprintf(os.Stderr, "%s\n", ui.Error(err.Error()))
			os.Exit(1)
		}
		return
	}

	app := &App{
		Verbose:        isVerbose,
		DryRun:         *dryRun,
		ForceInstall:   *forceInstall,
		ForceUninstall: *forceUninstall,
		ExportDefaults: shouldExportDefaults,
		ImportDefaults: shouldImportDefaults,
		RemoveProfile:  *removeProfile,
	}

	args := flag.Args()
	if err := app.Run(args); err != nil {
		fmt.Fprintf(os.Stderr, "%s\n", ui.Error(err.Error()))
		os.Exit(1)
	}
}

type App struct {
	Verbose        bool
	DryRun         bool
	ForceInstall   bool
	ForceUninstall bool
	ExportDefaults bool
	ImportDefaults bool
	RemoveProfile  string
}

func (a *App) Run(args []string) error {
	// Get current working directory as base directory
	baseDir, err := os.Getwd()
	if err != nil {
		return fmt.Errorf("failed to get current directory: %w", err)
	}

	configPath := filepath.Join(baseDir, "dot.yaml")
	if a.Verbose {
		fmt.Printf("🔧 Loading configuration...\n")
		fmt.Printf("   Base directory: %s\n", baseDir)
		fmt.Printf("   Config file: %s\n", configPath)
	}

	cfg, err := config.Load(configPath)
	if err != nil {
		return fmt.Errorf("failed to load config: %w", err)
	}

	if a.Verbose {
		fmt.Printf("   ✓ Configuration loaded successfully\n")
		if len(cfg.Profiles) > 0 {
			fmt.Printf("   📋 Available profiles: %d\n", len(cfg.Profiles))
			for name := range cfg.Profiles {
				fmt.Printf("      - %s\n", name)
			}
		}
		fmt.Println()
	}

	componentManager, err := component.NewManager(cfg, baseDir, a.Verbose, a.DryRun)
	if err != nil {
		return fmt.Errorf("failed to create component manager: %w", err)
	}

	profileManager := profile.NewManager(cfg)

	// Handle special commands
	if a.RemoveProfile != "" {
		return a.removeProfileCommand(a.RemoveProfile)
	}

	// Determine active profiles and fuzzy search
	var activeProfiles []string
	var fuzzySearch string
	var profilesFromUser bool = false

	// Parse arguments - first check if they're profile names or fuzzy search
	for _, arg := range args {
		if profileManager.ProfileExists(arg) {
			activeProfiles = append(activeProfiles, arg)
			profilesFromUser = true
			if a.Verbose {
				fmt.Printf("🔍 Recognized '%s' as profile\n", arg)
			}
		} else {
			// Treat as fuzzy search if not a profile name
			if fuzzySearch == "" {
				fuzzySearch = arg
			} else {
				fuzzySearch += " " + arg
			}
			if a.Verbose {
				fmt.Printf("🔍 Treating '%s' as fuzzy search (profile not found)\n", arg)
			}
		}
	}

	// If no profiles specified, load from state or default to empty (which means just "*")
	if len(activeProfiles) == 0 && fuzzySearch == "" {
		stateManager, err := state.NewManager()
		if err != nil {
			return fmt.Errorf("failed to create state manager: %w", err)
		}
		activeProfiles = stateManager.GetActiveProfiles()
		// profiles came from state, not user input
		profilesFromUser = false
		
		if a.Verbose {
			if len(activeProfiles) > 0 {
				fmt.Printf("🔄 Loaded saved profiles from state: %s\n", strings.Join(activeProfiles, ", "))
			} else {
				fmt.Printf("🔄 No saved profiles found in state\n")
			}
		}
	}

	// Handle defaults operations
	if a.ExportDefaults {
		if !system.IsMacOS() {
			return fmt.Errorf("defaults export is only available on macOS")
		}
		return componentManager.ExportDefaults(activeProfiles)
	}

	if a.ImportDefaults {
		if !system.IsMacOS() {
			return fmt.Errorf("defaults import is only available on macOS")
		}
		return componentManager.ImportDefaults(activeProfiles)
	}

	// Handle uninstall
	if a.ForceUninstall {
		results, err := componentManager.UninstallRemovedComponents()
		if err != nil {
			return err
		}
		a.printResults("Uninstall", results)
		return nil
	}

	// Main install operation
	if a.Verbose {
		fmt.Printf("🚀 Starting %s operation...\n", "installation")
		if len(activeProfiles) > 0 {
			fmt.Printf("   Active profiles: %s\n", strings.Join(activeProfiles, ", "))
		} else {
			fmt.Printf("   Active profiles: * (default)\n")
		}
		if fuzzySearch != "" {
			fmt.Printf("   Fuzzy search: %s\n", fuzzySearch)
		}
		if a.ForceInstall {
			fmt.Printf("   Force install: enabled\n")
		}
		if a.DryRun {
			fmt.Printf("   Dry run: enabled\n")
		}
		fmt.Println()
		
		// Use regular installation for verbose mode
		var results []component.InstallResult
		var err error
		if profilesFromUser {
			results, err = componentManager.InstallComponents(activeProfiles, fuzzySearch, a.ForceInstall)
		} else {
			results, err = componentManager.InstallComponentsWithoutSaving(activeProfiles, fuzzySearch, a.ForceInstall)
		}
		if err != nil {
			return err
		}
		a.printResults("Install", results)
	} else {
		// Use animated progress for quiet mode
		progressManager := ui.NewProgressManager(false)
		defer progressManager.StopAll()
		
		var results []component.InstallResult
		var err error
		if profilesFromUser {
			results, err = componentManager.InstallComponentsWithProgress(activeProfiles, fuzzySearch, a.ForceInstall, progressManager)
		} else {
			results, err = componentManager.InstallComponentsWithProgressWithoutSaving(activeProfiles, fuzzySearch, a.ForceInstall, progressManager)
		}
		if err != nil {
			return err
		}
		a.printSummaryResults("Install", results)
	}

	// Also handle automatic uninstall of removed components
	if !a.DryRun {
		if a.Verbose {
			fmt.Printf("🔍 Checking for removed components to uninstall...\n")
		}
		uninstallResults, err := componentManager.UninstallRemovedComponents()
		if err != nil {
			fmt.Fprintf(os.Stderr, "Warning: failed to uninstall removed components: %v\n", err)
		} else if len(uninstallResults) > 0 {
			if a.Verbose {
				fmt.Printf("📦 Found %d removed components to uninstall\n", len(uninstallResults))
			}
			fmt.Println("\nUninstalled removed components:")
			a.printResults("Uninstall", uninstallResults)
		} else if a.Verbose {
			fmt.Printf("✓ No removed components found\n")
		}
	}

	return nil
}

func (a *App) printResults(operation string, results []component.InstallResult) {
	if len(results) == 0 {
		fmt.Printf("No components to %s\n", strings.ToLower(operation))
		return
	}

	if a.Verbose {
		a.printVerboseResults(operation, results)
	} else {
		a.printQuietResults(operation, results)
	}
}

func (a *App) printVerboseResults(operation string, results []component.InstallResult) {
	fmt.Printf("\n┌─ %s Results (%d components) ─\n", operation, len(results))
	
	for _, result := range results {
		// Component header with better formatting
		if result.Skipped {
			fmt.Printf("│\n├─ 📦 %s\n│  └─ %s\n", result.Component.FullName(), ui.Skip("Skipped (no changes detected)"))
			continue
		}

		fmt.Printf("│\n├─ 📦 %s\n", result.Component.FullName())
		
		// Track timing and details
		steps := 0
		
		// Install step
		if result.InstallResult != nil {
			steps++
			if result.InstallResult.Success {
				fmt.Printf("│  ├─ %s Install: %s\n", ui.Success(""), result.InstallResult.String())
				if result.InstallResult.Output != "" {
					fmt.Printf("│  │  └─ 📄 Output: %s\n", strings.TrimSpace(result.InstallResult.Output))
				}
			} else {
				fmt.Printf("│  ├─ %s Install: %s\n", ui.Error(""), result.InstallResult.String())
				if result.InstallResult.Error != nil {
					fmt.Printf("│  │  └─ ❌ Error: %s\n", ui.RedText(result.InstallResult.Error.Error()))
				}
			}
		}

		// Link steps
		for _, linkResult := range result.LinkResults {
			steps++
			if linkResult.WasSuccessful() {
				fmt.Printf("│  ├─ %s Link: %s\n", ui.Success(""), linkResult.String())
			} else {
				fmt.Printf("│  ├─ %s Link: %s\n", ui.Error(""), linkResult.String())
				if linkResult.Error != nil {
					fmt.Printf("│  │  └─ ❌ Error: %s\n", ui.RedText(linkResult.Error.Error()))
				}
			}
		}

		// Post-install hook
		if result.PostInstallResult != nil {
			steps++
			if result.PostInstallResult.Success {
				fmt.Printf("│  ├─ %s Post-install: %s\n", ui.Success(""), result.PostInstallResult.String())
				if result.PostInstallResult.Output != "" {
					fmt.Printf("│  │  └─ 📄 Output: %s\n", strings.TrimSpace(result.PostInstallResult.Output))
				}
			} else {
				fmt.Printf("│  ├─ %s Post-install: %s\n", ui.Error(""), result.PostInstallResult.String())
				if result.PostInstallResult.Error != nil {
					fmt.Printf("│  │  └─ ❌ Error: %s\n", ui.RedText(result.PostInstallResult.Error.Error()))
				}
			}
		}

		// Post-link hook
		if result.PostLinkResult != nil {
			steps++
			if result.PostLinkResult.Success {
				fmt.Printf("│  ├─ %s Post-link: %s\n", ui.Success(""), result.PostLinkResult.String())
				if result.PostLinkResult.Output != "" {
					fmt.Printf("│  │  └─ 📄 Output: %s\n", strings.TrimSpace(result.PostLinkResult.Output))
				}
			} else {
				fmt.Printf("│  ├─ %s Post-link: %s\n", ui.Error(""), result.PostLinkResult.String())
				if result.PostLinkResult.Error != nil {
					fmt.Printf("│  │  └─ ❌ Error: %s\n", ui.RedText(result.PostLinkResult.Error.Error()))
				}
			}
		}

		// Defaults
		for _, defaultsResult := range result.DefaultsResults {
			steps++
			fmt.Printf("│  ├─ ⚙️  Defaults: %s\n", defaultsResult.String())
		}

		// Overall result
		if result.Error != nil {
			fmt.Printf("│  └─ ❌ Failed: %s\n", ui.RedText(result.Error.Error()))
		} else {
			fmt.Printf("│  └─ %s Completed successfully (%d steps)\n", ui.GreenText("✅"), steps)
		}
	}
	
	successful := 0
	failed := 0
	skipped := 0
	
	for _, result := range results {
		if result.Skipped {
			skipped++
		} else if result.WasSuccessful() {
			successful++
		} else {
			failed++
		}
	}
	
	fmt.Printf("│\n└─ 📊 Summary: %d successful, %d failed, %d skipped\n\n", successful, failed, skipped)
}

func (a *App) printQuietResults(operation string, results []component.InstallResult) {
	// This method is now deprecated in favor of the live progress in InstallComponentsWithProgress
	// But keep it for backward compatibility or other use cases
	a.printSummaryResults(operation, results)
}

func (a *App) printSummaryResults(operation string, results []component.InstallResult) {
	successful := 0
	failed := 0
	skipped := 0
	
	// Print individual component results - show ALL components
	for _, result := range results {
		if result.Skipped {
			fmt.Printf("%s %s\n", ui.Skip(""), result.Component.FullName())
			skipped++
		} else if result.WasSuccessful() {
			fmt.Printf("%s %s\n", ui.Success(""), result.Component.FullName())
			successful++
		} else {
			fmt.Printf("%s %s: %v\n", ui.Error(""), result.Component.FullName(), result.Error)
			failed++
		}
	}
	
	// Final summary
	if successful > 0 || failed > 0 || skipped > 0 {
		fmt.Printf("\n%s completed: %d successful", operation, successful)
		if failed > 0 {
			fmt.Printf(", %d failed", failed)
		}
		if skipped > 0 {
			fmt.Printf(", %d skipped", skipped)
		}
		fmt.Printf("\n")
	}
}

func (a *App) removeProfileCommand(profileName string) error {
	stateManager, err := state.NewManager()
	if err != nil {
		return fmt.Errorf("failed to create state manager: %w", err)
	}

	activeProfiles := stateManager.GetActiveProfiles()
	newProfiles := make([]string, 0, len(activeProfiles))

	found := false
	for _, profile := range activeProfiles {
		if profile != profileName {
			newProfiles = append(newProfiles, profile)
		} else {
			found = true
		}
	}

	if !found {
		return fmt.Errorf("profile '%s' is not currently active", profileName)
	}

	stateManager.SetActiveProfiles(newProfiles)
	if err := stateManager.Save(); err != nil {
		return fmt.Errorf("failed to save state: %w", err)
	}

	fmt.Printf("Removed profile '%s' from active profiles\n", profileName)
	return nil
}

func upgradeCommand(verbose bool) error {
	if verbose {
		fmt.Printf("🚀 Starting upgrade process...\n")
		fmt.Printf("   Repository: https://github.com/pablopunk/dot\n")
		fmt.Printf("   Script: https://raw.githubusercontent.com/pablopunk/dot/main/scripts/install.sh\n")
		fmt.Printf("   Method: curl + bash\n\n")
		fmt.Printf("📥 Downloading and installing latest version...\n")
	} else {
		// Use animated progress for quiet mode
		progressManager := ui.NewProgressManager(false)
		defer progressManager.StopAll()
		
		upgradeProgress := progressManager.NewSection("Downloading and installing latest version...")
		upgradeProgress.Start()
		
		// Download and run the install script
		cmd := exec.Command("sh", "-c", "curl -fsSL https://raw.githubusercontent.com/pablopunk/dot/main/scripts/install.sh | bash")
		cmd.Stdout = nil
		cmd.Stderr = nil

		if err := cmd.Run(); err != nil {
			upgradeProgress.Fail("Upgrade failed")
			return fmt.Errorf("upgrade failed: %w", err)
		}

		upgradeProgress.Complete("Upgrade completed successfully!")
		return nil
	}

	// Download and run the install script for verbose mode
	cmd := exec.Command("sh", "-c", "curl -fsSL https://raw.githubusercontent.com/pablopunk/dot/main/scripts/install.sh | bash")
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr

	if err := cmd.Run(); err != nil {
		return fmt.Errorf("upgrade failed: %w", err)
	}

	fmt.Printf("\n%s\n", ui.Success("Upgrade completed successfully!"))
	return nil
}

func listProfilesCommand() error {
	cfg, err := config.Load("dot.yaml")
	if err != nil {
		return fmt.Errorf("failed to load config: %w", err)
	}

	stateManager, err := state.NewManager()
	if err != nil {
		return fmt.Errorf("failed to create state manager: %w", err)
	}

	activeProfiles := make(map[string]bool)
	for _, profile := range stateManager.GetActiveProfiles() {
		activeProfiles[profile] = true
	}

	fmt.Println("Available profiles:")
	for name := range cfg.Profiles {
		status := ""
		if activeProfiles[name] {
			status = " (active)"
		}
		fmt.Printf("  %s%s\n", name, status)
	}

	if len(activeProfiles) > 0 {
		fmt.Println("\nActive profiles:")
		for profile := range activeProfiles {
			fmt.Printf("  %s\n", profile)
		}
	}

	return nil
}
