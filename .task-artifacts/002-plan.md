# 002-plan

- decision: approved
- nextPhase: plan_review

## Summary

Implementation plan for issue #34: "more feedback for cli commands, ends without output"

## Issue analysis

Fetched issue #34 via GitHub API. Title: "more feedback for cli commands, ends without output". Body: null (no additional description). State: open, no comments.

## Codebase exploration evidence

**Revisited files** (all under worktree path):

| File | Purpose |
|------|---------|
| `src/index.ts` | Main entrypoint, `main()` function, `printResultStatus`, `printLinkStatus`, "Done." line |
| `src/cli.ts` | Argument parsing |
| `src/installer.ts` | `installComponent()`, `uninstallComponent()` — runs subprocesses |
| `src/linker.ts` | `createLinks()`, `removeLinks()` — symlink management |
| `src/hooks.ts` | `runPostInstall()`, `runPostLink()` — hook execution |
| `src/defaults.ts` | `exportDefaults()`, `importDefaults()` — macOS defaults |
| `src/ui.ts` | `color()`, `spinner()` — ANSI helpers |
| `src/interactive.ts` | `runInteractive()` — TUI prompt via `prompts` |
| `src/config.ts` | `parseConfig()`, `resolveComponents()` |
| `src/fuzzy.ts` | `fuzzyMatch()`, `resolveComponentNames()` |
| `src/renderer.ts` | `hideCursor()`, `showCursor()`, ANSI escapes |
| `src/utils.ts` | `detectOS()`, `expandPath()`, `binaryExists()` |
| `tests/feedback.test.ts` | 10 tests covering `printResultStatus` and `printLinkStatus` |
| `tests/installer.test.ts` | Tests for `installComponent`, `uninstallComponent` |
| `tests/hooks.test.ts` | Tests for `runPostInstall`, `runPostLink` |
| `.task-artifacts/004-implement.md` | Previous implementation attempt (direct mode only) |

## Current state diagnosis

Two code paths exist: **interactive** (default TUI) and **direct** (flag-based non-interactive).

### Direct mode (flag-based, e.g. `dot -i git -l zsh`)

Already has feedback after the previous implementation attempt:
- `printResultStatus(name, result)` called for every operation in all 7 sections: uninstall, install, defaults import, defaults export, link, postinstall, postlink
- `printLinkStatus(name, results[])` called for link operations
- `"Done."` line printed unconditionally at the end (line 348)
- Section headers (`"Install"`, `"Link"`, etc.) still verbose-only (correct)

**However**, `installComponent` and `uninstallComponent` in `src/installer.ts` suppress subprocess stderr when `options.verbose` is `false` (lines 66-69 and 115-117). On failure, user sees `✗ name` but no error details.

### Interactive mode (default, TUI via `prompts`)

**Lacks post-execution feedback entirely** — this is the main gap:
- After TUI selection and action loop, the function returns without any status output
- No `printResultStatus`/`printLinkStatus` calls
- No "Done." line
- Only failure messages are written to stderr (lines 149-151)
- User sees: prompt -> select -> TUI closes -> nothing happens -> exits with code 0

### Additional bug found

Line 130: `interactive: isTty && args.mode === "direct"` — the `options.interactive` field is `false` when mode is `"interactive"`. This causes subprocesses to get `< /dev/null` piped to their stdin, preventing sudo prompts and interactive installers from working in interactive mode.

## Changes

### Change 1 — Add post-execution feedback to interactive mode

**File**: `src/index.ts` (interactive mode block, lines ~140–210)

**What**: After the per-component action loop in interactive mode, add:
1. A header line (`"Installing..."`, `"Linking..."`, etc.) based on `action` — only when verbose
2. `printResultStatus(name, result)` for each component's operation, using the result from `installComponent`/`uninstallComponent`/etc.
3. The `HookResult` from hooks needs `printResultStatus` support (it already has `success`, `failed`, `dryRun`, `skipped` fields — compatible)
4. The `LinkResult[]` from link operations needs `printLinkStatus` support
5. Track failures in a `failures: string[]` array
6. Print a failure count line at the end if any failures exist
7. Print "Done." line at the end
8. Section headers only when verbose

