# `nos`

<p align="center">
  <img src="https://github.com/user-attachments/assets/c878b7d3-e1f6-49b3-a2c0-25d5e39d1dfa#gh-light-mode-only" width="600px" />
  <img src="https://github.com/user-attachments/assets/64b98236-da26-4f8e-8706-ca27667b5f9c#gh-dark-mode-only" width="600px" />
</p>

> Manage your dotfiles and their dependencies automagically

## Table of Contents
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Usage](#usage)
  - [`init.lua`](#initlua)
  - [Recursive](#recursive)
  - [Profiles](#profiles)
  - [Force Mode `-f`](#force-mode--f)
  - [Unlinking Configs `--unlink`](#unlinking-configs---unlink)
  - [Purging Modules `--purge`](#purging-modules---purge)
- [To do](#to-do)

## Installation

> [!WARNING]
> This package is still a work in progress. Use at your own risk.

```bash
$ brew install pablopunk/brew/nos
```

## Quick Start

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

$ nos          # Link all dotfiles and install dependencies
$ nos neovim   # Only process the 'neovim' module
$ nos work     # Only process the 'work' profile
```

## Usage

Each module under the `modules/` folder needs to have at least an `init.lua`. If not, it will be ignored.

### `init.lua`

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

As you can see, you can declare dependencies as [Homebrew](https://brew.sh) packages, which makes it possible to also use `nos` to install GUI apps (Homebrew casks). You can create a module without any config to use it as an installer for your apps:

```lua
-- modules/apps/init.lua
return {
  brew = { "whatsapp", "spotify", "slack", "vscode" }
}
```

### Recursive

In the example above, let's say we want to separate our apps into "work" and "personal". We could either create 2 modules on the root folder or create a nested folder for each:

```lua
-- modules/apps/work/init.lua
return {
  brew = { "slack", "vscode" }
}
```

```lua
-- modules/apps/personal/init.lua
return {
  brew = { "whatsapp", "spotify" }
}
```

### Profiles

If you have several machines, you might not want to install all tools on every computer. That's why `nos` allows **profiles**.

Let's create a new "work" profile:

```lua
-- profiles/work.lua
return {
  modules = {
    "apps/work",
    "*",
  }
}
```

In this example, using the directories we created in the [Recursive](#recursive) section, running `nos work` will:

- `apps/work`: Install only our work apps under `modules/apps/work/init.lua`.
- `*`: Install everything else under `modules/*`, except nested directories (so it won't install `apps/work`).

> [!NOTE]
> Once `nos` detects an `init.lua`, it will stop going through the subdirectories inside that folder.

> [!NOTE]
> You probably don't want to name a profile the same as a module (e.g., `profiles/neovim` vs. `modules/neovim`) since running `nos neovim` will default to the profile.

### Force Mode `-f`

By default, `nos` won't touch your existing dotfiles if the destination already exists. If you still want to replace them, you can use the `-f` flag:

```bash
$ nos -f neovim
```

> [!NOTE]
> It won't remove the existing config but will move it to a new path: `<path-to-config>.before-nos`.

### Unlinking Configs `--unlink`

If you want to remove the symlinks created by `nos` for a specific module but keep your configuration, you can use the `--unlink` option:

```bash
$ nos --unlink neovim
```

This command will:

- Remove the symlink at the destination specified in `config.output`.
- Copy the config source from `config.source` to the output location.

This is useful if you want to maintain your configuration files without `nos` managing them anymore.

### Purging Modules `--purge`

To completely remove a module, including uninstalling its dependencies and removing its configuration, use the `--purge` option:

```bash
$ nos --purge neovim
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

### Summary of Command-Line Options

- **Install Modules**: Install dependencies and link configurations.

  ```bash
  $ nos             # Install all modules
  $ nos neovim      # Install only the 'neovim' module
  $ nos work        # Install only the 'work' profile
  ```

- **Force Mode**: Replace existing configurations, backing them up to `<config>.before-nos`.

  ```bash
  $ nos -f          # Force install all modules
  $ nos -f neovim   # Force install the 'neovim' module
  ```

- **Unlink Configs**: Remove symlinks but keep the config files in their destination.

  ```bash
  $ nos --unlink neovim
  ```

- **Purge Modules**: Uninstall dependencies and remove configurations.

  ```bash
  $ nos --purge neovim
  ```

## To do

- [x] `nos` will install dependencies and link files.
- [x] Support Homebrew dependencies.
- [x] `nos -f` will remove the existing configs if they exist (moves config to `*.before-nos`).
- [x] Allow post-install hooks in bash.
- [x] Allow installing only one module with `nos neovim`.
- [x] Allow multiple setups in one repo. Similar to "hosts" in Nix, `nos work` reads `profiles/work.lua` which includes whatever it wants from `modules/`.
- [x] Package and distribute `nos` through Homebrew.
- [x] Add `--unlink` option to remove symlinks and copy configs to output.
- [x] Add `--purge` option to uninstall dependencies and remove configurations.
- [x] Allow array of config. For example I could like two separate folders that are not siblings
- [ ] Add screenshots to the README.
- [ ] Support more ways of adding dependencies (e.g., wget binaries).
- [ ] Unlinking dotfiles without copying. An option like `nos --unlink --no-copy` could be added.
- [ ] `nos --purge-all` to purge all modules at once.
- [ ] Support Mac defaults, similar to `nix-darwin`.
- [ ] Improve profiles syntax. For example, `{ "*", "apps/work" }` should still be recursive except in "apps/". Or maybe accept negative patterns like `{ "!apps/personal" }` -> everything but apps/personal.
