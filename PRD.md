# dot v2 — PRD

Single-binary CLI for dotfiles management. Zero dependencies, built with Bun,
compiled to standalone binaries.

## Goals

- Zero-dependency binary — no npm, no node, no bun required at runtime
- Interactive-first UX via terminal TUI checklist
- Fully scriptable CLI with composable flags for automation/LLM use
- Cross-platform: macOS (arm64, x64), Linux (arm64, x64), Windows (x64)
- Drop complexity from v1: no profiles, no state file, no lock file
- TOML config format (Bun.TOML built-in)

## Non-goals

- Backward compatibility with v1 `dot.yaml`
- Profiles or profile-based configuration
- Persistent state tracking between runs
- Node.js/npm package distribution (binary only)

---

## Config: `dot.toml`

Placed in the root of a dotfiles repo. Dot runs from that directory.

```toml
[zsh]
install.brew = "brew install zsh"
install.apt = "sudo apt install zsh"
install.any = "echo 'install zsh manually'"
uninstall.brew = "brew uninstall zsh"
link."zsh/.zshrc" = "~/.zshrc"
link."zsh/.zprofile" = ["~/.zprofile", "~/.config/zsh/.zprofile"]
postinstall = "echo 'zsh configured'"
postlink = "chmod 600 ~/.zshrc"
os = ["mac", "linux"]

[neovim]
install.brew = "brew install neovim"
install.any = "curl -sL https://example.com/install.sh | bash"
os = ["mac", "linux"]

[dock]
defaults."com.apple.dock" = "macos/dock.plist"
os = ["mac"]

[finder]
defaults."com.apple.finder" = "macos/finder.xml"
os = ["mac"]
```

### Rules

- Each `[section]` is a component name
- `install.<manager>`: install command. `any` is universal fallback
- `uninstall.<manager>`: optional uninstall command
- `link.<src>`: relative path from repo → target(s). Single string or array
- `postinstall` / `postlink`: shell script run after install/link
- `defaults.<domain>`: macOS defaults domain → plist/xml path. `.xml` = XML export
- `os`: optional string array. Component hidden if current OS not in list

### Package manager resolution

No hardcoded list. For each component, check each install key via `Bun.which()`:

```
install.brew → Bun.which("brew")? → use "brew" command
install.apt  → Bun.which("apt")?  → use "apt" command
install.any  → fallback (always available)
```

First match wins. `any` is checked last.

---

## CLI

```
dot [flags...]

No action flags → interactive checklist (default)
Any action flag → direct mode (scriptable)

Action flags (repeatable, combinable):
  -i, --install <name>     Install component (fuzzy match)
  -u, --uninstall <name>   Uninstall component (fuzzy match)
  -l, --link <name>        Link files for component (fuzzy match)
  --postinstall <name>     Run postinstall hook (fuzzy match)
  --postlink <name>        Run postlink hook (fuzzy match)
  -e, --defaults-export    Export macOS defaults to files
  -I, --defaults-import    Import macOS defaults from files
  --list                   List all available components
  --upgrade                Self-upgrade binary

Modifiers (apply globally):
  --dry-run                Preview only
  -v, --verbose            Verbose output

Meta:
  -h, --help               Show help
  --version                Show version

Examples:
  dot -i zsh -i nvim -v         Install zsh + nvim, verbose
  dot -u zsh                    Uninstall zsh
  dot -l git                    Link git files
  dot --postinstall nvim        Run postinstall hook for nvim
  dot --postlink ssh            Run postlink hook for ssh
  dot -e                        Export macOS defaults
  dot -I                        Import macOS defaults
  dot --list                    List all components
  dot --dry-run -i nvim         Preview nvim install
  dot --upgrade                 Self-upgrade
```

### Execution order (direct mode)

```
1. Uninstall actions (in order specified)
2. Install actions (in order specified)
3. macOS defaults import (if -I)
4. Link actions (in order specified)
5. Postinstall hooks (in order specified)
6. Postlink hooks (in order specified)
```

Components are deduplicated within each phase (first occurrence wins).

---

## Interactive mode

Triggered when `dot` is run with no action flags (modifiers only like `-v` or `--dry-run` are ok).

### UI

```
  ◆ zsh             brew    `brew install zsh`
  ◇ neovim          brew    `brew install neovim`
  ◇ tmux            any     `curl ... | bash`
  ⚠ something       —       (no manager available)
  ─── Defaults ───
  ◇ dock            plist   com.apple.dock
  ─── Links ───
  ◇ zsh → ~/.zshrc, ~/.zprofile

  ↑↓ move  space toggle  enter confirm  q quit
  Ready: 1 to install, 0 links. Detected: brew, apt
  ⚠ 1 component has no install method
```