### Change 2 — Show stderr on failure regardless of verbose mode

**File**: `src/installer.ts`

**What**: In `installComponent()` and `uninstallComponent()`, remove the `if (options.verbose)` guard around stderr output on failure.

Current (`installComponent`, lines 58-69):
```typescript
if (result.exitCode !== 0) {
  if (options.verbose) {
    const stderr = result.stderr.toString().trim();
    if (stderr) process.stderr.write(`  ${color("[error]", "red")} ${name}: ${stderr}\n`);
  }
  return { ...base, failed: true };
}
```

Change to: always write stderr to stderr on failure, regardless of verbose mode. This mirrors the behavior already in `hooks.ts` which always shows stderr on failure.

Same change needed in `uninstallComponent()` (lines ~107-117).

### Change 3 — Fix `options.interactive` for interactive mode

**File**: `src/index.ts`, line 130

**What**: Change:
```typescript
const options = { dryRun: args.dryRun, verbose: args.verbose, interactive: isTty && args.mode === "direct" };
```
to:
```typescript
const options = { dryRun: args.dryRun, verbose: args.verbose, interactive: isTty };
```

This ensures subprocesses get real stdin access in both modes when running in a terminal.

## Target files (ordered by change)

1. `src/index.ts` — Changes 1 and 3
2. `src/installer.ts` — Change 2
3. `tests/feedback.test.ts` — Add tests for interactive mode feedback

## Not changing

- `src/linker.ts` — verbose guards around link details are intentional (too verbose for default)
- `src/hooks.ts` — already shows stderr on failure without verbose guard (correct)
- `src/defaults.ts` — verbose guards are intentional (too verbose for default)
- `README.md` — may need update after implementation to reflect new default output
- Direct mode status output — already working correctly

## Validation

### Test commands

```bash
cd /agent-state/fractal/projects/pablopunk-dot/worktrees/task-34-dot
bun test
```

Expected: all existing tests pass, including the 10 `feedback.test.ts` tests.

### Manual verification (conceptual)

**Interactive mode feedback:**
1. `dot` -> select component -> should print status lines after TUI closes
2. `dot -v` -> should print verbose output + status lines

**Non-verbose stderr on failure:**
1. `dot -i nonexistent` (with failing install) -> should show `✗ name` + error details

**Options.interactive fix:**
1. `dot` with brew install -> should allow password prompts

## Risks

| Risk | Mitigation |
|------|------------|
| Interactive mode output changes break user scripts that pipe dot output | Interactive mode requires a TTY (checked at line 131), so piping is not possible in this mode |
| Stderr always shown on failure could be noisy for expected failures (e.g., already installed component) | Stderr only shown on exit code != 0, which indicates actual failure, not success |
| Options.interactive change could change subprocess behavior | Only affects TTY sessions; non-TTY (scripted) sessions are unchanged |
| Tests may fail if bun test runner uses different TTY detection | Use `interactive: false` explicitly in test options (already done in all test files) |

## Open questions

1. Should interactive mode show a cumulative summary (e.g., "3 installed, 1 failed") in addition to per-component lines? — Not in scope for this issue; can be added later.
2. Should "Done." be in green as it is now? — Yes, matches existing pattern.
3. Should the `options.interactive` fix be a separate PR? — No, it's directly related to getting accurate feedback in interactive mode.

## Acceptance criteria

1. [ ] Running `dot` (interactive mode) and selecting components prints status lines (`✓ name`/`✗ name`) after the TUI closes, followed by "Done."
2. [ ] Running `dot -v` shows verbose output plus same status lines
3. [ ] Running `dot -i name` with a failing command shows stderr error details in addition to `✗ name`
4. [ ] Running `dot` with TUI properly passes stdin to subprocesses (sudo prompts work)
5. [ ] All existing `bun test` tests pass
6. [ ] New tests in `tests/feedback.test.ts` cover interactive mode behavior
