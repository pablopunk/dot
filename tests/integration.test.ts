import { describe, test, expect, beforeEach, afterEach } from "bun:test";
import { tmpdir } from "node:os";
import { mkdtempSync, writeFileSync, rmSync, existsSync, readlinkSync, mkdirSync } from "node:fs";
import { join } from "node:path";
import prompts from "prompts";
import { parseConfig, resolveComponents } from "../src/config";
import { resolveComponentNames } from "../src/fuzzy";
import { createLinks } from "../src/linker";
import { main } from "../src/index";

function makeTempDir(): string {
  return mkdtempSync(join(tmpdir(), "dot-integration-"));
}

describe("integration", () => {
  let repoDir: string;
  let homeDir: string;

  beforeEach(() => {
    repoDir = makeTempDir();
    homeDir = makeTempDir();
    process.env.HOME = homeDir;
  });

  afterEach(() => {
    rmSync(repoDir, { recursive: true, force: true });
    rmSync(homeDir, { recursive: true, force: true });
  });

  test("end to end: config → install → link", async () => {
    const configToml = `
[zsh]
install.any = "echo 'installed zsh'"
link."zshrc" = "~/.zshrc"

[git]
install.any = "echo 'installed git'"
link."gitconfig" = ["~/.gitconfig", "~/.config/git/config"]
postinstall = "echo 'git configured'"
`;
    writeFileSync(join(repoDir, "dot.toml"), configToml);

    writeFileSync(join(repoDir, "zshrc"), "# zsh config");
    writeFileSync(join(repoDir, "gitconfig"), "# git config");

    const config = await parseConfig(join(repoDir, "dot.toml"));
    const resolved = resolveComponents(config, "linux");

    expect(resolved).toHaveLength(2);

    const { found } = resolveComponentNames(["zsh", "git"], resolved.map((c) => c.name));
    expect(found).toContain("zsh");
    expect(found).toContain("git");

    const zshLinks = createLinks("zsh", resolved[0].link, repoDir, { dryRun: false, verbose: false, interactive: false });
    expect(zshLinks[0].success).toBe(true);
    expect(existsSync(join(homeDir, ".zshrc"))).toBe(true);
    expect(readlinkSync(join(homeDir, ".zshrc"))).toBe(join(repoDir, "zshrc"));

    const gitLinks = createLinks("git", resolved[1].link, repoDir, { dryRun: false, verbose: false, interactive: false });
    expect(gitLinks[0].success).toBe(true);
    expect(existsSync(join(homeDir, ".gitconfig"))).toBe(true);
    expect(existsSync(join(homeDir, ".config", "git", "config"))).toBe(true);
  });

  test("interactive installs preserve pipeline input", async () => {
    const marker = join(repoDir, "mise-installed");
    writeFileSync(join(repoDir, "dot.toml"), `
[mise]
install.any = "printf 'touch ${marker}' | sh"
`);

    const originalArgv = process.argv;
    const originalCwd = process.cwd();
    const originalIsTty = Object.getOwnPropertyDescriptor(process.stdin, "isTTY");

    try {
      process.argv = ["dot"];
      process.chdir(repoDir);
      Object.defineProperty(process.stdin, "isTTY", { value: true, configurable: true });
      prompts.inject([["mise"]]);

      await main();

      expect(existsSync(marker)).toBe(true);
    } finally {
      process.argv = originalArgv;
      process.chdir(originalCwd);
      if (originalIsTty) {
        Object.defineProperty(process.stdin, "isTTY", originalIsTty);
      } else {
        delete (process.stdin as any).isTTY;
      }
    }
  });

  test("named install runs the full component lifecycle", async () => {
    const installMarker = join(repoDir, "installed");
    const postInstallMarker = join(repoDir, "postinstalled");
    const postLinkMarker = join(repoDir, "postlinked");
    writeFileSync(join(repoDir, "dot.toml"), `
[zsh]
install.any = "touch ${installMarker}"
link."zshrc" = "~/.zshrc"
postinstall = "touch ${postInstallMarker}"
postlink = "touch ${postLinkMarker}"
`);
    writeFileSync(join(repoDir, "zshrc"), "# zsh config");

    const originalArgv = process.argv;
    const originalCwd = process.cwd();

    try {
      process.argv = ["dot", "-i", "zsh"];
      process.chdir(repoDir);

      await main();

      expect(existsSync(installMarker)).toBe(true);
      expect(existsSync(join(homeDir, ".zshrc"))).toBe(true);
      expect(existsSync(postInstallMarker)).toBe(true);
      expect(existsSync(postLinkMarker)).toBe(true);
    } finally {
      process.argv = originalArgv;
      process.chdir(originalCwd);
    }
  });

  test("direct commands show completed lifecycle steps", async () => {
    const installMarker = join(repoDir, "installed");
    writeFileSync(join(repoDir, "dot.toml"), `
[mise]
install.any = "touch ${installMarker}"
link."config/mise.toml" = "~/.config/mise/config.toml"
postinstall = "true"
postlink = "true"
`);
    mkdirSync(join(repoDir, "config"));
    writeFileSync(join(repoDir, "config/mise.toml"), "# mise config");

    const child = Bun.spawn([process.execPath, join(import.meta.dir, "../src/index.ts"), "-i", "mise"], {
      cwd: repoDir,
      env: { ...process.env, HOME: homeDir },
      stdout: "pipe",
      stderr: "pipe",
    });
    const output = await new Response(child.stdout).text();
    const plainOutput = output.replace(/\x1B\[[0-?]*[ -/]*[@-~]/g, "");

    expect(await child.exited).toBe(0);
    expect(plainOutput).toContain("mise");
    expect(plainOutput).toContain("✓ installed");
    expect(plainOutput).toContain("✓ linked");
    expect(plainOutput).toContain("✓ postinstall");
    expect(plainOutput).toContain("✓ postlink");
    expect(plainOutput).toContain("✓ Done.");
  });

  test("dry run does not create links", async () => {
    const configToml = `
[zsh]
install.any = "echo installed"
link."zshrc" = "~/.zshrc"
`;
    writeFileSync(join(repoDir, "dot.toml"), configToml);
    writeFileSync(join(repoDir, "zshrc"), "# zsh config");

    const config = await parseConfig(join(repoDir, "dot.toml"));
    const resolved = resolveComponents(config, "linux");

    const results = createLinks("zsh", resolved[0].link, repoDir, { dryRun: true, verbose: false, interactive: false });
    expect(results[0].dryRun).toBe(true);
    expect(existsSync(join(homeDir, ".zshrc"))).toBe(false);
  });

  test("config with multiple components", async () => {
    const configToml = `
[zsh]
install.brew = "brew install zsh"
install.apt = "sudo apt install zsh"

[neovim]
install.any = "curl example.com | sh"
os = ["mac", "linux"]

[dock]
defaults."com.apple.dock" = "macos/dock.plist"
os = ["mac"]

[shared-config]
link."shared/.eslintrc" = "~/.eslintrc"
`;
    writeFileSync(join(repoDir, "dot.toml"), configToml);

    const config = await parseConfig(join(repoDir, "dot.toml"));
    expect(config.components).toHaveLength(4);

    const resolved = resolveComponents(config, "linux");
    expect(resolved).toHaveLength(3); // dock filtered out
    expect(resolved.map((c) => c.name)).not.toContain("dock");

    const names = resolved.map((c) => c.name);
    expect(names).toContain("zsh");
    expect(names).toContain("neovim");
    expect(names).toContain("shared-config");
  });

  test("resolves package manager -> install command flow", async () => {
    const configToml = `
[zsh]
install.sh = "echo 'using sh'"
install.any = "echo 'fallback'"
`;
    writeFileSync(join(repoDir, "dot.toml"), configToml);

    const config = await parseConfig(join(repoDir, "dot.toml"));
    const resolved = resolveComponents(config, "linux");

    expect(resolved[0].availableManager).toBe("sh");
    expect(resolved[0].installCommand).toBe("echo 'using sh'");
  });

  test("fuzzy match resolves then links", async () => {
    const configToml = `
[z-shell]
install.any = "echo installed"
link."zshrc" = "~/.zshrc"

[git]
install.any = "echo installed"
`;
    writeFileSync(join(repoDir, "dot.toml"), configToml);
    writeFileSync(join(repoDir, "zshrc"), "# zsh config");

    const config = await parseConfig(join(repoDir, "dot.toml"));
    const resolved = resolveComponents(config, "linux");
    const names = resolved.map((c) => c.name);

    const { found } = resolveComponentNames(["zsh"], names);
    expect(found).toContain("z-shell");
  });

  test("link-only component", async () => {
    const configToml = `
[config]
link."shared/.eslintrc" = "~/.eslintrc"
`;
    writeFileSync(join(repoDir, "dot.toml"), configToml);
    mkdirSync(join(repoDir, "shared"), { recursive: true });
    writeFileSync(join(repoDir, "shared/.eslintrc"), "{}");

    const config = await parseConfig(join(repoDir, "dot.toml"));
    const resolved = resolveComponents(config, "linux");

    expect(resolved[0].hasLinks).toBe(true);
    expect(resolved[0].hasInstall).toBe(false);

    const results = createLinks("config", resolved[0].link, repoDir, { dryRun: false, verbose: false, interactive: false });
    expect(results[0].success).toBe(true);
    expect(existsSync(join(homeDir, ".eslintrc"))).toBe(true);
  });
});
