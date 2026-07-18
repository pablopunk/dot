import { closeSync, openSync } from "node:fs";
import { ReadStream } from "node:tty";

export function openTerminalInput(terminalPath = "/dev/tty"): ReadStream | null {
  if (process.platform === "win32") {
    return null;
  }

  let terminalFd: number | null = null;
  try {
    terminalFd = openSync(terminalPath, "r");
    return new ReadStream(terminalFd);
  } catch {
    if (terminalFd !== null) closeSync(terminalFd);
    return null;
  }
}
