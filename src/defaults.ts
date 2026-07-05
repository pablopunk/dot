import { color } from "./ui";
import { join } from "node:path";

export interface RunOptions {
  dryRun: boolean;
  verbose: boolean;
  interactive: boolean;
}

export interface DefaultsResult {
  domain: string;
  file: string;
  success: boolean;
  failed: boolean;
  dryRun: boolean;
  skipped: boolean;
  reason?: string;
}

export async function exportDefaults(
  defaults: Record<string, string>,
  repoDir: string,
  options: RunOptions
): Promise<DefaultsResult[]> {
  const results: DefaultsResult[] = [];

  if (Object.keys(defaults).length === 0) return results;

  if (process.platform !== "darwin") {
    for (const [domain, file] of Object.entries(defaults)) {
      results.push({
        domain,
        file,
        success: false,
        failed: false,
        dryRun: false,
        skipped: true,
        reason: "defaults only available on macOS",
      });
    }
    return results;
  }

  for (const [domain, file] of Object.entries(defaults)) {
    const absFile = join(repoDir, file);
    const base: DefaultsResult = { domain, file, success: false, failed: false, dryRun: false, skipped: false };

    if (options.dryRun) {
      if (options.verbose) {
        process.stdout.write(`  ${color("[dry-run]", "yellow")} would export ${domain} → ${file}\n`);
      }
      results.push({ ...base, success: true, dryRun: true });
      continue;
    }

    try {
      if (file.endsWith(".xml")) {
        const proc = Bun.spawnSync(["defaults", "export", domain, "-"], { stdout: "pipe" });
        Bun.write(absFile, proc.stdout);
      } else {
        const proc = Bun.spawnSync(["defaults", "read", domain], { stdout: "pipe" });
        Bun.write(absFile, proc.stdout);
      }

      if (options.verbose) {
        process.stdout.write(`  ${color("[export]", "green")} ${domain} → ${file}\n`);
      }
      results.push({ ...base, success: true });
    } catch (e: any) {
      if (options.verbose) {
        process.stderr.write(`  ${color("[error]", "red")} ${domain}: ${e.message}\n`);
      }
      results.push({ ...base, failed: true, reason: e.message });
    }
  }

  return results;
}

export async function importDefaults(
  defaults: Record<string, string>,
  repoDir: string,
  options: RunOptions
): Promise<DefaultsResult[]> {
  const results: DefaultsResult[] = [];

  if (Object.keys(defaults).length === 0) return results;

  if (process.platform !== "darwin") {
    for (const [domain, file] of Object.entries(defaults)) {
      results.push({
        domain,
        file,
        success: false,
        failed: false,
        dryRun: false,
        skipped: true,
        reason: "defaults only available on macOS",
      });
    }
    return results;
  }

  for (const [domain, file] of Object.entries(defaults)) {
    const absFile = join(repoDir, file);
    const base: DefaultsResult = { domain, file, success: false, failed: false, dryRun: false, skipped: false };

    if (options.dryRun) {
      if (options.verbose) {
        process.stdout.write(`  ${color("[dry-run]", "yellow")} would import ${file} → ${domain}\n`);
      }
      results.push({ ...base, success: true, dryRun: true });
      continue;
    }

    const f = Bun.file(absFile);
    if (!f.exists()) {
      if (options.verbose) {
        process.stdout.write(`  ${color("[warn]", "yellow")} ${domain}: file not found: ${absFile}\n`);
      }
      results.push({ ...base, failed: true, reason: `file not found: ${absFile}` });
      continue;
    }

    try {
      const proc = Bun.spawnSync(["defaults", "import", domain, absFile]);
      if (proc.exitCode !== 0) {
        if (options.verbose) {
          process.stdout.write(`  ${color("[error]", "red")} ${domain}: defaults import failed (exit ${proc.exitCode})\n`);
        }
        results.push({ ...base, failed: true, reason: `defaults import exited with code ${proc.exitCode}` });
        continue;
      }
      if (options.verbose) {
        process.stdout.write(`  ${color("[import]", "green")} ${file} → ${domain}\n`);
      }
      results.push({ ...base, success: true });
    } catch (e: any) {
      if (options.verbose) {
        process.stderr.write(`  ${color("[error]", "red")} ${domain}: ${e.message}\n`);
      }
      results.push({ ...base, failed: true, reason: e.message });
    }
  }

  return results;
}
