# `dot`

<p align="center">
  <img src="https://github.com/user-attachments/assets/7dbda7f1-cce5-4183-82c0-f596ac375fa2" width="600px" />
</p>

> Manage your apps, dotfiles, preferences, and their dependencies automagically

## Table of Contents

- [Installation](#installation)
- [Quick Start](#quick-start)
- [Usage](#usage)
  - [Modules](#modules)
  - [Installation System](#installation-system)
  - [Linking Files](#linking-files)
  - [macOS Preferences (defaults)](#macos-preferences-defaults)
  - [OS Restrictions](#os-restrictions)
  - [Profiles](#profiles)
  - [Hooks](#hooks)
- [Command-Line Options](#command-line-options)
- [Examples](#examples)

## Installation

**Option 1: Using curl (installs Lua and dot)**
```bash
curl -fsSL https://raw.githubusercontent.com/pablopunk/dot/main/install.sh | bash
```

**Option 2: Using Homebrew**
```bash
brew install pablopunk/brew/dot
```

The curl installer will:
- Detect your OS (macOS, Linux)
- Install Lua if not present
- Download and install the `dot` tool
- Add it to your PATH

**To update the tool later:**
```bash
dot --update
```

## Quick Start

<img src="https://github.com/user-attachments/assets/8c235cb8-d6c5-4f9c-88db-db1a04e914e4" width="600px" />

```bash
$ cd /path/to/dotfiles
$ tree

profiles.lua # work, personal, server...
neovim/
├── dot.lua
└── config/
zsh/
├── dot.lua
└── zshrc
apps/
├── work/
│   └── dot.lua
└── personal/
    └── dot.lua

$ dot          # Link all dotfiles and install dependencies
$ dot neovim   # Only process the 'neovim' module
$ dot work     # Only process the 'work' profile
```

## Usage

### Modules

Any subdirectory containing a `dot.lua` file is considered a module. **Modules can be nested** - you can have directories within directories, and each can contain its own `dot.lua` to define configurations and dependencies.

#### `dot.lua`

Example for neovim:

```lua
-- neovim/dot.lua
return {
  install = {
    brew = "brew install neovim ripgrep",
    apt = "sudo apt install -y neovim ripgrep"
  },
  check = "nvim --version", -- Check if neovim is already installed
  link = {
    ["./config"] = "~/.config/nvim" -- link the whole directory or just one file, your choice
  }
}
```

### Installation System

The `install` system dynamically detects available package managers and uses the first one found. You can specify multiple package managers, and `dot` will use the first available one.

```lua
-- apps/dot.lua
return {
  install = {
    brew = "brew install whatsapp spotify slack vscode",
    apt = "sudo apt install -y vim git curl",
    yum = "yum install vim git curl"
  }
}
```

In this example, if `brew` is available, it will use that. If not, it will try `apt`, then `yum`.

#### Smart Installation with `check`

To avoid reinstalling tools that are already installed, add a `check` field:

```lua
-- neovim/dot.lua
return {
  install = {
    brew = "brew install neovim ripgrep",
    apt = "sudo apt install -y neovim ripgrep"
  },
  check = "nvim --version", -- Check if neovim is already installed
  link = {
    ["./config"] = "~/.config/nvim"
  }
}
```

The `check` field specifies a command to verify if the tool is already installed. If the command succeeds, `dot` will skip the installation step.

**Examples:**
- `check = "nvim --version"` for Neovim
- `check = "git --version"` for Git
- `check = "node --version"` for Node.js
- `check = "which docker"` for Docker

### Linking Files

The `link` system creates symlinks from your dotfiles to their destinations. Use the new key-value format:

```lua
-- cursor/dot.lua
return {
  install = {
    brew = "brew install cursor"
  },
  link = {
    ["./config/settings.json"] = "~/Library/Application Support/Cursor/User/settings.json",
    ["./config/keybindings.json"] = "~/Library/Application Support/Cursor/User/keybindings.json"
  }
}
```

This creates symlinks:
```bash
~/Library/Application Support/Cursor/User/settings.json → ~/dotfiles/cursor/config/settings.json
~/Library/Application Support/Cursor/User/keybindings.json → ~/dotfiles/cursor/config/keybindings.json
```

### macOS Preferences (defaults)

Manage macOS application preferences using the `defaults` field:

```lua
-- swiftshift/dot.lua
return {
  defaults = {
    ["com.pablopunk.Swift-Shift"] = "./defaults/SwiftShift.xml"
  }
}
```

> [!NOTE]
> To find the app id, run: `defaults domains | tr ', ' '\n' | grep -i <app-name>`

#### XML Format (Recommended)

Use `.xml` extension for human-readable preferences:

```lua
return {
  defaults = {
    ["com.pablopunk.Swift-Shift"] = "./defaults/SwiftShift.xml"
  }
}
```

XML files are easier to read, compare, and track with version control.

#### Export/Import Commands

Export current preferences:
```bash
$ dot swiftshift --defaults-export  # or -e
```

Import preferences from your dotfiles:
```bash
$ dot swiftshift --defaults-import  # or -i
```

### OS Restrictions

Restrict modules to specific operating systems:

```lua
-- macos-only/dot.lua
return {
  os = { "mac" },  -- Only runs on macOS
  install = {
    brew = "brew install mac-specific-app"
  },
  link = {
    ["./config"] = "~/.config/mac-specific-app"
  }
}
```

Supported OS values:
- `"mac"`, `"macos"`, or `"darwin"` for macOS
- `"linux"` for Linux systems
- `"windows"` for Windows systems

### Profiles

Profiles let you manage different setups for different machines. Create a single `profiles.lua` file:

```lua
-- profiles.lua
return {
  personal = {
    "*",           -- Include all modules
    "!apps/work"   -- Exclude work apps
  },
  work = {
    "apps/work",
    "slack",
    "neovim",
    "zsh"
  },
  linux_server = {
    "zsh",
    "neovim",
    "tmux"
  }
}
```

#### Profile Patterns

- `"*"`: Include all modules recursively
- `"!module_name"`: Exclude a specific module and its submodules
- `"module_name"`: Include a specific module

#### Persistent Profiles

Profiles are remembered between runs:

```bash
$ dot work
...installing work profile...

$ dot
...installing work profile again...
```

Remove the current profile:
```bash
$ dot --remove-profile
```

### Hooks

Run commands after installation or linking:

```lua
return {
  install = {
    brew = "brew install gh"
  },
  postinstall = "gh auth login"
}
```

Multi-line hooks:
```lua
return {
  install = {
    brew = "brew install gh"
  },
  postinstall = [[
    gh auth status | grep 'Logged in to github.com account' > /dev/null || gh auth login --web -h github.com
    gh extension list | grep gh-copilot > /dev/null || gh extension install github/gh-copilot
  ]]
}
```

Available hooks:
- `postinstall`: Runs after dependencies are installed
- `postlink`: Runs after files are linked

## Command-Line Options

### Basic Usage
```bash
$ dot             # Install all modules
$ dot neovim      # Install only the 'neovim' module
$ dot work        # Install only the 'work' profile
```

### Force Mode
Replace existing configurations (backs up to `<config>.before-dot`):
```bash
$ dot -f          # Force install all modules
$ dot -f neovim   # Force install the 'neovim' module
```

### Unlink Mode
Remove symlinks but keep config files:
```bash
$ dot --unlink neovim
```

### Defaults Management
```bash
$ dot app -e              # Export app preferences to plist
$ dot app -i              # Import app preferences from plist
```

### Hook Options
```bash
$ dot --postinstall       # Run postinstall hooks even if dependencies haven't changed
$ dot --postlink          # Run postlink hooks even if symlinks haven't changed
```

### Other Options
```bash
$ dot --remove-profile    # Remove the last used profile
$ dot --version           # Show version
$ dot -h                  # Show help
```

## Examples

- [pablopunk/dotfiles](https://github.com/pablopunk/dotfiles): my own dotfiles, using `dot` to manage them.

