const COLORS: Record<string, string> = {
  green: "32",
  red: "31",
  yellow: "33",
  blue: "34",
  cyan: "36",
  bold: "1",
  dim: "2",
  reset: "0",
};

export function color(str: string, c: string): string {
  const code = COLORS[c] || "0";
  return `\x1b[${code}m${str}\x1b[0m`;
}

export function spinner(): { frames: string[]; interval: number } {
  return {
    frames: ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"],
    interval: 80,
  };
}
