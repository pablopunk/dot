export function detectOS(): string {
  const platform = process.platform;
  if (platform === "darwin") return "mac";
  if (platform === "linux") return "linux";
  if (platform === "win32") return "windows";
  return "linux";
}

export function expandPath(p: string): string {
  const home = process.env.HOME;
  if (!home) return p;
  if (p === "~") return home;
  if (p.startsWith("~/")) return home + p.slice(1);
  return p;
}

export function binaryExists(name: string): boolean {
  return Bun.which(name) !== null;
}

export function isTTY(): boolean {
  return process.stdin.isTTY ?? false;
}
