# dot — all your computers in one repo

> Single binary, zero dependencies, one config file

<img width="751" height="486" alt="image" src="https://github.com/user-attachments/assets/9ae4f98e-5f3d-4389-985c-016a3cd0c08e" />


## Highlights

- **Zero dependencies** — compiled binary, nothing else to install
- **Cross-platform** — macOS, Linux, Windows
- **Interactive** — run `dot` and pick what you want from a checklist
- **Scriptable** — `dot -i git -l zsh -v` for automation and LLMs
- **Install anything** — brew, apt, pacman, paru, curl, cargo, any shell command
- **Idempotent** — run it twice, nothing breaks
- **macOS defaults** — export/import GUI app settings

## Installation

### macOS / Linux

```bash
curl -fsSL https://raw.githubusercontent.com/pablopunk/dot/main/scripts/install.sh | bash
```

Downloads the latest binary to `~/.local/bin/dot`.

### Windows PowerShell

```powershell
irm https://raw.githubusercontent.com/pablopunk/dot/main/scripts/install.ps1 | iex
```

Downloads the latest binary to `%LOCALAPPDATA%\Programs\dot\dot.exe` and adds it to your user `PATH`.

## Quick Start

1. Create a `dot.toml` in your dotfiles repo:

```toml
[zsh]
install.brew = "brew install zsh"
install.apt = "sudo apt install zsh"
link."zsh/.zshrc" = "~/.zshrc"

[git]
install.brew = "brew install git git-delta gh"
link."git/.gitconfig" = "~/.gitconfig"
postinstall = "gh auth login -p ssh -h github.com"

[neovim]
install.brew = "brew install neovim"
link."neovim/init.lua" = "~/.config/nvim/init.lua"
```

2. Run it:

```bash
dot                  # interactive checklist (default)
dot -i zsh -l git    # scriptable: install zsh, link git
dot --list           # list all components
```

## Configuration

```toml
[component-name]
install.brew = "brew install thing"   # any manager key works
install.apt = "sudo apt install -y thing"
install.any = "curl ... | sh"         # fallback
uninstall.brew = "brew uninstall thing"
link."src/file" = "~/.dest/file"      # single dest
link."src/file" = ["~/.a", "~/.b"]    # multi dest
postinstall = "echo 'done'"           # run after install
postlink = "chmod 600 ~/.file"        # run after link
os = ["mac", "linux"]                 # restrict to OS
check = "binary-name"                 # detect if already installed
defaults."com.apple.dock" = "dock.plist"  # macOS only
```

### Package managers

No hardcoded list. dot checks `Bun.which(manager)` for each key in your config and picks the first one available. `any` is always the last resort.

```toml
[mise]
install.brew = "brew install mise"
install.curl = "curl https://mise.run | sh"   # picked if curl exists
```

### Detecting installed components

`check` tells dot how to detect if a component is already installed. The interactive checklist shows `✓` for detected items.

```toml
[btop]
install.brew = "brew install btop"
check = "btop"                            # checks if binary is on PATH

[neovim]
install.brew = "brew install neovim"
check = "nvim"                            # binary name differs from package

[zed]
os = ["mac"]
install.brew = "brew install zed"
check = "test -d /Applications/Zed.app"   # shell command, exit 0 = installed
```

Dot also auto-detects when all symlinks are already in place — no `check` needed for link-only components.

### macOS defaults

```toml
[dock]
os = ["mac"]
defaults."com.apple.dock" = "macos/dock.plist"

[finder]
os = ["mac"]
defaults."com.apple.finder" = "macos/finder.xml"   # .xml = human-readable
```

```bash
dot -e   # export current defaults to files
dot -I   # import saved defaults
```

### Hooks

```toml
[vim]
install.brew = "brew install vim"
postinstall = "vim +PlugInstall +qall"
postlink = "echo 'linked'"
```

```bash
dot --postinstall vim    # run postinstall hook only
dot --postlink ssh       # run postlink hook only
```

## Usage

```bash
dot                          # interactive checklist (default)
dot --install                 # interactive install mode
dot --uninstall               # interactive uninstall mode
dot --link                    # interactive link mode
dot --postinstall             # interactive postinstall mode
dot -i zsh -i nvim -v         # install zsh + nvim, verbose
dot -u zsh                    # uninstall zsh
dot -l git                    # link git files
dot --postinstall nvim       # run postinstall hook
dot --postlink ssh           # run postlink hook
dot -e                       # export macOS defaults
dot -I                       # import macOS defaults
dot --list                   # list all components
dot --dry-run -i nvim        # preview without changes
dot --upgrade                # self-upgrade binary
dot -h                       # help
dot --version                # version
```

All action flags are composable. Execution order is: uninstall → install → defaults → link → postinstall → postlink.

Fuzzy matching: `dot -i nvim` matches `neovim` too.

Output is silent by default — use `-v` for verbose. In a TTY, package managers get real stdin for interactive prompts. When piped, stdin is closed for non-interactive use.

## Examples

### Basic dev setup

```toml
[zsh]
install.brew = "brew install zsh"
link."zsh/.zshrc" = "~/.zshrc"

[git]
install.brew = "brew install git git-delta"
link."git/.gitconfig" = "~/.gitconfig"

[vim]
install.brew = "brew install vim"
link."vim/.vimrc" = "~/.vimrc"
```

### Cross-platform

```toml
[tailscale]
install.brew = "brew install --cask tailscale"
install.pacman = "sudo pacman -S --noconfirm tailscale"
install.paru = "paru -S --noconfirm tailscale"
postinstall = """
if [[ "$(uname)" == "Linux" ]]; then
  sudo systemctl enable --now tailscaled
fi
"""
```

### macOS-only tools with defaults

```toml
[ice]
os = ["mac"]
install.brew = "brew install ice"
defaults."com.jordanbaird.Ice" = "config/ice/Ice.xml"

[karabiner]
os = ["mac"]
install.brew = "brew install karabiner-elements"
link."config/karabiner/karabiner.json" = "~/.config/karabiner/karabiner.json"
```

### Linux-only

```toml
[xremap]
os = ["linux"]
install.cargo = "cargo install xremap --features hypr"
link."config/xremap/config.yml" = "~/.config/xremap/config.yml"
```

## Building from source

```bash
git clone https://github.com/pablopunk/dot.git
cd dot
bun test        # run tests
make build      # compile binary
sudo make install
```

## Comparison

| Feature | dot | GNU Stow | chezmoi | dotbot |
|---------|-----|----------|---------|--------|
| Zero dependencies | yes | no | no | no |
| Single binary | yes | no | yes | no |
| Interactive TUI | yes | no | no | no |
| Package install | yes | no | yes | yes |
| macOS defaults | yes | no | no | no |
| Cross-platform | yes | yes | yes | yes |
| Dry run | yes | yes | yes | no |

## License

MIT
