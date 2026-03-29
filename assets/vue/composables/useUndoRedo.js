/**
 * Client-side undo/redo stack.
 *
 * Actions are stored locally. Undo/redo dispatch events to the server
 * to revert/reapply changes.
 *
 * Usage:
 *   const { push, undo, redo, canUndo, canRedo } = useUndoRedo()
 *   push({ type: "update_value", blockId: 1, prev: "old", next: "new" })
 *   undo() // dispatches the reverse action
 */

import { computed, ref } from "vue";
import { useLive } from "./useLive";

export function useUndoRedo(options = {}) {
	const { maxStack = 50, undoEvent = "undo", redoEvent = "redo" } = options;

	const live = useLive();
	const undoStack = ref([]);
	const redoStack = ref([]);

	const canUndo = computed(() => undoStack.value.length > 0);
	const canRedo = computed(() => redoStack.value.length > 0);

	function push(action) {
		undoStack.value.push(action);
		if (undoStack.value.length > maxStack) {
			undoStack.value.shift();
		}
		// Clear redo stack on new action
		redoStack.value = [];
	}

	function undo() {
		const action = undoStack.value.pop();
		if (!action) return;

		redoStack.value.push(action);
		live.pushEvent(undoEvent, action);
	}

	function redo() {
		const action = redoStack.value.pop();
		if (!action) return;

		undoStack.value.push(action);
		live.pushEvent(redoEvent, action);
	}

	function clear() {
		undoStack.value = [];
		redoStack.value = [];
	}

	return { push, undo, redo, canUndo, canRedo, clear };
}
