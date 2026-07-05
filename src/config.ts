import { expandPath } from "./utils";
import { join } from "node:path";
import { existsSync, readlinkSync, lstatSync } from "node:fs";

export interface Component {
  name: string;
  install: Record<string, string>;
  uninstall: Record<string, string>;
  link: Record<string, string[]>;
  postinstall?: string;
  postlink?: string;
  defaults: Record<string, string>;
  os?: string[];
  check?: string;
}

export interface ResolvedComponent extends Component {
  availableManager: string | null;
  installCommand: string | null;
  hasDefaults: boolean;
  hasLinks: boolean;
  hasInstall: boolean;
  allLinksDone: boolean;
  isInstalled: boolean;
}

export interface Config {
  components: Component[];
}

export async function parseConfig(path?: string): Promise<Config> {
  const filePath = path || "dot.toml";
  const file = Bun.file(filePath);
  if (!(await file.exists())) throw new Error(`Config file not found: ${filePath}`);

  const raw = await file.text();

  let parsed: any;
  try {
    parsed = Bun.TOML.parse(raw);
  } catch (e: any) {
    throw new Error(`Invalid TOML in ${filePath}: ${e.message}`);
  }

  if (!parsed || typeof parsed !== "object") return { components: [] };

  const components: Component[] = [];
  for (const [name, section] of Object.entries(parsed)) {
    if (typeof section !== "object" || section === null || Array.isArray(section)) continue;

    const s = section as Record<string, any>;

    const component: Component = {
      name,
      install: {},
      uninstall: {},
      link: {},
      defaults: {},
    };

    for (const [key, value] of Object.entries(s)) {
      if (key === "os") {
        if (Array.isArray(value)) {
          component.os = value.map(String);
        }
      } else if (key === "postinstall") {
        component.postinstall = String(value);
      } else if (key === "postlink") {
        component.postlink = String(value);
      } else if (key === "check") {
        component.check = String(value);
      } else if (key === "install" && typeof value === "object" && value !== null && !Array.isArray(value)) {
        for (const [mgr, cmd] of Object.entries(value as Record<string, unknown>)) {
          component.install[mgr] = String(cmd);
        }
      } else if (key === "uninstall" && typeof value === "object" && value !== null && !Array.isArray(value)) {
        for (const [mgr, cmd] of Object.entries(value as Record<string, unknown>)) {
          component.uninstall[mgr] = String(cmd);
        }
      } else if (key === "link" && typeof value === "object" && value !== null && !Array.isArray(value)) {
        for (const [src, targets] of Object.entries(value as Record<string, unknown>)) {
          if (Array.isArray(targets)) {
            component.link[src] = targets.map(String);
          } else {
            component.link[src] = [String(targets)];
          }
        }
      } else if (key === "defaults" && typeof value === "object" && value !== null && !Array.isArray(value)) {
        for (const [domain, file] of Object.entries(value as Record<string, unknown>)) {
          component.defaults[domain] = String(file);
        }
      }
    }

    if (Object.keys(component.install).length > 0 ||
        Object.keys(component.uninstall).length > 0 ||
        Object.keys(component.link).length > 0 ||
        Object.keys(component.defaults).length > 0 ||
        component.postinstall ||
        component.postlink) {
      components.push(component);
    }
  }

  return { components };
}

function linksAllCorrect(component: Component): boolean {
  const links = component.link;
  if (Object.keys(links).length === 0) return false;
  const repoDir = process.cwd();
  for (const [src, targets] of Object.entries(links)) {
    const absSrc = join(repoDir, src);
    if (!existsSync(absSrc)) return false;
    for (const target of targets) {
      const dest = expandPath(target);
      if (!existsSync(dest)) return false;
      try {
        if (!lstatSync(dest).isSymbolicLink()) return false;
        if (readlinkSync(dest) !== absSrc) return false;
      } catch {
        return false;
      }
    }
  }
  return true;
}

export function isCheckInstalled(check: string): boolean {
  if (check.includes(" ")) {
    const result = Bun.spawnSync(["sh", "-c", check], { stdout: null, stderr: null });
    return result.exitCode === 0;
  }
  return Bun.which(check) !== null;
}

export function resolveComponents(config: Config, os: string): ResolvedComponent[] {
  return config.components
    .filter((c) => {
      if (!c.os || c.os.length === 0) return true;
      return c.os.includes(os);
    })
    .map((c) => {
      let availableManager: string | null = null;
      let installCommand: string | null = null;

      const managers = Object.keys(c.install);
      for (const mgr of managers) {
        if (mgr === "any") continue;
        if (Bun.which(mgr)) {
          availableManager = mgr;
          installCommand = c.install[mgr];
          break;
        }
      }

      if (!availableManager && c.install["any"]) {
        availableManager = "any";
        installCommand = c.install["any"];
      }

      return {
        ...c,
        availableManager,
        installCommand,
        hasDefaults: Object.keys(c.defaults).length > 0,
        hasLinks: Object.keys(c.link).length > 0,
        hasInstall: Object.keys(c.install).length > 0,
        allLinksDone: linksAllCorrect(c),
        isInstalled: c.check ? isCheckInstalled(c.check) : false,
      };
    });
}
