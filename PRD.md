# Product Requirements Document (PRD) for "dot" Tool

## 1. Overview

- **Primary Goal:**
  Manage a single repository of dotfiles and replicate configurations across multiple computers and operating systems (macOS and Linux) with zero dependencies beyond a single compiled binary. Installation should be simple via a one-liner `curl` command.

- **Target User:**
  Developers, sysadmins, and power users who want a minimal, dependency-free tool to synchronize dotfiles and environment setups across machines.

## 2. Core Functionality

- Support multiple profiles with components specifying installation, linking, and configuration.
- Install software or tools using user-defined commands keyed by package manager/tool names (e.g., `brew`, `apt`).
- Detect available package managers/tools by checking for their binaries (`which brew`, `which apt`), and use the first available command.
- Support OS restrictions for components: only install components matching the current OS (`mac`/`darwin` or `linux`). If no OS is specified, install on all.
- Link configuration files/directories using `ln -s` without prompting or backing up existing files.
- Run optional post-install and post-link shell commands.
- Optionally uninstall components that were previously installed but removed from the config, using uninstall commands if provided.
- Maintain a persistent state file (`~/.local/state/dot/lock.yaml`) to track installed components and detect changes.
- Support a dry-run mode to preview actions without making changes.

## 3. Input Specification

- `dot.yaml` structured with profiles at the top level.
- Profiles are defined as:

```yaml
profiles:
  "*":  # Modules always installed on any machine
    bash:
      link:
        "bash/.bashrc": "~/.bashrc"
        "bash/.bash_profile": "~/.bash_profile"
    git:
      link:
        "git/.gitconfig": "~/.gitconfig"
      install:
        brew: "brew install git"
        apt: "apt install -y git"

  work:  # Modules installed only on work machines
    vpn:
      install:
        brew: "brew install --cask viscosity"
        apt: "apt install -y openvpn"
      postinstall: "cp ~/dotfiles/vpn/config.ovpn ~/.config/vpn/"
    docker:
      install:
        brew: "brew install docker"
        apt: "apt install -y docker.io"
      os: ["linux"]  # Only install on Linux

  laptop:
    battery:
      install:
        brew: "brew install --cask battery-guardian"
      os: ["mac"]  # Only install on macOS
    spotify:
      install:
        brew: "brew install --cask spotify"
        apt: "snap install spotify"
```

- Each profile contains components.
- Each component can have:
  - `install`: map of package manager/tool names to install commands.
  - `uninstall`: map of package manager/tool names to uninstall commands.
  - `link`: map of source paths (relative to repo) to target paths.
  - `postinstall`: shell command to run after installation.
  - `postlink`: shell command to run after linking.
  - `os`: list of OS names (`mac` or `linux`) to restrict installation.
  - `defaults`: map of macOS app identifiers to plist or XML files for system defaults (macOS only).

## 4. Installation Process

- Detect OS and available package managers/tools.
- For each component in the active profile(s):
  - Skip if OS restriction does not match.
  - Check if component is already installed (based on lock file).
  - If not installed, run the first available install command.
  - Link config files/directories using `ln -s`.
  - Run post-install and post-link commands.
- On subsequent runs, detect removed components and run uninstall commands if available.

## 5. User Interaction

- CLI interface with commands such as:
  - `dot install` to install and link components.
  - `dot uninstall` to uninstall removed components.
  - `dot dry-run` to preview actions.
  - `dot --profiles` to list available profiles.
  - `dot --upgrade` to upgrade the tool.
  - `dot --remove-profile [profile]` to remove a profile from the active set.
- Profiles:
  - The default profile `"*"` is always installed.
  - Named profiles are installed only if explicitly specified.
  - Profiles are persistent and saved in the lock file.
  - Multiple profiles can be installed at once.
- Module fuzzy search:
  - If the first argument is not a profile or flag, it is treated as a fuzzy search for a module/component name.
- Verbosity:
  - `-v` or `--verbose` prints detailed info.
  - Default output is minimal, showing only modules being processed.
- Install/uninstall behavior:
  - By default, install only runs if files/configs differ from the last run.
  - Uninstall runs only for components present in the lock file but removed from the repo, or if `--uninstall` is specified.
  - `--install` forces reinstall regardless of changes.

## 6. Hooks

- Each module/component can define two optional hooks:
  - **postinstall:** Runs only if the install command was executed during the current run.
  - **postlink:** Runs only if linking was performed during the current run.
- Hooks allow modules to perform additional setup or configuration conditionally.

## 7. macOS Defaults Handling

- Supports a `defaults` section per module mapping macOS app identifiers to plist or XML files.
- On macOS only, the tool can:
  - Export current app preferences to plist files using `defaults export` (via `--defaults-export` or `-e`).
  - Import preferences from plist files using `defaults import` (via `--defaults-import` or `-i`).
  - During normal runs, compares current system defaults with plist files and warns if they differ.
- Resolves relative plist paths relative to the module directory.
- Export/import commands ensure parent directories exist and handle errors gracefully.
- This feature is macOS-specific and skipped on Linux or other OSes.

## 8. Installation and Upgrade

