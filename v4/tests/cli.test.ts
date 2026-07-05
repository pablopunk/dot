import { describe, test, expect } from "bun:test";
import { parseArgs } from "../src/cli";

describe("parseArgs", () => {
  test("no args → interactive mode", () => {
    const result = parseArgs(["dot"]);
    expect(result.mode).toBe("interactive");
  });

  test("--help → meta help", () => {
    const result = parseArgs(["dot", "--help"]);
    expect(result.mode).toBe("meta");
    expect(result.meta).toBe("help");
  });

  test("-h → meta help", () => {
    const result = parseArgs(["dot", "-h"]);
    expect(result.mode).toBe("meta");
    expect(result.meta).toBe("help");
  });

  test("--version → meta version", () => {
    const result = parseArgs(["dot", "--version"]);
    expect(result.mode).toBe("meta");
    expect(result.meta).toBe("version");
  });

  test("--upgrade → meta upgrade", () => {
    const result = parseArgs(["dot", "--upgrade"]);
    expect(result.mode).toBe("meta");
    expect(result.meta).toBe("upgrade");
  });

  test("-i zsh → direct install", () => {
    const result = parseArgs(["dot", "-i", "zsh"]);
    expect(result.mode).toBe("direct");
    expect(result.install).toEqual(["zsh"]);
  });

  test("--install zsh → direct install", () => {
    const result = parseArgs(["dot", "--install", "zsh"]);
    expect(result.mode).toBe("direct");
    expect(result.install).toEqual(["zsh"]);
  });

  test("-i zsh -i nvim → multiple installs", () => {
    const result = parseArgs(["dot", "-i", "zsh", "-i", "nvim"]);
    expect(result.install).toEqual(["zsh", "nvim"]);
  });

  test("-u zsh → uninstall", () => {
    const result = parseArgs(["dot", "-u", "zsh"]);
    expect(result.uninstall).toEqual(["zsh"]);
  });

  test("--uninstall zsh → uninstall", () => {
    const result = parseArgs(["dot", "--uninstall", "zsh"]);
    expect(result.uninstall).toEqual(["zsh"]);
  });

  test("-l git → link", () => {
    const result = parseArgs(["dot", "-l", "git"]);
    expect(result.link).toEqual(["git"]);
  });

  test("--link git → link", () => {
    const result = parseArgs(["dot", "--link", "git"]);
    expect(result.link).toEqual(["git"]);
  });

  test("--postinstall nvim → postinstall", () => {
    const result = parseArgs(["dot", "--postinstall", "nvim"]);
    expect(result.postinstall).toEqual(["nvim"]);
  });

  test("--postlink ssh → postlink", () => {
    const result = parseArgs(["dot", "--postlink", "ssh"]);
    expect(result.postlink).toEqual(["ssh"]);
  });

  test("-e → exportDefaults", () => {
    const result = parseArgs(["dot", "-e"]);
    expect(result.exportDefaults).toBe(true);
    expect(result.mode).toBe("direct");
  });

  test("--defaults-export → exportDefaults", () => {
    const result = parseArgs(["dot", "--defaults-export"]);
    expect(result.exportDefaults).toBe(true);
  });

  test("-I → importDefaults", () => {
    const result = parseArgs(["dot", "-I"]);
    expect(result.importDefaults).toBe(true);
  });

  test("--defaults-import → importDefaults", () => {
    const result = parseArgs(["dot", "--defaults-import"]);
    expect(result.importDefaults).toBe(true);
  });

  test("--list → list mode", () => {
    const result = parseArgs(["dot", "--list"]);
    expect(result.mode).toBe("direct");
    expect(result.list).toBe(true);
  });

  test("--dry-run as modifier only still interactive", () => {
    const result = parseArgs(["dot", "--dry-run"]);
    expect(result.mode).toBe("interactive");
    expect(result.dryRun).toBe(true);
  });

  test("-v as modifier only still interactive", () => {
    const result = parseArgs(["dot", "-v"]);
    expect(result.mode).toBe("interactive");
    expect(result.verbose).toBe(true);
  });

  test("-v with action → direct mode", () => {
    const result = parseArgs(["dot", "-v", "-i", "zsh"]);
    expect(result.mode).toBe("direct");
    expect(result.verbose).toBe(true);
    expect(result.install).toEqual(["zsh"]);
  });

  test("combined short flags -vi zsh", () => {
    const result = parseArgs(["dot", "-vi", "zsh"]);
    expect(result.mode).toBe("direct");
    expect(result.verbose).toBe(true);
    expect(result.install).toEqual(["zsh"]);
  });

  test("--dry-run -i nvim -v", () => {
    const result = parseArgs(["dot", "--dry-run", "-i", "nvim", "-v"]);
    expect(result.mode).toBe("direct");
    expect(result.dryRun).toBe(true);
    expect(result.install).toEqual(["nvim"]);
    expect(result.verbose).toBe(true);
  });

  test("combined --install and --link", () => {
    const result = parseArgs(["dot", "--install", "zsh", "--link", "git", "-v"]);
    expect(result.mode).toBe("direct");
    expect(result.install).toEqual(["zsh"]);
    expect(result.link).toEqual(["git"]);
    expect(result.verbose).toBe(true);
  });

  test("flags after positional are flags not args", () => {
    const result = parseArgs(["dot", "-i", "zsh", "-v"]);
    expect(result.install).toEqual(["zsh"]);
    expect(result.verbose).toBe(true);
  });

  test("--install without value goes interactive", () => {
    const result = parseArgs(["dot", "--install"]);
    expect(result.mode).toBe("interactive");
    expect(result.interactiveAction).toBe("install");
  });

  test("-i without value goes interactive", () => {
    const result = parseArgs(["dot", "-i"]);
    expect(result.mode).toBe("interactive");
    expect(result.interactiveAction).toBe("install");
  });

  test("-u without value goes interactive", () => {
    const result = parseArgs(["dot", "-u"]);
    expect(result.mode).toBe("interactive");
    expect(result.interactiveAction).toBe("uninstall");
  });

  test("-l without value goes interactive", () => {
    const result = parseArgs(["dot", "-l"]);
    expect(result.mode).toBe("interactive");
    expect(result.interactiveAction).toBe("link");
  });

  test("--postinstall without value goes interactive", () => {
    const result = parseArgs(["dot", "--postinstall"]);
    expect(result.mode).toBe("interactive");
    expect(result.interactiveAction).toBe("postinstall");
  });

  test("unknown flag throws", () => {
    expect(() => parseArgs(["dot", "--unknown-flag"])).toThrow();
  });

  test("unknown short flag throws", () => {
    expect(() => parseArgs(["dot", "-x"])).toThrow();
  });
});
