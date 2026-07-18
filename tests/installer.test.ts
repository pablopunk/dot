import { describe, test, expect, beforeEach, afterEach } from "bun:test";
import { installComponent, uninstallComponent } from "../src/installer";
import { mkdtempSync, rmSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

let tmp: string;

beforeEach(() => {
  tmp = mkdtempSync(join(tmpdir(), "dot-installer-"));
});

afterEach(() => {
  rmSync(tmp, { recursive: true, force: true });
});

describe("installComponent", () => {
  test("returns success for echo command", async () => {
    const result = await installComponent("zsh", "echo hello", { dryRun: false, verbose: false, interactive: false });
    expect(result.success).toBe(true);
    expect(result.failed).toBe(false);
  });

  test("dryRun does not execute", async () => {
    const result = await installComponent("zsh", "echo should-not-run", { dryRun: true, verbose: false, interactive: false });
    expect(result.success).toBe(true);
    expect(result.dryRun).toBe(true);
  });

  test("returns failure for nonexistent command", async () => {
    const result = await installComponent("zsh", "nonexistentcommandxyz123", { dryRun: false, verbose: false, interactive: false });
    expect(result.failed).toBe(true);
  });

  test("reports component name in result", async () => {
    const result = await installComponent("neovim", "echo ok", { dryRun: false, verbose: false, interactive: false });
    expect(result.component).toBe("neovim");
    expect(result.success).toBe(true);
  });

  test("reports manager name in result", async () => {
    const result = await installComponent("zsh", "echo ok", { dryRun: false, verbose: false, interactive: false }, "brew");
    expect(result.manager).toBe("brew");
  });

  test("null command returns failure", async () => {
    const result = await installComponent("custom", null as any, { dryRun: false, verbose: false, interactive: false });
    expect(result.failed).toBe(true);
  });

  test("non-interactive commands preserve pipeline input", async () => {
    const marker = join(tmp, "mise-installed");
    const result = await installComponent(
      "mise",
      `printf 'touch ${marker}' | sh`,
      { dryRun: false, verbose: false, interactive: false }
    );

    expect(result.success).toBe(true);
    expect(existsSync(marker)).toBe(true);
  });
});

describe("uninstallComponent", () => {
  test("returns success for echo command", async () => {
    const result = await uninstallComponent("zsh", "echo removing", { dryRun: false, verbose: false, interactive: false });
    expect(result.success).toBe(true);
    expect(result.failed).toBe(false);
  });

  test("dryRun does not execute", async () => {
    const result = await uninstallComponent("zsh", "echo should-not-run", { dryRun: true, verbose: false, interactive: false });
    expect(result.success).toBe(true);
    expect(result.dryRun).toBe(true);
  });

  test("reports component name in result", async () => {
    const result = await uninstallComponent("neovim", "echo ok", { dryRun: false, verbose: false, interactive: false });
    expect(result.component).toBe("neovim");
  });

  test("null command returns failure", async () => {
    const result = await uninstallComponent("custom", null as any, { dryRun: false, verbose: false, interactive: false });
    expect(result.failed).toBe(true);
  });
});
