import { describe, test, expect, beforeEach, afterEach } from "bun:test";
import { parseConfig, resolveComponents } from "../src/config";
import { tmpdir } from "node:os";
import { mkdtempSync, writeFileSync, rmSync } from "node:fs";
import { join } from "node:path";

function makeTempDir(): string {
  return mkdtempSync(join(tmpdir(), "dot-test-"));
}

describe("parseConfig", () => {
  let tmp: string;

  beforeEach(() => {
    tmp = makeTempDir();
  });

  afterEach(() => {
    rmSync(tmp, { recursive: true, force: true });
  });

  function writeToml(content: string): string {
    const path = join(tmp, "dot.toml");
    writeFileSync(path, content);
    return path;
  }

  test("parses install commands", async () => {
    writeToml(`
[zsh]
install.brew = "brew install zsh"
install.apt = "sudo apt install zsh"
`);
    const config = await parseConfig(join(tmp, "dot.toml"));
    expect(config.components).toHaveLength(1);
    expect(config.components[0].name).toBe("zsh");
    expect(config.components[0].install).toEqual({
      brew: "brew install zsh",
      apt: "sudo apt install zsh",
    });
  });

  test("parses uninstall commands", async () => {
    writeToml(`
[zsh]
uninstall.brew = "brew uninstall zsh"
`);
    const config = await parseConfig(join(tmp, "dot.toml"));
    expect(config.components[0].uninstall).toEqual({
      brew: "brew uninstall zsh",
    });
  });

  test("parses single-dest link", async () => {
    writeToml(`
[zsh]
link."zsh/.zshrc" = "~/.zshrc"
`);
    const config = await parseConfig(join(tmp, "dot.toml"));
    expect(config.components[0].link).toEqual({
      "zsh/.zshrc": ["~/.zshrc"],
    });
  });

  test("parses multi-dest link", async () => {
    writeToml(`
[zsh]
link."zsh/.zshrc" = ["~/.zshrc", "~/.config/zsh/.zshrc"]
`);
    const config = await parseConfig(join(tmp, "dot.toml"));
    expect(config.components[0].link).toEqual({
      "zsh/.zshrc": ["~/.zshrc", "~/.config/zsh/.zshrc"],
    });
  });

  test("parses postinstall hook", async () => {
    writeToml(`
[neovim]
install.brew = "brew install neovim"
postinstall = "echo done"
`);
    const config = await parseConfig(join(tmp, "dot.toml"));
    expect(config.components[0].postinstall).toBe("echo done");
  });

  test("parses postlink hook", async () => {
    writeToml(`
[ssh]
postlink = "chmod 600 ~/.ssh/config"
`);
    const config = await parseConfig(join(tmp, "dot.toml"));
    expect(config.components[0].postlink).toBe("chmod 600 ~/.ssh/config");
  });

  test("parses os filter", async () => {
    writeToml(`
[zsh]
install.brew = "brew install zsh"
os = ["mac", "linux"]
`);
    const config = await parseConfig(join(tmp, "dot.toml"));
    expect(config.components[0].os).toEqual(["mac", "linux"]);
  });

  test("parses defaults", async () => {
    writeToml(`
[dock]
defaults."com.apple.dock" = "macos/dock.plist"
`);
    const config = await parseConfig(join(tmp, "dot.toml"));
    expect(config.components[0].defaults).toEqual({
      "com.apple.dock": "macos/dock.plist",
    });
  });

  test("parses component with no install (link-only)", async () => {
    writeToml(`
[config]
link."shared/.eslintrc" = "~/.eslintrc"
`);
    const config = await parseConfig(join(tmp, "dot.toml"));
    expect(config.components[0].install).toEqual({});
    expect(config.components[0].link).toEqual({
      "shared/.eslintrc": ["~/.eslintrc"],
    });
  });

  test("parses multiple components", async () => {
    writeToml(`
[zsh]
install.brew = "brew install zsh"

[git]
install.brew = "brew install git"
link."git/.gitconfig" = "~/.gitconfig"
`);
    const config = await parseConfig(join(tmp, "dot.toml"));
    expect(config.components).toHaveLength(2);
    expect(config.components[0].name).toBe("zsh");
    expect(config.components[1].name).toBe("git");
  });

  test("throws on missing file", async () => {
    await expect(parseConfig("/nonexistent/dot.toml")).rejects.toThrow();
  });

  test("throws on invalid TOML", async () => {
    const path = writeToml("this is {{{ not toml");
    await expect(parseConfig(path)).rejects.toThrow();
  });

  test("empty TOML returns empty components", async () => {
    const path = writeToml("");
    const config = await parseConfig(path);
    expect(config.components).toEqual([]);
  });

  test("TOML with non-component sections is ok (ignored config-level keys)", async () => {
    const path = writeToml(`
title = "my dotfiles"

[zsh]
install.brew = "brew install zsh"
`);
    const config = await parseConfig(path);
    expect(config.components).toHaveLength(1);
    expect(config.components[0].name).toBe("zsh");
  });

  test("any install key is parsed like any other", async () => {
    writeToml(`
[neovim]
install.any = "curl example.com/install.sh | bash"
`);
    const config = await parseConfig(join(tmp, "dot.toml"));
    expect(config.components[0].install).toEqual({
      any: "curl example.com/install.sh | bash",
    });
  });
});

