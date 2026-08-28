import { computed, reactive } from "vue";
import type { AIPaletteCommand } from "./aiCommands";
import { isAIPaletteCommand } from "./aiCommands";
import type { PaletteCommandBase } from "./commandTypes";

export type { PaletteCommandBase } from "./commandTypes";

type LocalPaletteCommandExecution =
  | { run: () => void | Promise<void>; href?: never }
  | { href: string; run?: never };

type PaletteCommandLabel =
  | { labelKey: string; label?: never }
  | { label: string; labelKey?: never };

/**
 * A command labels itself with EITHER an i18n key or a raw data-driven string
 * (workspace names, etc.). The union makes a labelless command a compile
 * error — there is deliberately no render-time fallback.
 */
export type LocalPaletteCommand = PaletteCommandBase &
  LocalPaletteCommandExecution &
  PaletteCommandLabel;

export type PaletteCommand = LocalPaletteCommand | (AIPaletteCommand & PaletteCommandLabel);

export interface PaletteRegistration {
  surface: string;
  commands: PaletteCommand[];
}

export const GLOBAL_SURFACE = "global";

const entries = reactive(new Map<symbol, PaletteRegistration>());

/**
 * Registers commands for a surface. Call from the owning component's setup;
 * the returned function unregisters (call it in onUnmounted). A surface is
 * "active" exactly while at least one of its registrations is alive, which is
 * what scopes the palette to the current page.
 */
export function registerPaletteCommands(surface: string, commands: PaletteCommand[]): () => void {
  const key = Symbol(surface);
  entries.set(key, { surface, commands });
  return () => {
    entries.delete(key);
  };
}

export interface PaletteGroup {
  key: string;
  commands: PaletteCommand[];
}

/** Commands grouped by heading, registration order preserved, first id wins on duplicates. */
export const paletteGroups = computed<PaletteGroup[]>(() => {
  const groups = new Map<string, PaletteCommand[]>();
  const seen = new Set<string>();

  for (const { commands } of entries.values()) {
    for (const command of commands) {
      if (seen.has(command.id)) continue;
      if (isAIPaletteCommand(command)) {
        if (command.availability.state === "hidden") continue;
      } else if (command.visible?.() === false) {
        continue;
      }
      seen.add(command.id);

      const list = groups.get(command.groupKey);
      if (list) {
        list.push(command);
      } else {
        groups.set(command.groupKey, [command]);
      }
    }
  }

  return Array.from(groups, ([key, commands]) => ({ key, commands }));
});

/** The most recently registered non-global surface — the analytics `surface` value. */
export const primarySurface = computed<string>(() => {
  let current = GLOBAL_SURFACE;
  for (const { surface } of entries.values()) {
    if (surface !== GLOBAL_SURFACE) current = surface;
  }
  return current;
});

/** Test-only: drops every registration so specs start from a clean slate. */
export function resetPaletteRegistry(): void {
  entries.clear();
}
