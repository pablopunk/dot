import { describe, test, expect } from "bun:test";
import { color, spinner } from "../src/ui";

describe("color", () => {
  test("returns string", () => {
    const result = color("hello", "green");
    expect(typeof result).toBe("string");
  });

  test("wraps with ANSI codes", () => {
    const result = color("hello", "red");
    expect(result).toContain("\x1b[");
    expect(result).toContain("hello");
    expect(result).toContain("\x1b[0m");
  });

  test("supports green", () => {
    const result = color("ok", "green");
    expect(result).toContain("[32m");
  });

  test("supports red", () => {
    const result = color("fail", "red");
    expect(result).toContain("[31m");
  });

  test("supports yellow", () => {
    const result = color("warn", "yellow");
    expect(result).toContain("[33m");
  });

  test("supports blue", () => {
    const result = color("info", "blue");
    expect(result).toContain("[34m");
  });

  test("supports cyan", () => {
    const result = color("debug", "cyan");
    expect(result).toContain("[36m");
  });

  test("supports bold", () => {
    const result = color("bold", "bold");
    expect(result).toContain("[1m");
  });

  test("supports dim", () => {
    const result = color("dim", "dim");
    expect(result).toContain("[2m");
  });
});

describe("spinner", () => {
  test("returns frames and interval", () => {
    const s = spinner();
    expect(s.frames).toBeInstanceOf(Array);
    expect(s.frames.length).toBeGreaterThan(0);
    expect(s.interval).toBeGreaterThan(0);
  });

  test("frames are strings", () => {
    const s = spinner();
    for (const frame of s.frames) {
      expect(typeof frame).toBe("string");
    }
  });
});
