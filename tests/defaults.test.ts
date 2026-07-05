import { describe, test, expect, beforeEach, afterEach } from "bun:test";
import { exportDefaults, importDefaults } from "../src/defaults";
import { tmpdir } from "node:os";
import { mkdtempSync, writeFileSync, rmSync, existsSync } from "node:fs";
import { join } from "node:path";

function makeTempDir(): string {
  return mkdtempSync(join(tmpdir(), "dot-defaults-test-"));
}

describe("exportDefaults", () => {
  let tmp: string;

  beforeEach(() => {
    tmp = makeTempDir();
  });

  afterEach(() => {
    rmSync(tmp, { recursive: true, force: true });
  });

  test("skips on non-macOS", async () => {
    if (process.platform === "darwin") return;
    const file = join(tmp, "dock.plist");
    const result = await exportDefaults({ "com.apple.dock": file }, tmp, { dryRun: false, verbose: false, interactive: false });
    expect(result[0].skipped).toBe(true);
    expect(result[0].reason).toContain("macOS");
  });

  test("dry run sets dryRun flag", async () => {
    const file = join(tmp, "dock.plist");
    const result = await exportDefaults({ "com.apple.dock": file }, tmp, { dryRun: true, verbose: false, interactive: false });
    if (result.length > 0) {
      expect(result[0].dryRun || result[0].skipped).toBe(true);
    }
  });

  test("handles empty defaults", async () => {
    const result = await exportDefaults({}, tmp, { dryRun: false, verbose: false, interactive: false });
    expect(result).toEqual([]);
  });

  test("returns component name for each domain", async () => {
    if (process.platform === "darwin") return;
    const file = join(tmp, "dock.plist");
    const result = await exportDefaults({ "com.apple.dock": file }, tmp, { dryRun: false, verbose: false, interactive: false });
    expect(result[0].domain).toBe("com.apple.dock");
  });
});

describe("importDefaults", () => {
  let tmp: string;

  beforeEach(() => {
    tmp = makeTempDir();
  });

  afterEach(() => {
    rmSync(tmp, { recursive: true, force: true });
  });

  test("skips on non-macOS", async () => {
    if (process.platform === "darwin") return;
    const file = join(tmp, "dock.plist");
    writeFileSync(file, "mock plist content");
    const result = await importDefaults({ "com.apple.dock": file }, tmp, { dryRun: false, verbose: false, interactive: false });
    expect(result[0].skipped).toBe(true);
    expect(result[0].reason).toContain("macOS");
  });

  test("dry run sets flag", async () => {
    const file = join(tmp, "dock.plist");
    writeFileSync(file, "mock plist content");
    const result = await importDefaults({ "com.apple.dock": file }, tmp, { dryRun: true, verbose: false, interactive: false });
    if (result.length > 0) {
      expect(result[0].dryRun || result[0].skipped).toBe(true);
    }
  });

  test("reports missing file", async () => {
    if (process.platform !== "darwin") return;
    const file = join(tmp, "nonexistent.plist");
    const result = await importDefaults({ "com.apple.dock": file }, tmp, { dryRun: false, verbose: false, interactive: false });
    expect(result[0].success).toBe(false);
    expect(result[0].reason).toContain("not found");
  });

  test("handles empty defaults", async () => {
    const result = await importDefaults({}, tmp, { dryRun: false, verbose: false, interactive: false });
    expect(result).toEqual([]);
  });

  test("returns domain for each import", async () => {
    if (process.platform === "darwin") return;
    const file = join(tmp, "dock.plist");
    writeFileSync(file, "mock plist content");
    const result = await importDefaults({ "com.apple.dock": file }, tmp, { dryRun: false, verbose: false, interactive: false });
    expect(result[0].domain).toBe("com.apple.dock");
  });
});
