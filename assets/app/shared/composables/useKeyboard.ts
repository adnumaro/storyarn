/**
 * Keyboard shortcut manager.
 *
 * Registers keyboard bindings that are cleaned up on component unmount.
 *
 * Usage:
 *   useKeyboard({
 *     "ctrl+z": () => undo(),
 *     "ctrl+shift+z": () => redo(),
 *     "delete": () => deleteSelected(),
 *     "escape": () => deselect(),
 *   })
 */

import { onBeforeUnmount, onMounted } from "vue";

export type KeyboardBindings = Record<string, (e: KeyboardEvent) => void>;

export interface UseKeyboardOptions {
  target?: EventTarget;
  prevent?: boolean;
  /** Opt selected bindings into editable targets without weakening every shortcut. */
  allowInEditable?: (combo: string, event: KeyboardEvent) => boolean;
}

export function useKeyboard(bindings: KeyboardBindings, options: UseKeyboardOptions = {}): void {
  const { target = document, prevent = true, allowInEditable } = options;

  function isEditableTarget(el: HTMLElement | null): boolean {
    if (!el) return false;
    const tag = el.tagName;
    return tag === "INPUT" || tag === "TEXTAREA" || !!el.isContentEditable;
  }

  function buildCombo(e: KeyboardEvent): string {
    const parts: string[] = [];
    if (e.ctrlKey || e.metaKey) parts.push("ctrl");
    if (e.shiftKey) parts.push("shift");
    if (e.altKey) parts.push("alt");
    parts.push(e.key.toLowerCase());
    return parts.join("+");
  }

  function handler(e: Event): void {
    const keyEvent = e as KeyboardEvent;
    const combo = buildCombo(keyEvent);
    if (
      isEditableTarget(keyEvent.target as HTMLElement | null) &&
      !allowInEditable?.(combo, keyEvent)
    ) {
      return;
    }

    const fn = bindings[combo];
    if (!fn) return;

    if (prevent) {
      keyEvent.preventDefault();
      keyEvent.stopPropagation();
    }
    fn(keyEvent);
  }

  onMounted(() => {
    target.addEventListener("keydown", handler);
  });

  onBeforeUnmount(() => {
    target.removeEventListener("keydown", handler);
  });
}
