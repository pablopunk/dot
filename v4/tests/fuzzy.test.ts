import { describe, test, expect } from "bun:test";
import { fuzzyMatch, resolveComponentNames } from "../src/fuzzy";

describe("fuzzyMatch", () => {
  const candidates = ["zsh", "z-shell", "git", "github-cli", "neovim", "tmux", "nvim"];

  test("exact match is first", () => {
    const result = fuzzyMatch("zsh", candidates);
    expect(result[0]).toBe("zsh");
    expect(result).toContain("z-shell");
  });

  test("substring match returns all", () => {
    const result = fuzzyMatch("git", candidates);
    expect(result).toContain("git");
    expect(result).toContain("github-cli");
  });

  test("char-in-order match", () => {
    const result = fuzzyMatch("zsh", candidates);
    expect(result).toContain("zsh");
    expect(result).toContain("z-shell");
  });

  test("case insensitive", () => {
    const result = fuzzyMatch("ZSH", candidates);
    expect(result).toContain("zsh");
    expect(result).toContain("z-shell");
  });

  test("no match returns empty", () => {
    const result = fuzzyMatch("xyzpdq", candidates);
    expect(result).toEqual([]);
  });

  test("multiple results ordered by match quality", () => {
    const result = fuzzyMatch("nvim", ["neovim", "nvim", "nvim-lazy", "vim"]);
    expect(result[0]).toBe("nvim");
    expect(result).toContain("neovim");
    expect(result).toContain("nvim-lazy");
  });

  test("empty query returns all candidates", () => {
    const result = fuzzyMatch("", ["a", "b", "c"]);
    expect(result).toEqual(["a", "b", "c"]);
  });

  test("empty candidates returns empty", () => {
    const result = fuzzyMatch("zsh", []);
    expect(result).toEqual([]);
  });
});

describe("resolveComponentNames", () => {
  const available = ["zsh", "z-shell", "git", "github-cli", "neovim", "tmux"];

  test("resolves exact match", () => {
    const { found, missing } = resolveComponentNames(["zsh"], available);
    expect(found).toContain("zsh");
    expect(missing).toEqual([]);
  });

  test("resolves fuzzy match", () => {
    const { found, missing } = resolveComponentNames(["git"], available);
    expect(found).toContain("git");
    expect(found).toContain("github-cli");
    expect(missing).toEqual([]);
  });

  test("resolves multiple queries", () => {
    const { found, missing } = resolveComponentNames(["zsh", "tmux"], available);
    expect(found).toContain("zsh");
    expect(found).toContain("tmux");
    expect(missing).toEqual([]);
  });

  test("reports missing", () => {
    const { found, missing } = resolveComponentNames(["nonexistent"], available);
    expect(found).toEqual([]);
    expect(missing).toEqual(["nonexistent"]);
  });

  test("mixed found and missing", () => {
    const { found, missing } = resolveComponentNames(["zsh", "nonexistent"], available);
    expect(found).toContain("zsh");
    expect(missing).toEqual(["nonexistent"]);
  });

  test("deduplicates fuzzy matches", () => {
    const { found } = resolveComponentNames(["zsh", "zsh"], available);
    const zshCount = found.filter(f => f === "zsh").length;
    expect(zshCount).toBe(1);
  });

  test("empty queries returns empty found", () => {
    const { found, missing } = resolveComponentNames([], available);
    expect(found).toEqual([]);
    expect(missing).toEqual([]);
  });
});
