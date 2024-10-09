# `nos`

> Manage your dotfiles and their dependencies automagically

```bash
$ brew install pablopunk/formulae/nos
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

$ nos # link all dotfiles and install dependencies
$ nos neovim # only neovim module
$ nos work # only my work profile
```

## Usage

Each module under the `modules/` folder needs to have at least an `init.lua`. If not, it will be ignored.

### `init.lua`

Example for neovim:

```lua
return {
  brew = {
    { name = "neovim", options = "--HEAD" },
    "ripgrep"
  },
  config = {
    source = "./config", -- this is our config i.e dotfiles/modules/neovim/config
    output = "~/.config/nvim", -- this is where the config will be linked to
  }
}
```

The config will be linked to the home folder with a soft link. In this case:

```bash
~/.config/nvim → ~/dotfiles/modules/neovim/config
```

As you can see you can declare dependencies as [homebrew](https://brew.sh) packages, which makes it possible to also use `nos` to install GUI apps (homebrew casks). You can create a module without any config, to use it as an installer for your apps:

```lua
-- modules/apps/init.lua
return {
  brew = { "whatsapp", "spotify", "slack", "vscode" }
}
```

### Recursive

In the example above, let's say we want to separate our apps into "work" and "personal". We could either create 2 modules on the root folder, or create a nested folder for each:

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

If you have several machines, you might not wanna install all tools on every computer. That's why `nos` allows **profiles**.

Let's created a new "work" profile:

```lua
-- profiles/work.lua
return {
  modules = {
    "apps/work",
    "*",
  }
}
```

In this example, using the directories we created in the [recursive section](#recursive) running `nos work` will:

* `apps/work`: install only our work apps under `modules/apps/work/init.lua`
* `*`: install everything else under `modules/*`, except nested directories (so it won't install `apps/work`)

> NOTE 1: once `nos` detects an init.lua, it will stop going through the subdirectories inside that folder.

> NOTE 2: you probably don't want to name a profile the same as a module (i.e profile/neovim <> modules/neovim)
> since running `nos neovim` will default to the profile

## To do

- [x] `nos` will install deps and link files.
- [x] Support brew dependencies.
- [x] `nos -f` will remove the existing configs if they exist (moves config to `*.before-nos`)
- [x] Allows post_install hooks in bash
- [ ] Allows to install only one thing `nos neovim`
- [ ] Allow multiple setups in one repo. Sort of like "hosts" in nix. `nos m1air` reads `profiles/m1air.lua` which includes whatever it wants from `modules/`
- [x] Package and distribute `nos` through _brew_
- [ ] Support more ways of adding dependencies (wget binaries?)
- [ ] Unlinking dotfiles. Something like `nos unlink` should remove all links and copy all files to its destinations (to maintain config).
- [ ] `nos purge`. Same as `unlink` but without copying the files. Just leave the computer "configless".
- [ ] mac defaults support, just like nix-darwin

