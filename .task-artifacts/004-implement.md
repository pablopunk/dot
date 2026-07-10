# 004 implement

- decision: implemented
- nextPhase: test

## Summary

Implemented Changes 1 and 2 from the approved plan targeting issue #34 (per-component feedback + always-on Done.).

### Change 1 — Per-component status output (always-on)

Added two helper functions to `src/index.ts`:

- **`printResultStatus(name, result)`** — prints a single status line for an operation result using `color()` from `./ui`:
  - `✓ name` (green) for success
  - `✗ name` (red) for failure
  - `~ name` (yellow) for dry-run
  - `- name` (dim) for skipped/no-op

- **`printLinkStatus(name, results[])`** — aggregates multiple `LinkResult` objects for a component and prints a single aggregate status line (same symbols).

These are called in all 7 operation sections of direct mode:

1. **uninstall** — after each component's result (or skipped when no uninstall command)
2. **install** — after each component's result (or `-` when no install command)
3. **import defaults** — per domain after each `DefaultsResult`
4. **export defaults** — per domain after each `DefaultsResult`
5. **link** — per component aggregated from `LinkResult[]` (or `-` when no links)
6. **postinstall** — after each component's `HookResult` (or `-` when no hook)
7. **postlink** — after each component's `HookResult` (or `-` when no hook)

Interactive mode is unchanged (separate code path).

### Change 2 — Always-on Done. line

Removed the `if (options.verbose)` guard around `process.stdout.write(\`\n${color("  Done.", "green")}\n\`)`. The "Done." line now always prints after successful completion in direct mode.

### Tests

Added `tests/feedback.test.ts` with 10 guardrail tests covering:
- `printResultStatus` — ✓ success, ✗ failure, ~ dry-run, - skipped, domain name
- `printLinkStatus` — ✓ all success, ✗ any failure, ~ all dry-run, - all skipped, empty results

## Files changed

- `src/index.ts`
- `tests/feedback.test.ts`
