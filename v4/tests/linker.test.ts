import { describe, test, expect, beforeEach, afterEach } from "bun:test";
import { createLinks, removeLinks, LinkResult } from "../src/linker";
import { tmpdir } from "node:os";
import { mkdtempSync, writeFileSync, symlinkSync, rmSync, existsSync, readlinkSync } from "node:fs";
import { join } from "node:path";

function makeTempDir(): string {
  return mkdtempSync(join(tmpdir(), "dot-link-test-"));
}

describe("createLinks", () => {
  let tmp: string;
  let home: string;

  beforeEach(() => {
    tmp = makeTempDir();
    home = makeTempDir();
    process.env.HOME = home;
  });

  afterEach(() => {
    rmSync(tmp, { recursive: true, force: true });
    rmSync(home, { recursive: true, force: true });
  });

  test("creates symlink", () => {
    const src = join(tmp, "zshrc");
    writeFileSync(src, "# zsh config");
    const dest = join(home, ".zshrc");

    const results = createLinks("zsh", { "zshrc": [dest] }, tmp, { dryRun: false, verbose: false, interactive: false });
    expect(results).toHaveLength(1);
    expect(results[0].success).toBe(true);
    expect(existsSync(dest)).toBe(true);
    expect(readlinkSync(dest)).toBe(src);
  });

  test("supports multiple destinations", () => {
    const src = join(tmp, "zshrc");
    writeFileSync(src, "# zsh config");
    const dest1 = join(home, ".zshrc");
    const dest2 = join(home, ".config/zsh/.zshrc");

    const results = createLinks("zsh", { "zshrc": [dest1, dest2] }, tmp, { dryRun: false, verbose: false, interactive: false });
    expect(results).toHaveLength(2);
    expect(results[0].success).toBe(true);
    expect(results[1].success).toBe(true);
  });

  test("skips when symlink already points correctly", () => {
    const src = join(tmp, "zshrc");
    writeFileSync(src, "# zsh config");
    const dest = join(home, ".zshrc");
    symlinkSync(src, dest);

    const results = createLinks("zsh", { "zshrc": [dest] }, tmp, { dryRun: false, verbose: false, interactive: false });
    expect(results[0].skipped).toBe(true);
    expect(results[0].reason).toContain("exists");
  });

  test("overwrites incorrect symlink", () => {
    const src = join(tmp, "zshrc");
    writeFileSync(src, "# new zsh config");
    const wrongSrc = join(tmp, "old-zshrc");
    writeFileSync(wrongSrc, "# old config");
    const dest = join(home, ".zshrc");
    symlinkSync(wrongSrc, dest);

    const results = createLinks("zsh", { "zshrc": [dest] }, tmp, { dryRun: false, verbose: false, interactive: false });
    expect(results[0].success).toBe(true);
    expect(readlinkSync(dest)).toBe(src);
  });

  test("backs up existing file before linking", () => {
    const src = join(tmp, "zshrc");
    writeFileSync(src, "# new zsh config");
    const dest = join(home, ".zshrc");
    writeFileSync(dest, "original content");

    const results = createLinks("zsh", { "zshrc": [dest] }, tmp, { dryRun: false, verbose: false, interactive: false });
    expect(results[0].success).toBe(true);
    const bakFile = dest + ".dot.bak";
    expect(existsSync(bakFile)).toBe(true);
    expect(readlinkSync(dest)).toBe(src);
  });

  test("dry run does not create links", () => {
    const src = join(tmp, "zshrc");
    writeFileSync(src, "# zsh config");
    const dest = join(home, ".zshrc");

    const results = createLinks("zsh", { "zshrc": [dest] }, tmp, { dryRun: true, verbose: false, interactive: false });
    expect(results[0].dryRun).toBe(true);
    expect(existsSync(dest)).toBe(false);
  });

  test("reports missing source", () => {
    const dest = join(home, ".zshrc");
    const results = createLinks("zsh", { "nonexistent": [dest] }, tmp, { dryRun: false, verbose: false, interactive: false });
    expect(results[0].success).toBe(false);
    expect(results[0].reason).toContain("not found");
  });

  test("creates parent directories for destination", () => {
    const src = join(tmp, "config");
    writeFileSync(src, "content");
    const dest = join(home, ".config", "nested", "deep", "config");

    const results = createLinks("zsh", { "config": [dest] }, tmp, { dryRun: false, verbose: false, interactive: false });
    expect(results[0].success).toBe(true);
    expect(existsSync(dest)).toBe(true);
  });
});

describe("removeLinks", () => {
  let tmp: string;
  let home: string;

  beforeEach(() => {
    tmp = makeTempDir();
    home = makeTempDir();
    process.env.HOME = home;
  });

  afterEach(() => {
    rmSync(tmp, { recursive: true, force: true });
    rmSync(home, { recursive: true, force: true });
  });

  test("removes symlink", () => {
    const src = join(tmp, "zshrc");
    writeFileSync(src, "# zsh config");
    const dest = join(home, ".zshrc");
    symlinkSync(src, dest);

    const results = removeLinks("zsh", { "zshrc": [dest] }, tmp, { dryRun: false, verbose: false, interactive: false });
    expect(results[0].success).toBe(true);
    expect(existsSync(dest)).toBe(false);
  });

  test("skips non-existent destination", () => {
    const dest = join(home, ".zshrc");
    const results = removeLinks("zsh", { "zshrc": [dest] }, tmp, { dryRun: false, verbose: false, interactive: false });
    expect(results[0].skipped).toBe(true);
  });

  test("does not remove real files (only symlinks)", () => {
    const dest = join(home, ".zshrc");
    writeFileSync(dest, "real file");

    const results = removeLinks("zsh", { "zshrc": [dest] }, tmp, { dryRun: false, verbose: false, interactive: false });
    expect(results[0].skipped).toBe(true);
    expect(existsSync(dest)).toBe(true);
  });

  test("dry run does not remove", () => {
    const src = join(tmp, "zshrc");
    writeFileSync(src, "# zsh config");
    const dest = join(home, ".zshrc");
    symlinkSync(src, dest);

    const results = removeLinks("zsh", { "zshrc": [dest] }, tmp, { dryRun: true, verbose: false, interactive: false });
    expect(results[0].dryRun).toBe(true);
    expect(existsSync(dest)).toBe(true);
  });
});
