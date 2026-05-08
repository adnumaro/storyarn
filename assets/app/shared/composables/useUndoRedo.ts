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

import { type ComputedRef, type Ref, computed, ref } from "vue";
import { useLive } from "./useLive";

export interface UndoRedoAction {
  type: string;
  [key: string]: unknown;
}

export interface UseUndoRedoOptions {
  maxStack?: number;
  undoEvent?: string;
  redoEvent?: string;
}

export interface UseUndoRedoReturn {
  push: (action: UndoRedoAction) => void;
  undo: () => void;
  redo: () => void;
  canUndo: ComputedRef<boolean>;
  canRedo: ComputedRef<boolean>;
  clear: () => void;
}

export function useUndoRedo(options: UseUndoRedoOptions = {}): UseUndoRedoReturn {
  const { maxStack = 50, undoEvent = "undo", redoEvent = "redo" } = options;

  const live = useLive();
  const undoStack: Ref<UndoRedoAction[]> = ref([]);
  const redoStack: Ref<UndoRedoAction[]> = ref([]);

  const canUndo = computed(() => undoStack.value.length > 0);
  const canRedo = computed(() => redoStack.value.length > 0);

  function push(action: UndoRedoAction): void {
    undoStack.value.push(action);
    if (undoStack.value.length > maxStack) {
      undoStack.value.shift();
    }
    // Clear redo stack on new action
    redoStack.value = [];
  }

  function undo(): void {
    const action = undoStack.value.pop();
    if (!action) return;

    redoStack.value.push(action);
    live.pushEvent(undoEvent, action);
  }

  function redo(): void {
    const action = redoStack.value.pop();
    if (!action) return;

    undoStack.value.push(action);
    live.pushEvent(redoEvent, action);
  }

  function clear(): void {
    undoStack.value = [];
    redoStack.value = [];
  }

  return { push, undo, redo, canUndo, canRedo, clear };
}
