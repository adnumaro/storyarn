import { beforeEach, describe, expect, it } from "vitest";
import {
  GLOBAL_SURFACE,
  paletteGroups,
  primarySurface,
  registerPaletteCommands,
  resetPaletteRegistry,
  type PaletteCommand,
} from "../../../shared/command-palette/registry";

function command(
  id: string,
  groupKey = "palette.groups.navigation",
  labelKey = `label.${id}`,
): PaletteCommand {
  return { id, labelKey, groupKey, run: () => undefined };
}

describe("command palette registry", () => {
  beforeEach(() => {
    resetPaletteRegistry();
  });

  it("starts empty with the global surface", () => {
    expect(paletteGroups.value).toEqual([]);
    expect(primarySurface.value).toBe(GLOBAL_SURFACE);
  });

  it("groups commands by group key preserving registration order", () => {
    registerPaletteCommands("flows", [
      command("flows.a", "palette.groups.view"),
      command("flows.b", "palette.groups.navigation"),
    ]);
    registerPaletteCommands(GLOBAL_SURFACE, [command("global.c", "palette.groups.view")]);

    expect(paletteGroups.value.map((group) => group.key)).toEqual([
      "palette.groups.view",
      "palette.groups.navigation",
    ]);
    expect(paletteGroups.value[0]!.commands.map((c) => c.id)).toEqual(["flows.a", "global.c"]);
  });

  it("scopes commands to live registrations — unregister removes them", () => {
    const unregister = registerPaletteCommands("sheets", [command("sheets.a")]);
    registerPaletteCommands(GLOBAL_SURFACE, [command("global.b")]);

    expect(paletteGroups.value[0]!.commands).toHaveLength(2);

    unregister();

    expect(paletteGroups.value[0]!.commands.map((c) => c.id)).toEqual(["global.b"]);
  });

  it("keeps the first command when two registrations share an id", () => {
    registerPaletteCommands("flows", [
      command("dup.id", "palette.groups.navigation", "label.first"),
    ]);
    registerPaletteCommands("sheets", [
      command("dup.id", "palette.groups.navigation", "label.second"),
    ]);

    const rendered = paletteGroups.value[0]!.commands;
    expect(rendered).toHaveLength(1);
    expect(rendered[0]!.labelKey).toBe("label.first");
  });

  it("primarySurface is the last non-global registration and falls back after unregister", () => {
    registerPaletteCommands(GLOBAL_SURFACE, [command("global.a")]);
    const unregisterFlows = registerPaletteCommands("flows", [command("flows.b")]);

    expect(primarySurface.value).toBe("flows");

    unregisterFlows();

    expect(primarySurface.value).toBe(GLOBAL_SURFACE);
  });
});
