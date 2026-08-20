import prompts from "prompts";
import { color } from "./ui";
import { ResolvedComponent } from "./config";

export interface CheckboxItem {
  name: string;
  selected: boolean;
  unavailable: boolean;
  manager: string | null;
  installCommand: string | null;
  hasDefaults: boolean;
  hasLinks: boolean;
  hasInstall: boolean;
  allLinksDone: boolean;
  isInstalled: boolean;
  isDone: boolean;
}

export function buildChecklist(components: ResolvedComponent[]): CheckboxItem[] {
  const items = components.map((c) => ({
    name: c.name,
    selected: false,
    unavailable: !c.availableManager && !c.hasDefaults && !c.hasLinks,
    manager: c.availableManager,
    installCommand: c.installCommand,
    hasDefaults: c.hasDefaults,
    hasLinks: c.hasLinks,
    hasInstall: c.hasInstall,
    allLinksDone: c.allLinksDone,
    isInstalled: c.isInstalled,
    isDone: Boolean(c.check || c.hasLinks)
      && (!c.check || c.isInstalled)
      && (!c.hasLinks || c.allLinksDone),
  }));

  items.sort((a, b) => {
    if (a.isDone !== b.isDone) return a.isDone ? 1 : -1;
    return a.name.localeCompare(b.name);
  });

  return items;
}

export async function runInteractive(
  components: ResolvedComponent[],
  stdin: NodeJS.ReadStream = process.stdin
): Promise<CheckboxItem[]> {
  const items = buildChecklist(components);

  const response = await prompts({
    type: "autocompleteMultiselect",
    name: "components",
    message: "Select components to set up",
    choices: items.map((item) => {
      const mgr = item.manager || (item.hasDefaults ? "defaults" : item.hasLinks ? "link" : "—");
      const cmd = item.installCommand
        ? item.installCommand.length > 45
          ? item.installCommand.slice(0, 42) + "..."
          : item.installCommand
        : "";
      let marker = "";
      if (item.unavailable) marker = " ⚠";
      else if (item.isDone) marker = ` ${color("✓", "green")}`;
      return {
        title: `${item.name}${marker}`,
        value: item.name,
        description: item.unavailable ? "no install method" : `${mgr}  ${cmd}`,
        selected: false,
        disabled: item.unavailable,
      };
    }),
    hint: "✓=done  ⚠=no install method  (type to filter, space to select, enter to confirm)",
    instructions: false,
    stdin,
    optionsPerPage: process.stdout.rows ? process.stdout.rows - 10 : 30,
    suggest: (input: string, choices: any[]) =>
      Promise.resolve(
        choices
          .filter((c) => c.title.includes(input) || c.title.toLowerCase().includes(input.toLowerCase()))
          .slice(0, 20)
      ),
  });

  if (!response.components || response.components.length === 0) {
    return [];
  }

  return items.filter((i) => response.components.includes(i.name));
}
