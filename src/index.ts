import { parseArgs } from "./cli";
import { parseConfig, resolveComponents } from "./config";
import { resolveComponentNames } from "./fuzzy";
import { runInteractive } from "./interactive";
import { installComponent, uninstallComponent } from "./installer";
import { createLinks } from "./linker";
import { runPostInstall, runPostLink } from "./hooks";
import { exportDefaults, importDefaults } from "./defaults";
import { selfUpgrade } from "./upgrade";
import { detectOS } from "./utils";
import { color } from "./ui";
import { showCursor, clearScreen } from "./renderer";

const VERSION = process.env.DOT_VERSION || "dev";

function printHelp(): void {
  process.stdout.write(`
  dot — manage your dotfiles

  Usage:
    dot                          Interactive checklist (default)
    dot [flags...]

  Actions (combinable, repeatable):
    -i, --install <name>         Install component (fuzzy match)
    -u, --uninstall <name>       Uninstall component
    -l, --link <name>            Link files for component
    --postinstall <name>         Run postinstall hooks
    --postlink <name>            Run postlink hooks
    -e, --defaults-export        Export macOS defaults
    -I, --defaults-import        Import macOS defaults
    --list                       List all components
    --upgrade                    Self-upgrade binary

  Modifiers:
    --dry-run                    Preview only
    -v, --verbose                Verbose output

  Meta:
    -h, --help                   Show this help
    --version                    Show version

  Examples:
    dot -i zsh -i nvim -v        Install zsh + nvim, verbose
    dot -u zsh                   Uninstall zsh
    dot -l git                   Link git files
    dot --dry-run -i nvim        Preview nvim install

`);
}

function printVersion(): void {
  const ver = VERSION.startsWith("v") ? VERSION : `v${VERSION}`;
  process.stdout.write(`dot ${ver}\n`);
}

function printList(resolved: ReturnType<typeof resolveComponents>): void {
  process.stdout.write(`\n  Available components:\n\n`);
  for (const c of resolved) {
    const mgr = c.availableManager || (c.hasDefaults ? "defaults" : c.hasLinks ? "link-only" : "none");
    const mgrColor = c.availableManager && c.availableManager !== "any" ? "green"
      : c.availableManager === "any" ? "yellow"
      : "red";
    process.stdout.write(`  ${color(c.name.padEnd(20), "bold")} ${color(`[${mgr}]`, mgrColor)}\n`);
  }
  process.stdout.write(`\n`);
}

