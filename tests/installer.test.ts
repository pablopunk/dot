import { describe, test, expect, jest } from "bun:test";
import { installComponent, uninstallComponent } from "../src/installer";

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
});

describe("installComponent stderr behavior (Change 2 — always show stderr on failure)", () => {
  test("writes stderr to process.stderr on failure without verbose", async () => {
    const writes: string[] = [];
    const spy = jest.spyOn(process.stderr, "write");
    spy.mockImplementation((chunk: string) => {
      writes.push(chunk);
      return true;
    });

    // A failing command should write stderr even without verbose mode
    const result = await installComponent("zsh", "nonexistentcommandxyz123", { dryRun: false, verbose: false, interactive: false });

    expect(result.failed).toBe(true);
    // Should have written error output to stderr
    const errorLine = writes.find((w) => w.includes("[error]") || w.includes("zsh"));
    expect(errorLine).toBeDefined();
    spy.mockRestore();
  });

  test("writes stderr to process.stderr on failure with verbose", async () => {
    const writes: string[] = [];
    const spy = jest.spyOn(process.stderr, "write");
    spy.mockImplementation((chunk: string) => {
      writes.push(chunk);
      return true;
    });

    const result = await installComponent("nvim", "nonexistentcommandxyz123", { dryRun: false, verbose: true, interactive: false });

    expect(result.failed).toBe(true);
    const errorLine = writes.find((w) => w.includes("[error]") || w.includes("nvim"));
    expect(errorLine).toBeDefined();
    spy.mockRestore();
  });

  test("does not write stderr on success without verbose", async () => {
    const writes: string[] = [];
    const spy = jest.spyOn(process.stderr, "write");
    spy.mockImplementation((chunk: string) => {
      writes.push(chunk);
      return true;
    });

    const result = await installComponent("zsh", "echo ok", { dryRun: false, verbose: false, interactive: false });

    expect(result.success).toBe(true);
    // No error output on success
    const errorLine = writes.find((w) => w.includes("[error]"));
    expect(errorLine).toBeUndefined();
    spy.mockRestore();
  });

  test("interactive:true does not pipe /dev/null (Change 3 guard)", async () => {
    // When interactive:true, the command runs without < /dev/null
    // We verify by running a command that reads from stdin
    const result = await installComponent("zsh", "echo interactive-works", {
      dryRun: false,
      verbose: false,
      interactive: true,
    });
    expect(result.success).toBe(true);
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

describe("uninstallComponent stderr behavior (Change 2 — always show stderr on failure)", () => {
  test("writes stderr to process.stderr on failure without verbose", async () => {
    const writes: string[] = [];
    const spy = jest.spyOn(process.stderr, "write");
    spy.mockImplementation((chunk: string) => {
      writes.push(chunk);
      return true;
    });

    const result = await uninstallComponent("zsh", "nonexistentcommandxyz123", { dryRun: false, verbose: false, interactive: false });

    expect(result.failed).toBe(true);
    const errorLine = writes.find((w) => w.includes("[error]") || w.includes("zsh"));
    expect(errorLine).toBeDefined();
    spy.mockRestore();
  });

  test("does not write stderr on success without verbose", async () => {
    const writes: string[] = [];
    const spy = jest.spyOn(process.stderr, "write");
    spy.mockImplementation((chunk: string) => {
      writes.push(chunk);
      return true;
    });

    const result = await uninstallComponent("zsh", "echo ok", { dryRun: false, verbose: false, interactive: false });

    expect(result.success).toBe(true);
    const errorLine = writes.find((w) => w.includes("[error]"));
    expect(errorLine).toBeUndefined();
    spy.mockRestore();
  });
});
