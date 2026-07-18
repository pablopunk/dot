import { color } from "./ui";

export interface RunOptions {
  dryRun: boolean;
  verbose: boolean;
  interactive: boolean;
}

export interface RunResult {
  component: string;
  success: boolean;
  failed: boolean;
  dryRun: boolean;
  manager?: string;
}

async function runNonInteractive(command: string): Promise<{ exitCode: number; stderr: Buffer }> {
  const shellCommand = process.platform === "win32"
    ? [process.env.ComSpec || "cmd.exe", "/d", "/s", "/c", command]
    : [Bun.which("bash") || "/bin/sh", "-c", command];
  const child = Bun.spawn(shellCommand, {
    stdin: "ignore",
    stdout: "pipe",
    stderr: "pipe",
  });
  const [exitCode, stderr] = await Promise.all([
    child.exited,
    new Response(child.stderr).arrayBuffer(),
    new Response(child.stdout).arrayBuffer(),
  ]);
  return { exitCode, stderr: Buffer.from(stderr) };
}

export async function installComponent(
  name: string,
  command: string | null,
  options: RunOptions,
  manager?: string
): Promise<RunResult> {
  const base: RunResult = { component: name, success: false, failed: false, dryRun: false, manager };

  if (!command) {
    return { ...base, failed: true };
  }

  if (options.dryRun) {
    if (options.verbose) {
      process.stdout.write(`  ${color("[dry-run]", "yellow")} would run: ${command}\n`);
    }
    return { ...base, success: true, dryRun: true };
  }

  if (options.verbose) {
    process.stdout.write(`  ${color("[install]", "blue")} ${name}: ${command}\n`);
  }

  try {
    let result;
    if (options.interactive) {
      result = await Bun.$`${{ raw: command }}`.nothrow().quiet();
    } else {
      result = await runNonInteractive(command);
    }
    if (result.exitCode !== 0) {
      if (options.verbose) {
        const stderr = result.stderr.toString().trim();
        if (stderr) process.stderr.write(`  ${color("[error]", "red")} ${name}: ${stderr}\n`);
      }
      return { ...base, failed: true };
    }
  } catch (e: any) {
    if (e.exitCode !== undefined && e.exitCode !== 0) {
      return { ...base, failed: true };
    }
    throw e;
  }

  if (options.verbose) {
    process.stdout.write(`  ${color("[ok]", "green")} ${name}\n`);
  }

  return { ...base, success: true };
}

export async function uninstallComponent(
  name: string,
  command: string | null,
  options: RunOptions
): Promise<RunResult> {
  const base: RunResult = { component: name, success: false, failed: false, dryRun: false };

  if (!command) {
    return { ...base, failed: true };
  }

  if (options.dryRun) {
    if (options.verbose) {
      process.stdout.write(`  ${color("[dry-run]", "yellow")} would run: ${command}\n`);
    }
    return { ...base, success: true, dryRun: true };
  }

  if (options.verbose) {
    process.stdout.write(`  ${color("[uninstall]", "blue")} ${name}: ${command}\n`);
  }

  try {
    let result;
    if (options.interactive) {
      result = await Bun.$`${{ raw: command }}`.nothrow().quiet();
    } else {
      result = await runNonInteractive(command);
    }
    if (result.exitCode !== 0) {
      return { ...base, failed: true };
    }
  } catch (e: any) {
    if (e.exitCode !== undefined && e.exitCode !== 0) {
      return { ...base, failed: true };
    }
    throw e;
  }

  if (options.verbose) {
    process.stdout.write(`  ${color("[ok]", "green")} ${name} uninstalled\n`);
  }

  return { ...base, success: true };
}
