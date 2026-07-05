import { describe, test, expect } from "bun:test";
import { runPostInstall, runPostLink } from "../src/hooks";

describe("runPostInstall", () => {
  test("runs hook and returns success", async () => {
    const result = await runPostInstall("zsh", "echo installed", { dryRun: false, verbose: false, interactive: false });
    expect(result.success).toBe(true);
    expect(result.component).toBe("zsh");
  });

  test("dry run skips execution", async () => {
    const result = await runPostInstall("zsh", "echo should-not-run", { dryRun: true, verbose: false, interactive: false });
    expect(result.success).toBe(true);
    expect(result.dryRun).toBe(true);
  });

  test("returns success when no hook", async () => {
    const result = await runPostInstall("zsh", null, { dryRun: false, verbose: false, interactive: false });
    expect(result.success).toBe(true);
    expect(result.skipped).toBe(true);
  });

  test("returns failure for failing hook", async () => {
    const result = await runPostInstall("zsh", "exit 1", { dryRun: false, verbose: false, interactive: false });
    expect(result.failed).toBe(true);
  });
});

describe("runPostLink", () => {
  test("runs hook and returns success", async () => {
    const result = await runPostLink("ssh", "echo linked", { dryRun: false, verbose: false, interactive: false });
    expect(result.success).toBe(true);
    expect(result.component).toBe("ssh");
  });

  test("dry run skips execution", async () => {
    const result = await runPostLink("ssh", "echo should-not-run", { dryRun: true, verbose: false, interactive: false });
    expect(result.success).toBe(true);
    expect(result.dryRun).toBe(true);
  });

  test("returns success when no hook", async () => {
    const result = await runPostLink("ssh", null, { dryRun: false, verbose: false, interactive: false });
    expect(result.success).toBe(true);
    expect(result.skipped).toBe(true);
  });

  test("returns failure for failing hook", async () => {
    const result = await runPostLink("ssh", "exit 1", { dryRun: false, verbose: false, interactive: false });
    expect(result.failed).toBe(true);
  });
});
