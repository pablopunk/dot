import { describe, test, expect } from "bun:test";
import {
  hideCursor,
  showCursor,
  clearLine,
  moveUp,
  inverseOn,
  inverseOff,
  moveTo,
  clearScreen,
} from "../src/renderer";

describe("hideCursor", () => {
  test("returns ANSI escape", () => {
    expect(hideCursor()).toBe("\x1b[?25l");
  });
});

describe("showCursor", () => {
  test("returns ANSI escape", () => {
    expect(showCursor()).toBe("\x1b[?25h");
  });
});

describe("clearLine", () => {
  test("returns ANSI escape", () => {
    expect(clearLine()).toBe("\x1b[2K\x1b[G");
  });
});

describe("moveUp", () => {
  test("moves up N lines", () => {
    expect(moveUp(3)).toBe("\x1b[3A");
  });

  test("defaults to 1", () => {
    expect(moveUp(1)).toBe("\x1b[1A");
  });
});

describe("inverseOn", () => {
  test("returns ANSI escape", () => {
    expect(inverseOn()).toBe("\x1b[7m");
  });
});

describe("inverseOff", () => {
  test("returns ANSI escape", () => {
    expect(inverseOff()).toBe("\x1b[0m");
  });
});

describe("moveTo", () => {
  test("moves to row col", () => {
    expect(moveTo(5, 10)).toBe("\x1b[5;10H");
  });
});

describe("clearScreen", () => {
  test("clears and moves to top", () => {
    expect(clearScreen()).toBe("\x1b[2J\x1b[H");
  });
});
