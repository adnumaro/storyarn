import type { Component } from "vue";
import { computed, reactive } from "vue";

interface PaletteCommandBase {
  /** Stable identifier, e.g. "flows.toggle-debug-panel". Also the analytics command_id. */
  id: string;
  /** i18n key for the group heading the command renders under. */
  groupKey: string;
  icon?: Component;
  /** Display-only shortcut hint, e.g. "⇧⌘L". Never a binding. */
  shortcut?: string;
  run: () => void;
}

/**
 * A command labels itself with EITHER an i18n key or a raw data-driven string
 * (workspace names, etc.). The union makes a labelless command a compile
 * error — there is deliberately no render-time fallback.
 */
export type PaletteCommand =
  | (PaletteCommandBase & { labelKey: string; label?: never })
  | (PaletteCommandBase & { label: string; labelKey?: never });

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
