import { color } from "./ui";
import { expandPath } from "./utils";
import { join, dirname } from "node:path";
import { existsSync, symlinkSync, unlinkSync, readlinkSync, lstatSync, writeFileSync, mkdirSync, readFileSync, statSync, renameSync } from "node:fs";

export interface RunOptions {
  dryRun: boolean;
  verbose: boolean;
  interactive: boolean;
  report?: boolean;
}

export interface LinkResult {
  component: string;
  src: string;
  dest: string;
  success: boolean;
  failed: boolean;
  dryRun: boolean;
  skipped: boolean;
  backedUp: boolean;
  reason?: string;
}

function isSymlink(p: string): boolean {
  try {
    const stat = lstatSync(p);
    return stat.isSymbolicLink();
  } catch {
    return false;
  }
}

export function allLinksCorrect(links: Record<string, string[]>, repoDir: string): boolean {
  if (Object.keys(links).length === 0) return false;
  for (const [src, targets] of Object.entries(links)) {
    const absSrc = join(repoDir, src);
    if (!existsSync(absSrc)) return false;
    for (const target of targets) {
      const dest = expandPath(target);
      if (!existsSync(dest)) return false;
      if (!isSymlink(dest)) return false;
      try {
        const existingTarget = readlinkSync(dest);
        if (existingTarget !== absSrc) return false;
      } catch {
        return false;
      }
    }
  }
  return true;
}

export function createLinks(
  component: string,
  links: Record<string, string[]>,
  repoDir: string,
  options: RunOptions
): LinkResult[] {
  const results: LinkResult[] = [];

  for (const [src, targets] of Object.entries(links)) {
    const absSrc = join(repoDir, src);

    for (const target of targets) {
      const dest = expandPath(target);
      const base: LinkResult = {
        component,
        src: absSrc,
        dest,
        success: false,
        failed: false,
        dryRun: false,
        skipped: false,
        backedUp: false,
      };

      if (options.dryRun) {
        if (options.report) process.stdout.write(`  ${color("[dry-run]", "yellow")} would link ${src} → ${dest}\n`);
        results.push({ ...base, success: true, dryRun: true });
        continue;
      }

      if (!existsSync(absSrc)) {
        if (options.verbose) {
          process.stdout.write(`  ${color("[warn]", "yellow")} ${component}: source not found: ${absSrc}\n`);
        }
        results.push({ ...base, failed: true, reason: `source not found: ${absSrc}` });
        continue;
      }

      if (existsSync(dest)) {
        if (isSymlink(dest)) {
          const existingTarget = readlinkSync(dest);
          if (existingTarget === absSrc) {
            if (options.report) process.stdout.write(`    ${color("✓", "green")} linked ${dest}\n`);
            results.push({ ...base, success: true, skipped: true, reason: "symlink exists and points correctly" });
            continue;
          }
          unlinkSync(dest);
        } else if (statSync(dest).isDirectory()) {
          const bak = dest + ".dot.bak";
          if (options.verbose) {
            process.stdout.write(`  ${color("[backup]", "cyan")} ${dest} → ${bak}\n`);
          }
          renameSync(dest, bak);
        } else {
          const bak = dest + ".dot.bak";
          writeFileSync(bak, readFileSync(dest));
          if (options.verbose) {
            process.stdout.write(`  ${color("[backup]", "cyan")} ${dest} → ${bak}\n`);
          }
          unlinkSync(dest);
        }
      }

      const destDir = dirname(dest);
      try {
        mkdirSync(destDir, { recursive: true });
      } catch {}

      try {
        symlinkSync(absSrc, dest);
        if (options.report) process.stdout.write(`    ${color("✓", "green")} linked ${dest}\n`);
        results.push({ ...base, success: true });
      } catch (e: any) {
        if (options.verbose) {
          process.stderr.write(`  ${color("[error]", "red")} ${component}: failed to link ${dest}: ${e.message}\n`);
        }
        results.push({ ...base, failed: true, reason: e.message });
      }
    }
  }

  return results;
}

export function removeLinks(
  component: string,
  links: Record<string, string[]>,
  repoDir: string,
  options: RunOptions
): LinkResult[] {
  const results: LinkResult[] = [];

  for (const [_src, targets] of Object.entries(links)) {
    for (const target of targets) {
      const dest = expandPath(target);
      const base: LinkResult = {
        component,
        src: _src,
        dest,
        success: false,
        failed: false,
        dryRun: false,
        skipped: false,
        backedUp: false,
      };

      if (options.dryRun) {
        if (options.report) process.stdout.write(`  ${color("[dry-run]", "yellow")} would unlink ${dest}\n`);
        results.push({ ...base, success: true, dryRun: true });
        continue;
      }

      if (!existsSync(dest)) {
        if (options.verbose) {
          process.stdout.write(`  ${color("[skip]", "dim")} ${component}: not found: ${dest}\n`);
        }
        results.push({ ...base, success: true, skipped: true });
        continue;
      }

      if (!isSymlink(dest)) {
        if (options.verbose) {
          process.stdout.write(`  ${color("[skip]", "dim")} ${component}: not a symlink, skipping: ${dest}\n`);
        }
        results.push({ ...base, skipped: true, reason: "not a symlink" });
        continue;
      }

      try {
        unlinkSync(dest);
        if (options.report) process.stdout.write(`    ${color("✓", "green")} unlinked ${dest}\n`);
        results.push({ ...base, success: true });
      } catch (e: any) {
        if (options.verbose) {
          process.stderr.write(`  ${color("[error]", "red")} ${component}: failed to unlink ${dest}: ${e.message}\n`);
        }
        results.push({ ...base, failed: true, reason: e.message });
      }
    }
  }

  return results;
}
