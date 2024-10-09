# `nos`

> Manage your dotfiles and their dependencies automagically

- [x] `nos` will install deps and link files.
- [x] Support brew dependencies.
- [x] `nos -f` will remove the existing configs if they exist (moves config to `*.before-nos`)
- [x] Allows post_install hooks in bash
- [ ] Allows to install only one thing `nos neovim`
- [ ] Allow multiple setups in one repo. Sort of like "hosts" in nix. `nos m1air` reads `profiles/m1air.lua` which includes whatever it wants from `modules/`
- [ ] Package and distribute `nos` through _brew_
- [ ] Support more ways of adding dependencies (wget binaries?)
- [ ] Unlinking dotfiles. Something like `nos unlink` should remove all links and copy all files to its destinations (to maintain config).
- [ ] `nos purge`. Same as `unlink` but without copying the files. Just leave the computer "configless".
- [ ] mac defaults support, just like nix-darwin

