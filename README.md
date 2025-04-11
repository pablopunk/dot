# `dot`

<p align="center">
  <img src="https://github.com/user-attachments/assets/3984a5c4-67f7-4f0e-a4dd-6ebdec323b49#gh-light-mode-only" width="600px" />
  <img src="https://github.com/user-attachments/assets/3733f2ea-b640-4d6c-b750-b2393638fd90#gh-dark-mode-only" width="600px" />
</p>

> Manage your apps, dotfiles, preferences, and their dependencies automagically

## Table of Contents

- [Installation](#installation)
- [Quick Start](#quick-start)
- [Usage](#usage)
  - [Modules](#modules)
  - [Dependencies](#dependencies)
  - [Dotfiles](#dotfiles)
  - [OS Restrictions](#os-restrictions)
  - [macOS Preferences (defaults)](#macos-preferences-defaults)
  - [Profiles](#profiles)
  - [Force Mode `-f`](#force-mode--f)
  - [Unlinking Configs `--unlink`](#unlinking-configs---unlink)
  - [Purging Modules `--purge`](#purging-modules---purge)
  - [Hooks](#hooks)
- [Summary of Command-Line Options](#summary-of-command-line-options)
- [Examples](#examples)
- [To do](#to-do)

## Installation

```bash
$ brew install pablopunk/brew/dot
```

## Quick Start

<img src="https://github.com/user-attachments/assets/8c235cb8-d6c5-4f9c-88db-db1a04e914e4" width="600px" />

```bash
$ cd /path/to/dotfiles
$ tree

profiles/
├── work.lua
├── personal.lua
├── linux-server.lua
modules/
├── neovim/
│   ├── init.lua
│   └── config/
├── zsh/
│   ├── init.lua
│   └── zshrc
└── apps/
    ├── work/
    │   └── init.lua
    └── personal/
        └── init.lua

$ dot          # Link all dotfiles and install dependencies
$ dot neovim   # Only process the 'neovim' module
$ dot work     # Only process the 'work' profile
```

## Usage

### Modules

Each module under the `modules/` folder needs to have at least an `init.lua`. If not, it will be ignored. **Modules can be recursive**, meaning you can have nested directories within the `modules/` folder, and each can contain its own `init.lua` to define configurations and dependencies.

#### `init.lua`

Example for neovim:

```lua
-- modules/neovim/init.lua
return {
  brew = {
    { name = "neovim", options = "--HEAD" },
    "ripgrep"
  },
  config = {
    source = "./config",       -- Our config directory within the module
    output = "~/.config/nvim", -- Where the config will be linked to
  }
}
```

### Dependencies

#### Brew

As you can see, you can declare dependencies as [Homebrew](https://brew.sh) packages, which makes it possible to also use `dot` to install GUI apps (Homebrew casks). You can create a module without any config to use it as an installer for your apps:

```lua
-- modules/apps/init.lua
return {
  brew = { "whatsapp", "spotify", "slack", "vscode" }
}
```

#### Wget

`dot` now supports downloading files using `wget`. This can be useful for fetching binaries or other resources that are not available through Homebrew. You can specify a `wget` configuration in your module's `init.lua` file.

Example:

```lua
-- modules/apps/init.lua
return {
  wget = {
    {
      url = "https://app1piece.com/1Piece-4.2.1.zip",
      output = "/Applications/1Piece.app",
      zip = true,
    },
    {
      url = "https://fakedomain.com/fake.app",
      output = "/Applications/Fake.app",
    },
  },
}
```

> [!NOTE]
> When using `zip = true`, make sure the output file name matches the unzipped file name. In the example above, the output is `/Applications/1Piece.app` because the zip file contains a file named `1Piece.app`.


### Dotfiles

The config will be linked to the home folder with a soft link. In this case:

```bash
~/.config/nvim → ~/dotfiles/modules/neovim/config
```

You can also specify multiple configurations for a single module:

```lua
-- modules/multi-config/init.lua
return {
  brew = { "cursor" },
  config = {
    {
      source = "./config/settings.json",
      output = "~/Library/Application Support/Cursor/User/settings.json",
    },
    {
      source = "./config/keybindings.json",
      output = "~/Library/Application Support/Cursor/User/keybindings.json",
    }
  }
}
```

This will create two symlinks:

```bash
~/Library/Application Support/Cursor/User/settings.json → ~/dotfiles/modules/multi-config/config/settings.json
~/Library/Application Support/Cursor/User/keybindings.json → ~/dotfiles/modules/multi-config/config/keybindings.json
```
### OS Restrictions

You can restrict modules to specific operating systems using the `os` field in your module's `init.lua`:

```lua
-- modules/macos-only/init.lua
return {
  os = { "mac" },  -- This module will only run on macOS
  brew = { "mac-specific-app" },
  config = {
    source = "./config",
    output = "~/.config/mac-specific-app",
  }
}
```

You can also specify multiple operating systems for a module:

```lua
return {
  os = { "mac", "linux" },  -- This module will run on both macOS and Linux
  config = {
    source = "./config",
    output = "~/.config/cross-platform-app",
  }
}
```

The module will be automatically skipped when run on non-matching operating systems. 
Supported OS values:
- `"mac"`, `"macos"`, or `"darwin"` for macOS
- `"linux"` for Linux systems
- `"windows"` for Windows systems


### macOS Preferences (defaults)

You can manage macOS application preferences using the `defaults` field in your module's `init.lua`. This allows you to export and import application preferences to and from plist files. Since macOS `defaults` don't play nice with symlinks, you'll need to run `dot` every time you want to update/import the preferences. But don't worry, it's easy:

Example:

```lua
-- modules/defaults_test/init.lua
return {
  defaults = {
    {
      plist = "./defaults/SwiftShift.plist",
      app = "com.pablopunk.Swift-Shift", -- Info on how to get this below
    }
  }
}
```

> [!NOTE]
> To find the app id, you can run `defaults domains | tr ', ' '\n' | grep -i <app-name>`.

#### Human-readable format

`dot` now supports human-readable XML format for preferences by using a `.xml` extension:

```lua
return {
  defaults = {
    {
      plist = "./defaults/SwiftShift.xml",
      app = "com.pablopunk.Swift-Shift",
    }
  }
}
```

XML files are much easier to read, compare, and track changes with version control compared to binary plist files.


https://github.com/user-attachments/assets/173d882c-3fb5-4fe1-bce4-4ac8fa6be7f0


The first time you run this without any files, it will export the current preferences to the plist file.

Whenever you want them to be exported again, run:

```bash
$ dot defaults_test --defaults-export
```

To import the preferences from the saved file, run:

```bash
$ dot defaults_test --defaults-import
```

By default, `dot` will only alert you that your saved preferences differ from the current ones.
It's up to you to choose which one you want to keep.

### Profiles

If you have several machines, you might not want to install all tools on every computer. That's why `dot` allows **profiles**.

Let's create a new "personal" profile:

```lua
-- profiles/personal.lua
return {
  modules = {
    "*",
    "!apps/work",
  }
}
```

In this example, running `dot personal` will:

- `*`: Install everything under `modules/`, including nested directories.
- `!apps/work`: Exclude the `apps/work` module and its submodules.

You can use the following patterns in your profile:

- `"*"`: Include all modules recursively.
- `"!module_name"`: Exclude a specific module and its submodules.
- `"module_name"`: Include a specific module.

For example, a work profile might look like this:

```lua
-- profiles/work.lua
return {
  modules = {
    "apps/work",
    "slack",
    "neovim",
    "zsh"
  }
}
```

> [!NOTE]
> If your profile is named just like a module (e.g., `profiles/neovim` and `modules/neovim`), running `dot neovim` will default to the profile.

#### Profiles are persistent

When you run `dot <profile-name>`, it will remember it, so next time you only need to run `dot` to use the same profile.

```bash
$ dot work
...installing work profile...

$ dot
...installing work profile again...
```

To get rid of the last profile used, select any other profile or run:

```bash
$ dot --remove-profile
```

### Force Mode `-f`

By default, `dot` won't touch your existing dotfiles if the destination already exists. If you still want to replace them, you can use the `-f` flag:

```bash
$ dot -f neovim
```

> [!NOTE]
> It won't remove the existing config but will move it to a new path: `<path-to-config>.before-dot`.

### Unlinking Configs `--unlink`

If you want to remove the symlinks created by `dot` for a specific module but keep your configuration, you can use the `--unlink` option:

```bash
$ dot --unlink neovim
```

This command will:

- Remove the symlink at the destination specified in `config.output`.
- Copy the config source from `config.source` to the output location.

This is useful if you want to maintain your configuration files without `dot` managing them anymore.

### Purging Modules `--purge`

To completely remove a module, including uninstalling its dependencies and removing its configuration, use the `--purge` option:

```bash
$ dot --purge neovim
```

This command will:

- Uninstall the Homebrew dependencies listed in the module's `init.lua`.
- Remove the symlink or config file/directory specified in `config.output`.
- Run any `post_purge` hooks if defined in the module.

> [!WARNING]
> `--purge` will uninstall packages from your system and remove configuration files. Use with caution.

### Hooks

You can define `post_install` and `post_purge` hooks in your module's `init.lua` to run arbitrary commands after the module has been installed or purged.

```lua
return {
  brew = { "gh" },
  post_install = "gh auth login"
}
```

You can also define multi-line hooks:

```lua
return {
  brew = { "gh" },
  post_install = [[
    gh auth status | grep 'Logged in to github.com account' > /dev/null || gh auth login --web -h github.com
    gh extension list | grep gh-copilot > /dev/null || gh extension install github/gh-copilot
  ]],
}
```

## Summary of Command-Line Options

- **Install Modules**: Install dependencies and link configurations.

  ```bash
  $ dot             # Install all modules
  $ dot neovim      # Install only the 'neovim' module
  $ dot work        # Install only the 'work' profile
  ```

- **Force Mode**: Replace existing configurations, backing them up to `<config>.before-dot`.

  ```bash
  $ dot -f          # Force install all modules
  $ dot -f neovim   # Force install the 'neovim' module
  ```

- **Unlink Configs**: Remove symlinks but keep the config files in their destination.

  ```bash
  $ dot --unlink neovim
  ```

- **Purge Modules**: Uninstall dependencies and remove configurations.

  ```bash
  $ dot --purge neovim
  ```

- **Defaults Export/Import**: Manage macOS application preferences.

  ```bash
  $ dot defaults_test --defaults-export  # Export app preferences to plist
  $ dot defaults_test --defaults-import  # Import app preferences from plist
  ```

## Examples

- [pablopunk/dotfiles](https://github.com/pablopunk/dotfiles): my own dotfiles, using `dot` to manage them.

## To do

- [x] `dot` will install dependencies and link files.
- [x] Support Homebrew dependencies.
- [x] `dot -f` will remove the existing configs if they exist (moves config to `*.before-dot`).
- [x] Allow post-install hooks in bash.
- [x] Allow installing only one module with `dot neovim`.
- [x] Allow multiple setups in one repo. Similar to "hosts" in Nix, `dot work` reads `profiles/work.lua` which includes whatever it wants from `modules/`.
- [x] Package and distribute `dot` through Homebrew.
- [x] Add `--unlink` option to remove symlinks and copy configs to output.
- [x] Add `--purge` option to uninstall dependencies and remove configurations.
- [x] Allow array of config. For example I could like two separate folders that are not siblings
- [x] Improve profiles syntax. For example, `{ "*", "apps/work" }` should still be recursive except in "apps/". Or maybe accept negative patterns like `{ "!apps/personal" }` -> everything but apps/personal.
- [x] Add screenshots to the README.
- [ ] Support more ways of adding dependencies (e.g., wget binaries, git clone, apt...).
  - [x] wget
  - [ ] git clone
  - [ ] apt
- [ ] Unlinking dotfiles without copying. An option like `dot --unlink --no-copy` could be added.
- [ ] `dot --purge-all` to purge all modules at once.
- [x] Support Mac defaults, similar to `nix-darwin`.
  - [x] Add tests
  - [x] Ignore on linux
  - [x] Add cog images to the header so it's easier to tell that it's not only about plaintext dotfiles
- [x] Support an `os` field. i.e `os = { "mac" }` will be ignored on Linux.
- [x] After using a profile, like `dot profile1`, it should remember it and all calls to `dot` should be done with this profile unless another profile is explicitely invoked, like `dot profile2`, which will replace it for the next invokations.