### Behavior

- Each component is one row. One checkbox per component.
- Components with no available manager are shown with ⚠ and skipped on confirm.
- Defaults components group in a sub-section (macOS only).
- Link-only components (no install) group in a Links sub-section.
- On enter: execute selected in lifecycle order (install → defaults → link → hooks).

---

## TUI implementation

- Raw terminal mode via `Bun.Terminal`
- Input: `Bun.stdin.stream()` byte by byte
- Parse ANSI escape sequences (↑↓ ←→ space enter q)
- Render with ANSI escape codes:
  - `\x1b[?25l` / `\x1b[?25h` — hide/show cursor
  - `\x1b[K` — clear line
  - `\x1b[{n}A` — move cursor up
  - `\x1b[7m` / `\x1b[0m` — inverse video on/off
  - `Bun.color(str, "green")` / `"red"` — component status

---

## Architecture

```
src/
├── index.ts           Entry point. Parse argv, dispatch mode.
├── cli.ts             Manual argument parsing (no deps).
├── config.ts          Load/validate dot.toml, resolve managers, OS filter.
├── interactive.ts     Checklist TUI + input loop.
├── renderer.ts        Low-level ANSI drawing primitives.
├── installer.ts       Run install/uninstall commands (Bun.$).
├── linker.ts          Symlink create/remove, ~ expansion, backup.
├── hooks.ts           Run postinstall/postlink scripts.
├── defaults.ts        macOS defaults export/import.
├── fuzzy.ts           Substring + char-order fuzzy matching.
├── ui.ts              Colors, spinner, status text.
└── utils.ts           OS detection, path expansion, binary check.

tests/
├── config.test.ts
├── cli.test.ts
├── fuzzy.test.ts
├── utils.test.ts
├── ui.test.ts
├── renderer.test.ts
├── interactive.test.ts
├── installer.test.ts
├── linker.test.ts
├── hooks.test.ts
├── defaults.test.ts
└── integration.test.ts
```

### Implementation notes

- **Zero runtime deps:** Only Bun built-ins (Bun.$, Bun.which, Bun.TOML, Bun.file, Bun.write,
  Bun.Terminal, Bun.color, Bun.spawn, Bun.spawnSync, Bun.symlink, Bun.sleep,
  Bun.stdin, Bun.stdout, Bun.stderr)
- **Zero dev deps:** Tests use `bun:test` only. No package.json.
- **Build:** `bun build --compile` embeds the Bun runtime. Output: ~50MB standalone binary.
- **Windows:** install/uninstall work. Links attempt, warn on failure. Defaults skip.

### Binary targets

```
bun build --compile --target=bun-linux-x64     ./src/index.ts
bun build --compile --target=bun-linux-arm64   ./src/index.ts
bun build --compile --target=bun-darwin-x64    ./src/index.ts
bun build --compile --target=bun-darwin-arm64  ./src/index.ts
bun build --compile --target=bun-windows-x64   ./src/index.ts
```

---

## Release workflow

GitHub Actions (same structure as v1):

- `.github/workflows/test.yml` — on push/PR: `bun test`
- `.github/workflows/build.yml` — cross-compile all targets
- `.github/workflows/release.yml` — on tag: build + `gh release create`

---

## Migration from v1

- Config renamed: `dot.yaml` → `dot.toml`
- Profiles dropped. Each component is always available (unless OS-filtered).
- State file dropped. No lock file, no tracking between runs.
- CLI flags changed: `--install <name>` replaces positional args.

---

## Open decisions (resolved)

| Decision | Choice |
|----------|--------|
| Config format | TOML (Bun.TOML) |
| Default mode | Interactive checklist |
| Profiles | Dropped |
| State/lock file | Dropped |
| macOS defaults | Kept: export/import plist+xml |
| Symlinks | Kept: backup existing files before overwrite |
| Package manager detection | `Bun.which(key)` per config — no hardcoded list |
| OS filter | `os = ["mac", "linux"]` |
| Windows | Install/uninstall work. Links best-effort. Defaults skip. |
| Dependencies | Zero (runtime + dev) |
| Binary targets | darwin/linux x64+arm64, windows x64 |
| Spinner | Yes, during installs |
| Config location | cwd only (same as v1) |
