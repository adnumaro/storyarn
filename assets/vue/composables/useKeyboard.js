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

export function useKeyboard(bindings, options = {}) {
	const { target = document, prevent = true } = options;

	function handler(e) {
		// Don't intercept when typing in inputs
		const tag = e.target?.tagName;
		if (tag === "INPUT" || tag === "TEXTAREA" || e.target?.isContentEditable)
			return;

		const parts = [];
		if (e.ctrlKey || e.metaKey) parts.push("ctrl");
		if (e.shiftKey) parts.push("shift");
		if (e.altKey) parts.push("alt");
		parts.push(e.key.toLowerCase());

		const combo = parts.join("+");
		const fn = bindings[combo];

		if (fn) {
			if (prevent) {
				e.preventDefault();
				e.stopPropagation();
			}
			fn(e);
		}
	}

	onMounted(() => {
		target.addEventListener("keydown", handler);
	});

	onBeforeUnmount(() => {
		target.removeEventListener("keydown", handler);
	});
}
