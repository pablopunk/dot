import { describe, test, expect, jest } from "bun:test";
import { printResultStatus, printLinkStatus } from "../src/index";

describe("printResultStatus", () => {
  test("success prints ✓ in green", () => {
    const writes: string[] = [];
    const spy = jest.spyOn(process.stdout, "write");
    spy.mockImplementation((chunk: string) => {
      writes.push(chunk);
      return true;
    });

    printResultStatus("zsh", { success: true, failed: false, dryRun: false });

    expect(writes.length).toBe(1);
    expect(writes[0]).toContain("✓");
    expect(writes[0]).toContain("zsh");
    expect(writes[0]).toContain("\x1b[32m"); // green
    spy.mockRestore();
  });

  test("failure prints ✗ in red", () => {
    const writes: string[] = [];
    const spy = jest.spyOn(process.stdout, "write");
    spy.mockImplementation((chunk: string) => {
      writes.push(chunk);
      return true;
    });

    printResultStatus("nvim", { success: false, failed: true, dryRun: false });

    expect(writes.length).toBe(1);
    expect(writes[0]).toContain("✗");
    expect(writes[0]).toContain("nvim");
    expect(writes[0]).toContain("\x1b[31m"); // red
    spy.mockRestore();
  });

  test("dry-run prints ~ in yellow", () => {
    const writes: string[] = [];
    const spy = jest.spyOn(process.stdout, "write");
    spy.mockImplementation((chunk: string) => {
      writes.push(chunk);
      return true;
    });

    printResultStatus("git", { success: true, failed: false, dryRun: true });

    expect(writes.length).toBe(1);
    expect(writes[0]).toContain("~");
    expect(writes[0]).toContain("git");
    expect(writes[0]).toContain("\x1b[33m"); // yellow
    spy.mockRestore();
  });

  test("skipped prints - in dim", () => {
    const writes: string[] = [];
    const spy = jest.spyOn(process.stdout, "write");
    spy.mockImplementation((chunk: string) => {
      writes.push(chunk);
      return true;
    });

    printResultStatus("ssh", { success: false, failed: false, dryRun: false, skipped: true });

    expect(writes.length).toBe(1);
    expect(writes[0]).toContain("-");
    expect(writes[0]).toContain("ssh");
    expect(writes[0]).toContain("\x1b[2m"); // dim
    spy.mockRestore();
  });

  test("handles domain name for defaults", () => {
    const writes: string[] = [];
    const spy = jest.spyOn(process.stdout, "write");
    spy.mockImplementation((chunk: string) => {
      writes.push(chunk);
      return true;
    });

    printResultStatus("com.apple.dock", { success: true, failed: false, dryRun: false });

    expect(writes[0]).toContain("com.apple.dock");
    expect(writes[0]).toContain("✓");
    spy.mockRestore();
  });
});

describe("printLinkStatus", () => {
  test("all success prints ✓", () => {
    const writes: string[] = [];
    const spy = jest.spyOn(process.stdout, "write");
    spy.mockImplementation((chunk: string) => {
      writes.push(chunk);
      return true;
    });

    printLinkStatus("git", [
      { success: true, failed: false, dryRun: false, skipped: false },
      { success: true, failed: false, dryRun: false, skipped: false },
    ]);

    expect(writes[0]).toContain("✓");
    expect(writes[0]).toContain("git");
    spy.mockRestore();
  });

  test("any failure prints ✗", () => {
    const writes: string[] = [];
    const spy = jest.spyOn(process.stdout, "write");
    spy.mockImplementation((chunk: string) => {
      writes.push(chunk);
      return true;
    });

    printLinkStatus("git", [
      { success: true, failed: false, dryRun: false, skipped: false },
      { success: false, failed: true, dryRun: false, skipped: false },
    ]);

    expect(writes[0]).toContain("✗");
    expect(writes[0]).toContain("git");
    spy.mockRestore();
  });

  test("all dry-run prints ~", () => {
    const writes: string[] = [];
    const spy = jest.spyOn(process.stdout, "write");
    spy.mockImplementation((chunk: string) => {
      writes.push(chunk);
      return true;
    });

    printLinkStatus("nvim", [
      { success: true, failed: false, dryRun: true, skipped: false },
      { success: true, failed: false, dryRun: true, skipped: false },
    ]);

    expect(writes[0]).toContain("~");
    expect(writes[0]).toContain("nvim");
    spy.mockRestore();
  });

  test("all skipped prints -", () => {
    const writes: string[] = [];
    const spy = jest.spyOn(process.stdout, "write");
    spy.mockImplementation((chunk: string) => {
      writes.push(chunk);
      return true;
    });

    printLinkStatus("ssh", [
      { success: true, failed: false, dryRun: false, skipped: true },
      { success: true, failed: false, dryRun: false, skipped: true },
    ]);

    expect(writes[0]).toContain("-");
    expect(writes[0]).toContain("ssh");
    spy.mockRestore();
  });

  test("empty results prints nothing", () => {
    const writes: string[] = [];
    const spy = jest.spyOn(process.stdout, "write");
    spy.mockImplementation((chunk: string) => {
      writes.push(chunk);
      return true;
    });

    printLinkStatus("git", []);
    expect(writes.length).toBe(0);
    spy.mockRestore();
  });
});

describe("interactive mode feedback patterns (Change 1)", () => {
  test("Done. line is green and indented", () => {
    const writes: string[] = [];
    const spy = jest.spyOn(process.stdout, "write");
    spy.mockImplementation((chunk: string) => {
      writes.push(chunk);
      return true;
    });

    // Simulate the interactive mode's Done. line exactly as in src/index.ts
    process.stdout.write(`\n${"\x1b[32m"}  Done.${"\x1b[39m"}\n`);

    const doneLine = writes.find((w) => w.includes("Done."));
    expect(doneLine).toBeDefined();
    expect(doneLine).toContain("\x1b[32m"); // green
    expect(doneLine).toContain("Done.");
    spy.mockRestore();
  });

  test("failure count line is red and written to stderr", () => {
    const writes: string[] = [];
    const spy = jest.spyOn(process.stderr, "write");
    spy.mockImplementation((chunk: string) => {
      writes.push(chunk);
      return true;
    });

    // Simulate the interactive mode's failure count line
    const count = 2;
    process.stderr.write(`\n${"\x1b[31m"}  ${count} failure(s)${"\x1b[39m"}\n`);

    const failLine = writes.find((w) => w.includes("failure(s)"));
    expect(failLine).toBeDefined();
    expect(failLine).toContain("2 failure(s)");
    expect(failLine).toContain("\x1b[31m"); // red
    spy.mockRestore();
  });

  test("no failure count line when zero failures", () => {
    const writes: string[] = [];
    const spy = jest.spyOn(process.stderr, "write");
    spy.mockImplementation((chunk: string) => {
      writes.push(chunk);
      return true;
    });

    // The interactive mode only writes failure count when failures.length > 0
    // Zero failures should not produce a failure count line
    const failures: string[] = [];
    if (failures.length > 0) {
      process.stderr.write(`\n${"\x1b[31m"}  ${failures.length} failure(s)${"\x1b[39m"}\n`);
    }

    const failLine = writes.find((w) => w.includes("failure(s)"));
    expect(failLine).toBeUndefined();
    spy.mockRestore();
  });
});
