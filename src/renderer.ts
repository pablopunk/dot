export function hideCursor(): string {
  return "\x1b[?25l";
}

export function showCursor(): string {
  return "\x1b[?25h";
}

export function clearLine(): string {
  return "\x1b[2K\x1b[G";
}

export function moveUp(n: number = 1): string {
  return `\x1b[${n}A`;
}

export function inverseOn(): string {
  return "\x1b[7m";
}

export function inverseOff(): string {
  return "\x1b[0m";
}

export function moveTo(row: number, col: number): string {
  return `\x1b[${row};${col}H`;
}

export function clearScreen(): string {
  return "\x1b[2J\x1b[H";
}
