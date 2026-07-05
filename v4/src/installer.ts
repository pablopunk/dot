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
      result = await Bun.$`${{ raw: command }} < /dev/null`.nothrow().quiet();
    }
    if (result.exitCode !== 0) {
      const stderr = result.stderr.toString();
      if (stderr) {
        process.stderr.write(`  ${color("[error]", "red")} ${name}: ${stderr.trim()}\n`);
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
      result = await Bun.$`${{ raw: command }} < /dev/null`.nothrow().quiet();
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