describe("resolveComponents", () => {
  let tmp: string;

  beforeEach(() => {
    tmp = makeTempDir();
  });

  afterEach(() => {
    rmSync(tmp, { recursive: true, force: true });
  });

  async function makeConfig(components: any[]): Promise<string> {
    let toml = "";
    for (const c of components) {
      toml += `\n[${c.name}]\n`;
      for (const [mgr, cmd] of Object.entries(c.install || {})) {
        toml += `install.${mgr} = "${cmd}"\n`;
      }
      for (const [src, targets] of Object.entries(c.link || {})) {
        if (Array.isArray(targets)) {
          toml += `link."${src}" = [${targets.map((t: string) => `"${t}"`).join(", ")}]\n`;
        } else {
          toml += `link."${src}" = "${targets}"\n`;
        }
      }
      if (c.postinstall) toml += `postinstall = "${c.postinstall}"\n`;
      if (c.postlink) toml += `postlink = "${c.postlink}"\n`;
      if (c.defaults) {
        for (const [domain, file] of Object.entries(c.defaults)) {
          toml += `defaults."${domain}" = "${file}"\n`;
        }
      }
      if (c.os) toml += `os = [${c.os.map((o: string) => `"${o}"`).join(", ")}]\n`;
    }
    writeFileSync(join(tmp, "dot.toml"), toml);
    return join(tmp, "dot.toml");
  }

  test("resolves brew as available manager", async () => {
    await makeConfig([{
      name: "zsh",
      install: { brew: "brew install zsh", apt: "sudo apt install zsh" },
    }]);
    const config = await parseConfig(join(tmp, "dot.toml"));
    const resolved = resolveComponents(config, "linux");
    expect(resolved[0].availableManager).toBeDefined();
    expect(resolved[0].installCommand).toBeDefined();
  });

  test("resolves any as fallback when nothing else matches", async () => {
    await makeConfig([{
      name: "custom",
      install: {
        nonexistentmgr: "echo fail",
        any: "curl example.com/install.sh | bash",
      },
    }]);
    const config = await parseConfig(join(tmp, "dot.toml"));
    const resolved = resolveComponents(config, "linux");
    expect(resolved[0].availableManager).toBe("any");
    expect(resolved[0].installCommand).toBe("curl example.com/install.sh | bash");
  });

  test("null manager when nothing works and no any", async () => {
    await makeConfig([{
      name: "custom",
      install: { nonexistentmgr: "echo fail" },
    }]);
    const config = await parseConfig(join(tmp, "dot.toml"));
    const resolved = resolveComponents(config, "linux");
    expect(resolved[0].availableManager).toBeNull();
    expect(resolved[0].installCommand).toBeNull();
  });

  test("filters by OS (matches)", async () => {
    await makeConfig([{
      name: "zsh",
      install: { brew: "brew install zsh" },
      os: ["mac", "linux"],
    }]);
    const config = await parseConfig(join(tmp, "dot.toml"));
    const resolved = resolveComponents(config, "linux");
    expect(resolved).toHaveLength(1);
  });

  test("filters by OS (does not match)", async () => {
    await makeConfig([{
      name: "dock",
      install: { brew: "brew install dock" },
      os: ["mac"],
    }]);
    const config = await parseConfig(join(tmp, "dot.toml"));
    const resolved = resolveComponents(config, "linux");
    expect(resolved).toHaveLength(0);
  });

  test("no os filter means always included", async () => {
    await makeConfig([{
      name: "zsh",
      install: { brew: "brew install zsh" },
    }]);
    const config = await parseConfig(join(tmp, "dot.toml"));
    const resolved = resolveComponents(config, "linux");
    expect(resolved).toHaveLength(1);
  });

  test("sets hasDefaults flag", async () => {
    await makeConfig([{
      name: "dock",
      defaults: { "com.apple.dock": "dock.plist" },
    }]);
    const config = await parseConfig(join(tmp, "dot.toml"));
    const resolved = resolveComponents(config, "mac");
    expect(resolved[0].hasDefaults).toBe(true);
  });

  test("no defaults → hasDefaults is false", async () => {
    await makeConfig([{ name: "zsh", install: { brew: "brew install zsh" } }]);
    const config = await parseConfig(join(tmp, "dot.toml"));
    const resolved = resolveComponents(config, "linux");
    expect(resolved[0].hasDefaults).toBe(false);
  });

  test("sets hasLinks flag", async () => {
    await makeConfig([{
      name: "zsh",
      install: { brew: "brew install zsh" },
      link: { "zsh/.zshrc": "~/.zshrc" },
    }]);
    const config = await parseConfig(join(tmp, "dot.toml"));
    const resolved = resolveComponents(config, "linux");
    expect(resolved[0].hasLinks).toBe(true);
  });

  test("no links → hasLinks is false", async () => {
    await makeConfig([{ name: "zsh", install: { brew: "brew install zsh" } }]);
    const config = await parseConfig(join(tmp, "dot.toml"));
    const resolved = resolveComponents(config, "linux");
    expect(resolved[0].hasLinks).toBe(false);
  });

  test("sets hasInstall flag", async () => {
    await makeConfig([{ name: "zsh", install: { brew: "brew install zsh" } }]);
    const config = await parseConfig(join(tmp, "dot.toml"));
    const resolved = resolveComponents(config, "linux");
    expect(resolved[0].hasInstall).toBe(true);
  });

  test("no install → hasInstall is false", async () => {
    await makeConfig([{ name: "config", link: { "config/.foo": "~/.foo" } }]);
    const config = await parseConfig(join(tmp, "dot.toml"));
    const resolved = resolveComponents(config, "linux");
    expect(resolved[0].hasInstall).toBe(false);
  });
});
