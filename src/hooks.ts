import { color } from "./ui";

export interface RunOptions {
  dryRun: boolean;
  verbose: boolean;
  interactive: boolean;
  report?: boolean;
}

export interface HookResult {
  component: string;
  success: boolean;
  failed: boolean;
  dryRun: boolean;
  skipped: boolean;
}

export async function runPostInstall(
  component: string,
  hook: string | null | undefined,
  options: RunOptions
): Promise<HookResult> {
  const base: HookResult = { component, success: false, failed: false, dryRun: false, skipped: false };

  if (!hook) {
    return { ...base, success: true, skipped: true };
  }

  if (options.dryRun) {
    if (options.report) process.stdout.write(`  ${color("[dry-run]", "yellow")} ${component} postinstall: ${hook}\n`);
    return { ...base, success: true, dryRun: true };
  }

  if (options.verbose) {
    process.stdout.write(`  ${color("[postinstall]", "blue")} ${component}: ${hook}\n`);
  }

  try {
    const result = await Bun.$`${{ raw: hook }}`.nothrow().quiet();
    if (result.exitCode !== 0) {
      const stderr = result.stderr.toString();
      if (stderr) {
        process.stderr.write(`  ${color("[error]", "red")} ${component}: ${stderr.trim()}\n`);
      }
      return { ...base, failed: true };
    }
  } catch (e: any) {
    if (e.exitCode !== undefined && e.exitCode !== 0) {
      return { ...base, failed: true };
    }
    throw e;
  }

  if (options.report) process.stdout.write(`    ${color("✓", "green")} postinstall\n`);
  return { ...base, success: true };
}

export async function runPostLink(
  component: string,
  hook: string | null | undefined,
  options: RunOptions
): Promise<HookResult> {
  const base: HookResult = { component, success: false, failed: false, dryRun: false, skipped: false };

  if (!hook) {
    return { ...base, success: true, skipped: true };
  }

  if (options.dryRun) {
    if (options.report) process.stdout.write(`  ${color("[dry-run]", "yellow")} ${component} postlink: ${hook}\n`);
    return { ...base, success: true, dryRun: true };
  }

  if (options.verbose) {
    process.stdout.write(`  ${color("[postlink]", "blue")} ${component}: ${hook}\n`);
  }

  try {
    const result = await Bun.$`${{ raw: hook }}`.nothrow().quiet();
    if (result.exitCode !== 0) {
      const stderr = result.stderr.toString();
      if (stderr) {
        process.stderr.write(`  ${color("[error]", "red")} ${component}: ${stderr.trim()}\n`);
      }
      return { ...base, failed: true };
    }
  } catch (e: any) {
    if (e.exitCode !== undefined && e.exitCode !== 0) {
      return { ...base, failed: true };
    }
    throw e;
  }

  if (options.report) process.stdout.write(`    ${color("✓", "green")} postlink\n`);
  return { ...base, success: true };
}
