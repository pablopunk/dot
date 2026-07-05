import { describe, test, expect } from "bun:test";
import { buildChecklist, CheckboxItem } from "../src/interactive";
import { ResolvedComponent } from "../src/config";

function makeComponent(overrides: Partial<ResolvedComponent> = {}): ResolvedComponent {
  return {
    name: "zsh",
    install: { brew: "brew install zsh" },
    uninstall: {},
    link: {},
    defaults: {},
    availableManager: "brew",
    installCommand: "brew install zsh",
    hasDefaults: false,
    hasLinks: false,
    hasInstall: true,
    allLinksDone: false,
    isInstalled: false,
    ...overrides,
  };
}

describe("buildChecklist", () => {
  test("creates items from components", () => {
    const comps = [makeComponent({ name: "zsh" }), makeComponent({ name: "git" })];
    const items = buildChecklist(comps);
    expect(items).toHaveLength(2);
    // Both have allLinksDone=false, sorted alphabetically: git before zsh
    expect(items[0].name).toBe("git");
    expect(items[1].name).toBe("zsh");
  });

  test("all items start unselected", () => {
    const comps = [makeComponent(), makeComponent({ name: "git" })];
    const items = buildChecklist(comps);
    for (const item of items) {
      expect(item.selected).toBe(false);
    }
  });

  test("marks unavailable items", () => {
    const comps = [makeComponent({ availableManager: null, installCommand: null })];
    const items = buildChecklist(comps);
    expect(items[0].unavailable).toBe(true);
  });

  test("available items are not unavailable", () => {
    const comps = [makeComponent({ availableManager: "brew" })];
    const items = buildChecklist(comps);
    expect(items[0].unavailable).toBe(false);
  });
});
