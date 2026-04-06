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
}

export function useKeyboard(bindings: KeyboardBindings, options: UseKeyboardOptions = {}): void {
  const { target = document, prevent = true } = options;

  function handler(e: Event): void {
    const keyEvent = e as KeyboardEvent;
    // Don't intercept when typing in inputs
    const targetEl = keyEvent.target as HTMLElement | null;
    const tag = targetEl?.tagName;
    if (tag === "INPUT" || tag === "TEXTAREA" || targetEl?.isContentEditable) return;

    const parts: string[] = [];
    if (keyEvent.ctrlKey || keyEvent.metaKey) parts.push("ctrl");
    if (keyEvent.shiftKey) parts.push("shift");
    if (keyEvent.altKey) parts.push("alt");
    parts.push(keyEvent.key.toLowerCase());

    const combo = parts.join("+");
    const fn = bindings[combo];

    if (fn) {
      if (prevent) {
        keyEvent.preventDefault();
        keyEvent.stopPropagation();
      }
      fn(keyEvent);
    }
  }

  onMounted(() => {
    target.addEventListener("keydown", handler);
  });

  onBeforeUnmount(() => {
    target.removeEventListener("keydown", handler);
  });
}
