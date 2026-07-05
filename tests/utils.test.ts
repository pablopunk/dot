import { describe, test, expect } from "bun:test";
import { detectOS, expandPath, binaryExists, isTTY } from "../src/utils";

describe("detectOS", () => {
  test("returns current platform", () => {
    const os = detectOS();
    expect(["mac", "linux", "windows"]).toContain(os);
  });

  test("returns linux on linux", () => {
    if (process.platform !== "linux") return;
    expect(detectOS()).toBe("linux");
  });

  test("returns mac on darwin", () => {
    if (process.platform !== "darwin") return;
    expect(detectOS()).toBe("mac");
  });

  test("returns windows on win32", () => {
    if (process.platform !== "win32") return;
    expect(detectOS()).toBe("windows");
  });
});

describe("expandPath", () => {
  const originalHome = process.env.HOME;

  test("replaces ~ with HOME", () => {
    process.env.HOME = "/home/user";
    expect(expandPath("~/.zshrc")).toBe("/home/user/.zshrc");
  });

  test("replaces ~ at start only", () => {
    process.env.HOME = "/home/user";
    expect(expandPath("~/.foo/~/bar")).toBe("/home/user/.foo/~/bar");
  });

  test("returns unchanged if no ~", () => {
    process.env.HOME = "/home/user";
    expect(expandPath("/etc/hosts")).toBe("/etc/hosts");
  });

  test("returns unchanged if empty", () => {
    process.env.HOME = "/home/user";
    expect(expandPath("")).toBe("");
  });

  test("returns home if only ~", () => {
    process.env.HOME = "/home/user";
    expect(expandPath("~")).toBe("/home/user");
  });

  test("handles missing HOME", () => {
    delete process.env.HOME;
    expect(expandPath("~/file")).toBe("~/file");
    process.env.HOME = originalHome;
  });
});

describe("binaryExists", () => {
  test("finds sh", () => {
    expect(binaryExists("sh")).toBe(true);
  });

  test("does not find nonexistentkjasdhfkjsdhf", () => {
    expect(binaryExists("nonexistentkjasdhfkjsdhf")).toBe(false);
  });

  test("finds echo (usually builtin but on PATH too)", () => {
    expect(binaryExists("echo")).toBe(true);
  });
});

describe("isTTY", () => {
  test("returns boolean", () => {
    expect(typeof isTTY()).toBe("boolean");
  });
});
