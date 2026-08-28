import type { Component } from "vue";

export interface PaletteCommandBase {
  /** Stable identifier, e.g. "flows.toggle-debug-panel". Also the analytics command_id. */
  id: string;
  /** i18n key for the group heading the command renders under. */
  groupKey: string;
  icon?: Component;
  /** Display-only shortcut hint, e.g. "⇧⌘L". Never a binding. */
  shortcut?: string;
  /** Dynamic availability is evaluated whenever the reactive registry recomputes. */
  visible?: () => boolean;
  enabled?: () => boolean;
  disabledReasonKey?: string;
}