export async function main(): Promise<void> {
  const args = parseArgs(process.argv);

  if (args.mode === "meta") {
    if (args.meta === "help") { printHelp(); return; }
    if (args.meta === "version") { printVersion(); return; }
    if (args.meta === "upgrade") {
      await selfUpgrade();
      return;
    }
    return;
  }

  let config;
  try {
    config = await parseConfig("dot.toml");
  } catch (e: any) {
    process.stderr.write(`${color("[error]", "red")} ${e.message}\n`);
    process.exit(1);
  }

  const os = detectOS();
  const resolved = resolveComponents(config, os);

  if (resolved.length === 0) {
    process.stdout.write(`${color("[warn]", "yellow")} No components found in config for this OS\n`);
    process.exit(0);
  }

  const isTty = process.stdin.isTTY ?? false;
  const options = { dryRun: args.dryRun, verbose: args.verbose, interactive: isTty && args.mode === "direct" };

  if (args.mode === "interactive") {
    const selected = await runInteractive(resolved);
    if (selected.length === 0) {
      process.exit(0);
    }

    const action = args.interactiveAction;

    for (const item of selected) {
      if (item.unavailable) continue;
      const comp = resolved.find((c: { name: string }) => c.name === item.name);
      if (!comp) continue;

      if (!action || action === "install") {
        if (comp.installCommand) {
          const result = await installComponent(comp.name, comp.installCommand, options, comp.availableManager || undefined);
          if (result.failed) {
            process.stderr.write(`  ${color("[error]", "red")} ${comp.name}: install failed\n`);
          }
        }
      }

      if (!action || action === "install") {
        if (comp.hasDefaults && os === "mac") {
          await importDefaults(comp.defaults, process.cwd(), options);
        }
      }

      if (!action || action === "link") {
        if (comp.hasLinks) {
          createLinks(comp.name, comp.link, process.cwd(), options);
        }
      }

      if (!action || action === "postinstall") {
        if (comp.postinstall) {
          await runPostInstall(comp.name, comp.postinstall, options);
        }
      }

      if (!action || action === "postlink") {
        if (comp.postlink) {
          await runPostLink(comp.name, comp.postlink, options);
        }
      }

      if (action === "uninstall") {
        const uninstallCmd = Object.entries(comp.uninstall)[0];
        if (uninstallCmd) {
          const [, cmd] = uninstallCmd;
          await uninstallComponent(comp.name, cmd, options);
        }
      }
    }

    return;
  }

  if (args.mode === "direct") {
    const names = resolved.map((c: { name: string }) => c.name);

    if (args.list) {
      printList(resolved);
      return;
    }

    const hasOnlyModifiers = (
      !args.install.length &&
      !args.uninstall.length &&
      !args.link.length &&
      !args.postinstall.length &&
      !args.postlink.length &&
      !args.exportDefaults &&
      !args.importDefaults &&
      !args.list
    );

    if (hasOnlyModifiers) {
      process.stderr.write(`${color("[error]", "red")} No actions specified. Use --help for usage.\n`);
      process.exit(1);
    }

    const failures: string[] = [];

    if (args.uninstall.length > 0) {
      if (args.verbose) process.stdout.write(`\n${color("Uninstall", "bold")}\n`);
      const { found, missing } = resolveComponentNames(args.uninstall, names);
      for (const m of missing) {
        process.stdout.write(`  ${color("[warn]", "yellow")} component not found: ${m}\n`);
      }
      for (const name of found) {
        const comp = resolved.find((c: { name: string }) => c.name === name)!;
        const uninstallCmd = Object.entries(comp.uninstall)[0];
        if (!uninstallCmd) {
          process.stdout.write(`  ${color("[skip]", "dim")} ${name}: no uninstall command\n`);
          continue;
        }
        const [, cmd] = uninstallCmd;
        const result = await uninstallComponent(name, cmd, options);
        if (result.failed && !result.dryRun) failures.push(name);
      }
    }

    if (args.install.length > 0) {
      if (args.verbose) process.stdout.write(`\n${color("Install", "bold")}\n`);
      const { found, missing } = resolveComponentNames(args.install, names);
      for (const m of missing) {
        process.stdout.write(`  ${color("[warn]", "yellow")} component not found: ${m}\n`);
      }
      for (const name of found) {
        const comp = resolved.find((c: { name: string }) => c.name === name)!;
        if (comp.installCommand) {
          const result = await installComponent(name, comp.installCommand, options, comp.availableManager || undefined);
          if (result.failed && !result.dryRun) failures.push(name);
        }
      }
    }

    if (args.importDefaults) {
      if (args.verbose) process.stdout.write(`\n${color("Defaults", "bold")}\n`);
      const allDefaults = Object.fromEntries(
        resolved
          .filter((c: { hasDefaults: boolean }) => c.hasDefaults)
          .flatMap((c: { defaults: Record<string, string> }) => Object.entries(c.defaults))
      );
      const results = await importDefaults(allDefaults, process.cwd(), options);
      for (const r of results) {
        if (r.failed && !r.dryRun) failures.push(r.domain);
      }
    }

    if (args.exportDefaults) {
      if (args.verbose) process.stdout.write(`\n${color("Defaults Export", "bold")}\n`);
      const allDefaults = Object.fromEntries(
        resolved
          .filter((c: { hasDefaults: boolean }) => c.hasDefaults)
          .flatMap((c: { defaults: Record<string, string> }) => Object.entries(c.defaults))
      );
      const results = await exportDefaults(allDefaults, process.cwd(), options);
      for (const r of results) {
        if (r.failed && !r.dryRun) failures.push(r.domain);
      }
    }

    if (args.link.length > 0) {
      if (args.verbose) process.stdout.write(`\n${color("Link", "bold")}\n`);
      const { found, missing } = resolveComponentNames(args.link, names);
      for (const m of missing) {
        process.stdout.write(`  ${color("[warn]", "yellow")} component not found: ${m}\n`);
      }
      for (const name of found) {
        const comp = resolved.find((c: { name: string }) => c.name === name)!;
        if (comp.hasLinks) {
          const results = createLinks(name, comp.link, process.cwd(), options);
          for (const r of results) {
            if (r.failed && !r.dryRun) failures.push(name);
          }
        }
      }
    }

    if (args.postinstall.length > 0) {
      if (args.verbose) process.stdout.write(`\n${color("Post-install", "bold")}\n`);
      const { found, missing } = resolveComponentNames(args.postinstall, names);
      for (const m of missing) {
        process.stdout.write(`  ${color("[warn]", "yellow")} component not found: ${m}\n`);
      }
      for (const name of found) {
        const comp = resolved.find((c: { name: string }) => c.name === name)!;
        if (comp.postinstall) {
          const result = await runPostInstall(name, comp.postinstall, options);
          if (result.failed && !result.dryRun) failures.push(name);
        }
      }
    }

    if (args.postlink.length > 0) {
      if (args.verbose) process.stdout.write(`\n${color("Post-link", "bold")}\n`);
      const { found, missing } = resolveComponentNames(args.postlink, names);
      for (const m of missing) {
        process.stdout.write(`  ${color("[warn]", "yellow")} component not found: ${m}\n`);
      }
      for (const name of found) {
        const comp = resolved.find((c: { name: string }) => c.name === name)!;
        if (comp.postlink) {
          const result = await runPostLink(name, comp.postlink, options);
          if (result.failed && !result.dryRun) failures.push(name);
        }
      }
    }

    if (failures.length > 0) {
      process.stderr.write(`\n${color(`  ${failures.length} failure(s)`, "red")}\n`);
      process.exit(1);
    }

    if (options.verbose) {
      process.stdout.write(`\n${color("  Done.", "green")}\n`);
    }
  }
}

export { VERSION };

if (import.meta.main) {
  main().catch((e) => {
    process.stderr.write(`Fatal: ${e.message}\n`);
    process.exit(1);
  });
}