- Installation via a single command:
  ```bash
  curl -fsSL https://raw.githubusercontent.com/pablopunk/dot/main/scripts/install.sh | bash
  ```
- The install script:
  - Installs the `dot` executable into `~/.local/bin`.
  - Creates `~/.local/bin` if it does not exist.
  - Adds `~/.local/bin` to the user's PATH in shell profiles if needed.
  - Ensures `dot` is immediately available in the current shell session.
  - Compatible with bash and zsh on macOS and Linux.
- Upgrade via:
  ```bash
  dot --upgrade
  ```
  - Re-runs the installation script to replace the existing `dot` executable.

## 9. Security and Safety

- No automatic backups of existing files when linking (unless forced).
- User responsible for writing safe install/uninstall commands.
- No elevated permissions assumed; user must run with appropriate rights.

## 10. Output and Reporting

- Summary of installed, linked, and uninstalled components.
- Lock file (`~/.local/state/dot/lock.yaml`) to track state and optimize future runs.

## 11. Testing Framework

- Comprehensive testing suite that validates all features without modifying the actual system.
- Tests should run in a sandboxed environment with:
  - A mock home directory to verify linking operations.
  - Simulated package manager commands that record calls without actually installing software.
  - Mocked OS detection to test platform-specific behavior.
  - Verification of lock file creation and updates.
- Test coverage should include:
  - Profile selection and activation.
  - Component installation, linking, and uninstallation.
  - Hook execution and conditional logic.
  - OS-specific features (especially macOS defaults handling).
  - Error handling and recovery.
- Integration tests should validate the entire workflow from configuration parsing to execution.
- The testing framework should be able to run in CI environments for automated validation.

## 12. Implementation Plan

### Technology Stack
- **Language**: Go (Golang)
  - Chosen for its ability to compile to a single static binary with no runtime dependencies
  - Cross-platform support for macOS and Linux
  - Strong standard library for file operations, command execution, and YAML parsing

### Development Approach
- Modular architecture with clear separation of concerns:
  - Configuration parsing (YAML handling)
  - Profile and component management
  - OS detection and package manager discovery
  - File linking and operations
  - Command execution
  - State management (lock file)
- Use Go's testing framework for unit and integration tests
- Implement mocks for filesystem, command execution, and OS detection to enable testing without system modification

### Build and Distribution
- Set up a cross-compilation pipeline to build binaries for:
  - macOS (amd64, arm64)
  - Linux (amd64, arm64, arm)
- Automate the build process with GitHub Actions or similar CI/CD tool
- Version binaries using semantic versioning
- Host binaries on GitHub Releases for easy access

### Installation
- Create a simple bash installation script that:
  - Detects the OS and architecture
  - Downloads the appropriate binary
  - Places it in `~/.local/bin/`
  - Makes it executable
  - Updates PATH if necessary
- The script should be installable via the one-liner:
  ```bash
  curl -fsSL https://raw.githubusercontent.com/pablopunk/dot/main/scripts/install.sh | bash
  ```

### Project Structure
```
dot/
├── cmd/
│   └── dot/
│       └── main.go       # Entry point
├── internal/
│   ├── config/           # YAML parsing and config handling
│   ├── profile/          # Profile management
│   ├── component/        # Component operations
│   ├── system/           # OS detection and package manager discovery
│   ├── link/             # File linking operations
│   ├── exec/             # Command execution
│   └── state/            # Lock file management
├── pkg/                  # Public API (if needed)
├── scripts/
│   └── install.sh        # Installation script
└── test/
    ├── fixtures/         # Test data
    └── integration/      # Integration tests
```

## 13. Conclusion and Next Steps

The "dot" tool represents a significant improvement over existing dotfile management solutions by providing a zero-dependency, cross-platform solution that is easy to install and use. By implementing the tool in Go, we can achieve the perfect balance of functionality, performance, and ease of distribution.

### Key Advantages
- **Zero Dependencies**: A single compiled binary with no external requirements
- **Cross-Platform**: Works identically on macOS and Linux
- **Simple Installation**: One-line curl command to install
- **Flexible Configuration**: Profile-based approach for different machine types
- **Comprehensive Testing**: Full test coverage without system modification

### Next Steps
1. **Initial Development**:
   - Set up the Go project structure
   - Implement core YAML parsing and configuration handling
   - Develop the profile and component management system

2. **Feature Implementation**:
   - Build the linking system
   - Implement package manager detection and command execution
   - Create the state management system for tracking installations

3. **Testing and Refinement**:
   - Develop the testing framework
   - Write comprehensive tests for all features
   - Refine based on test results

4. **Build and Distribution**:
   - Set up cross-compilation
   - Create the installation script
   - Test installation on various platforms

5. **Documentation and Release**:
   - Write user documentation
   - Create example configurations
   - Release version 1.0

This PRD provides a comprehensive roadmap for developing the "dot" tool, from concept to implementation. The modular design and clear separation of concerns will make the codebase maintainable and extensible, while the Go implementation ensures a fast, reliable tool with minimal dependencies.

---

This PRD covers the full scope and behavior of the "dot" tool as discussed. Let me know if you'd like me to add or adjust anything, or if you want me to start planning the implementation steps next.
