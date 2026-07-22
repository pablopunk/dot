export interface ParsedArgs {
  mode: "interactive" | "direct" | "meta";
  meta: "help" | "version" | "upgrade" | null;
  install: string[];
  uninstall: string[];
  link: string[];
  postinstall: string[];
  postlink: string[];
  exportDefaults: boolean;
  importDefaults: boolean;
  list: boolean;
  dryRun: boolean;
  verbose: boolean;
  interactiveAction: string | null;
}

const VALID_FLAGS = new Set([
  "install", "uninstall", "link", "postinstall", "postlink",
  "defaults-export", "defaults-import", "list", "upgrade",
  "dry-run", "verbose", "help", "version",
]);

const SHORT_FLAGS: Record<string, string> = {
  "i": "install",
  "u": "uninstall",
  "l": "link",
  "e": "defaults-export",
  "I": "defaults-import",
  "v": "verbose",
  "h": "help",
};

const VALUE_FLAGS = new Set([
  "install", "uninstall", "link", "postinstall", "postlink",
]);

const BOOL_ACTION_FLAGS = new Set([
  "defaults-export", "defaults-import", "list", "upgrade",
]);

export function parseArgs(argv: string[]): ParsedArgs {
  const result: ParsedArgs = {
    mode: "interactive",
    meta: null,
    install: [],
    uninstall: [],
    link: [],
    postinstall: [],
    postlink: [],
    exportDefaults: false,
    importDefaults: false,
    list: false,
    dryRun: false,
    verbose: false,
    interactiveAction: null,
  };

  let hasAction = false;
  let i = 1;

  while (i < argv.length) {
    let arg = argv[i];

    if (arg.startsWith("--")) {
      const name = arg.slice(2);

      if (!VALID_FLAGS.has(name)) {
        throw new Error(`Unknown flag: --${name}`);
      }

      if (name === "help") {
        return { ...result, mode: "meta", meta: "help" };
      }
      if (name === "version") {
        return { ...result, mode: "meta", meta: "version" };
      }
      if (name === "upgrade") {
        return { ...result, mode: "meta", meta: "upgrade" };
      }

      if (VALUE_FLAGS.has(name)) {
        i++;
        if (i >= argv.length || argv[i].startsWith("-")) {
          if (name === "install") {
            throw new Error("Flag --install requires a component name");
          }
          result.interactiveAction = name;
          hasAction = true;
          i--;
        } else {
          const key = name as keyof Pick<ParsedArgs, "install" | "uninstall" | "link" | "postinstall" | "postlink">;
          result[key].push(argv[i]);
          hasAction = true;
        }
      } else if (BOOL_ACTION_FLAGS.has(name)) {
        if (name === "list") result.list = true;
        if (name === "defaults-export") result.exportDefaults = true;
        if (name === "defaults-import") result.importDefaults = true;
        hasAction = true;
      } else if (name === "dry-run") {
        result.dryRun = true;
      } else if (name === "verbose") {
        result.verbose = true;
      }
    } else if (arg.startsWith("-") && arg.length > 1) {
      const flags = arg.slice(1);

      for (let j = 0; j < flags.length; j++) {
        const ch = flags[j];
        const resolved = SHORT_FLAGS[ch];
        if (!resolved) {
          throw new Error(`Unknown flag: -${ch}`);
        }

        if (resolved === "help") {
          return { ...result, mode: "meta", meta: "help" };
        }

        if (VALUE_FLAGS.has(resolved)) {
          if (j < flags.length - 1) {
            throw new Error(`Flag -${ch} requires a value and cannot be combined`);
          }
          i++;
          if (i >= argv.length || argv[i].startsWith("-")) {
            if (resolved === "install") {
              throw new Error("Flag -i requires a component name");
            }
            result.interactiveAction = resolved;
            hasAction = true;
            i--;
          } else {
            const key = resolved as keyof Pick<ParsedArgs, "install" | "uninstall" | "link" | "postinstall" | "postlink">;
            result[key].push(argv[i]);
            hasAction = true;
          }
        } else if (BOOL_ACTION_FLAGS.has(resolved)) {
          if (resolved === "defaults-export") result.exportDefaults = true;
          if (resolved === "defaults-import") result.importDefaults = true;
          hasAction = true;
        } else if (resolved === "verbose") {
          result.verbose = true;
        }
      }
    }

    i++;
  }

  if (!hasAction) {
    result.mode = "interactive";
  } else if (result.interactiveAction && 
    result.install.length === 0 && result.uninstall.length === 0 &&
    result.link.length === 0 && result.postinstall.length === 0 &&
    result.postlink.length === 0 && !result.exportDefaults &&
    !result.importDefaults && !result.list) {
    result.mode = "interactive";
  } else {
    result.mode = "direct";
  }

  return result;
}
