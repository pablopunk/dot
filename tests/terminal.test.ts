import { describe, expect, test } from "bun:test";
import { openTerminalInput } from "../src/terminal";

describe("openTerminalInput", () => {
  test("returns null when no terminal can be opened", async () => {
    const result = openTerminalInput("/definitely/missing/dot-terminal");

    expect(result).toBeNull();
  });
});
