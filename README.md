# dot - all your computers in one repo

> All your tools, apps, and configs with 0 dependencies

## Highlights ✨

- **Zero Dependencies**: Single compiled binary with no external requirements.
- **Cross-Platform**: Works on macOS and Linux.
- **Profile-Based**: Organize configurations for different machine types (work, laptop, etc.)
- **Install anything**: Run any shell command for installation - brew, apt, dnf, wget, curl, anything!
- **Idempotent**: Run it twice and you'll see.
- **macOS Preferences**: Yes! You can import/export GUI apps settings.

## Installation 🚀

Install with a single command:

```bash
curl -fsSL https://raw.githubusercontent.com/pablopunk/dot/main/scripts/install.sh | bash
```

This will:
- Download the latest release for your platform
- Install to `~/.local/bin/dot`
- Update your shell profile to include `~/.local/bin` in PATH

## Quick Start

1. Create a `dot.yaml` file in your dotfiles repository:

```yaml
profiles:
  "*":        # Always installed on every machine
    - bash
    - git
  
  work:       # Only on your work computer
    - vpn
    - ssh

config:
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
  
  vpn:
    install:
      brew: "brew install --cask viscosity"
      apt: "apt install -y openvpn"
  
  ssh:
    link:
      "ssh/config": "~/.ssh/config"
```

2. Run dot to install the default profile:

```bash
dot
```

3. Install a specific profile:

```bash
dot work
```

4. Install multiple profiles at once:

```bash
dot work laptop
```

## Configuration

### Profile Structure

Profiles are simple lists of tool names. Each tool is configured in the `config` section:

```yaml
profiles:
  "*":              # Always installed (special profile)
    - git
    - vim
    - zsh
  
  work:             # Named profile (installed when requested)
    - docker
    - slack
  
  gui:
    - apps          # Can reference nested config containers

config:
  git:              # Tool configuration
    install:        # Installation commands (any shell command)
      brew: "brew install git"
      apt: "apt install -y git"
      wget: "wget https://example.com/git.zip -O /Applications/git.zip"
    uninstall:      # Optional uninstall commands
      brew: "brew uninstall git"
      apt: "apt remove -y git"
    link:           # File/directory linking
      "source/path": "~/target/path"
    postinstall:    # Run after successful installation
      "echo 'Installed successfully'"
    postlink:       # Run after successful linking
      "echo 'Linked successfully'"
    os: ["mac"]     # OS restrictions (mac/darwin, linux)
    defaults:       # macOS system defaults (macOS only)
      "com.apple.dock": "macos/dock.plist"
  
  vim:
    link:
      "vim/.vimrc": "~/.vimrc"
      "vim/.vim/": "~/.vim/"
  
  zsh:
    install:
      brew: "brew install zsh"
      apt: "apt install -y zsh"
  
  docker:
    install:
      brew: "brew install docker"
      apt: "apt install -y docker.io"
    postinstall: "sudo usermod -aG docker $USER"
  
  slack:
    os: ["mac"]
    install:
      brew: "brew install slack"
```

### Special Profiles

- `"*"`: Always installed on every machine
- Named profiles (e.g., `work`, `laptop`, `rice`): Only installed on machines where they apply
- You can pass multiple profiles at once (e.g., `dot work laptop`). The `*` profile is always included.
- You can also use profiles with fuzzy search: `dot work git` (installs all tools in `*` and `work` profiles, plus any tool matching "git")


### OS Restrictions

Restrict tools to specific operating systems:

```yaml
profiles:
  "*":
    - mac_only
    - linux_only
    - cross_platform

config:
  mac_only:
    os: ["mac"]     # or ["darwin"]
    install:
      brew: "brew install --cask app"

  linux_only:
    os: ["linux"]
    install:
      apt: "apt install -y package"

  cross_platform:
    # No OS restriction - installs everywhere
    install:
      brew: "brew install tool"
      apt: "apt install -y tool"
```

### Advanced Features

#### Nested Configs

Organize tools in nested structures for better readability:

```yaml
profiles:
  "*":
    - cli      # References a nested config container
  
  gui:
    - apps     # References another nested config container

config:
  cli:         # Container with shell tools
    bash:
      install: {...}
    zsh:
      install: {...}
    git:
      install: {...}
  
  apps:        # Container with GUI applications
    slack:
      install: {...}
    docker:
      install: {...}
    chrome:
      install: {...}
```

When you run `dot gui`, it will install all tools from: `*` + `gui` profiles, automatically expanding `cli` and `apps` containers.

#### Fuzzy Search

Install specific tools by name without specifying profiles:

```bash
# Install any tool matching "git"
dot git

# Install tools matching multiple terms
dot git vim

# Mix profiles and fuzzy search
dot work git    # Installs from *, work profiles, plus any tool matching "git"
```

## Usage

### Basic Commands

```bash
# Install default profile
dot

# Install specific profiles
dot work laptop

# List available profiles
dot --profiles

# Preview changes without applying
dot --dry-run work

# Force reinstall everything
dot --install

# Uninstall removed components
dot --uninstall

# Verbose output
dot -v work
```

### Advanced Usage

```bash
# Fuzzy search for components
dot git     # Installs any component matching "git"

# Remove a profile from active set
dot --remove-profile work

# Run hooks independently
dot --postinstall       # Run only postinstall hooks
dot --postlink          # Run only postlink hooks

# macOS defaults management
dot --defaults-export   # Export current settings to plist/XML files
dot --defaults-import   # Import settings from plist/XML files

# Upgrade dot itself
dot --upgrade
```

## Install Commands

dot can run any shell command for installation. It automatically detects which commands are available on your system and runs the first available one.

You can use any command for installation:

```yaml
profiles:
  "*":
    # Package managers
    node:
      install:
        brew: "brew install node"
        apt: "apt install -y nodejs npm"
        yum: "yum install -y nodejs npm"

    # Direct downloads
    1piece:
      os: ["mac"]
      install:
        wget: "wget https://app1piece.com/1Piece-4.2.1.zip -O /Applications/1Piece.app"
        curl: "curl -L https://app1piece.com/1Piece-4.2.1.zip -o /Applications/1Piece.app"

    # Custom scripts
    custom_tool:
      install:
        bash: "./scripts/install-my-tool.sh"
        python: "python setup.py install"
```

The tool will check if each command exists (using `which`) and run the first available one.

## Hooks

Run custom commands after installation or linking:

```yaml
profiles:
  "*":
    tmux:
      install:
        brew: "brew install tmux"
      postinstall: |
        echo "Setting up tmux..."
        tmux new-session -d -s setup

    vim:
      link:
        "vim/.vimrc": "~/.vimrc"
        "vim/.vim": "~/.vim"
      postlink: |
        echo "Installing vim plugins..."
        vim +PlugInstall +qall
```

### Hook Types

- **`postinstall`**: Runs only if package installation was executed and succeeded in the current run
- **`postlink`**: Runs only if symlink creation was performed and succeeded in the current run

### Running Hooks Independently

You can run hooks without performing full installation:

```bash
# Run only postinstall hooks
dot --postinstall

# Run only postlink hooks
dot --postlink

# Run hooks for specific components
dot git --postinstall    # Run postinstall for git component
dot vim --postlink       # Run postlink for vim component

# Run hooks with dry-run to see what would execute
dot --postinstall --dry-run -v

# Run hooks for specific profiles
dot work --postinstall   # Run postinstall hooks for work profile
```

This is useful for:
- **Testing hooks** during development
- **Re-running configuration** after manual changes
- **Debugging hook failures** without full reinstalls
- **Updating configs** without reinstalling packages

## macOS Defaults

Manage macOS system preferences with plist or XML files:

```yaml
profiles:
  "*":
    dock:
      defaults:
        "com.apple.dock": "macos/dock.plist"
        "com.apple.finder": "macos/finder.xml"        # XML format for better readability
```

Commands:
- `dot --defaults-export`: Export current settings to plist/XML files
- `dot --defaults-import`: Import settings from plist/XML files
- Normal runs will warn if current settings differ from saved files

Files ending in `.xml` are exported as XML format for better readability and version control.

## State Management

dot maintains a state file at `~/.local/state/dot/lock.yaml` to track:
- Installed components and their package managers
- Active profiles
- Link mappings
- Hook execution status
- Install commands used for each component
- Uninstall commands for removed components

This enables:
- **Incremental updates**: Only install/link what's changed
- **Automatic cleanup**: Remove components deleted from config
- **State persistence**: Remember active profiles across runs
- **Efficient linking**: Skip symlinks that already exist and point correctly
- **Smart uninstalls**: Run uninstall commands for components removed from config

## Examples

### Basic Development Setup

```yaml
profiles:
  "*":
    - shell
    - git
    - vim

config:
  shell:
    link:
      "shell/.bashrc": "~/.bashrc"
      "shell/.zshrc": "~/.zshrc"

  git:
    link:
      "git/.gitconfig": "~/.gitconfig"
    install:
      brew: "brew install git"
      apt: "apt install -y git"

  vim:
    link:
      "vim/.vimrc": "~/.vimrc"
    install:
      brew: "brew install vim"
      apt: "apt install -y vim"
```

### Work Machine Profile

```yaml
profiles:
  work:
    - docker
    - vpn
    - kubectl

config:
  docker:
    install:
      brew: "brew install docker"
      apt: "apt install -y docker.io"
    postinstall: "sudo usermod -aG docker $USER"

  vpn:
    install:
      brew: "brew install --cask viscosity"
      apt: "apt install -y openvpn"
    link:
      "work/vpn.conf": "~/.config/vpn/client.conf"

  kubectl:
    install:
      brew: "brew install kubectl"
      curl: "curl -LO https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl && chmod +x kubectl && sudo mv kubectl /usr/local/bin/"
```

### Laptop-Specific Tools

```yaml
profiles:
  laptop:
    - battery
    - wifi

config:
  battery:
    os: ["mac"]
    install:
      brew: "brew install --cask battery-guardian"

  wifi:
    os: ["linux"]
    install:
      apt: "apt install -y network-manager"
```

## Building from Source

Requirements:
- Go 1.21 or later

```bash
# Clone the repository
git clone https://github.com/pablopunk/dot.git
cd dot

# Build for current platform
make build

# Build for all platforms
make build-all

# Run tests
make test

# Install locally
make install
```

## Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature-name`
3. Make your changes and add tests
4. Run tests: `make test`
5. Submit a pull request

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Comparison with Other Tools

| Feature | dot | GNU Stow | chezmoi | dotbot |
|---------|-----|----------|---------|--------|
| Zero dependencies | ✅ | ❌ | ❌ | ❌ |
| Single binary | ✅ | ❌ | ✅ | ❌ |
| Package installation | ✅ | ❌ | ✅ | ✅ |
| Cross-platform | ✅ | ✅ | ✅ | ✅ |
| Profile-based | ✅ | ❌ | ✅ | ❌ |
| State tracking | ✅ | ❌ | ✅ | ❌ |
| Dry run | ✅ | ✅ | ✅ | ❌ |

---

**dot** - Simple, fast, and reliable dotfiles management.
