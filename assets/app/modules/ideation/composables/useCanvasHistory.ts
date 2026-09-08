import { computed, ref, shallowRef } from "vue";

export interface CanvasCommand {
  undo: () => Promise<boolean>;
  redo: () => Promise<boolean>;
}

/** Session-local commands, acknowledged before moving between stacks. The shared
 * useUndoRedo dispatches fire-and-forget server events and cannot acknowledge
 * these composed, asynchronous canvas operations. No version history is stored. */
export function useCanvasHistory(
  onError: () => void,
  shouldRetry = () => false,
  prepare?: () => Promise<boolean>,
) {
  const past = shallowRef<CanvasCommand[]>([]);
  const future = shallowRef<CanvasCommand[]>([]);
  const busy = ref(false);
  let generation = 0;
  function push(command: CanvasCommand) {
    past.value = [...past.value.slice(-49), command];
    future.value = [];
  }
  async function run<T>(operation: () => Promise<T>): Promise<T | undefined> {
    if (busy.value) return undefined;
    const started = generation;
    busy.value = true;
    try {
      const value = await operation();
      return started === generation ? value : undefined;
    } catch {
      if (started === generation) onError();
      return undefined;
    } finally {
      if (started === generation) busy.value = false;
    }
  }
  async function step(undo: boolean) {
    const source = undo ? past : future;
    const destination = undo ? future : past;
    const command = source.value.at(-1);
    if (!command || busy.value) return;
    const started = generation;
    const result = await run(async () => {
      if (prepare && (!(await prepare()) || started !== generation)) return undefined;
      return undo ? command.undo() : command.redo();
    });
    if (result === undefined) return;
    if (!result) {
      // A rejected command is no longer applicable. Keep uncertain offline
      // writes retryable, but never let an invalid command block older ones.
      if (!shouldRetry()) source.value = source.value.slice(0, -1);
      onError();
      return;
    }
    source.value = source.value.slice(0, -1);
    destination.value = [...destination.value, command];
  }
  function clear() {
    generation++;
    past.value = [];
    future.value = [];
    busy.value = false;
  }
  return {
    push,
    run,
    clear,
    busy,
    undo: () => step(true),
    redo: () => step(false),
    canUndo: computed(() => past.value.length > 0),
    canRedo: computed(() => future.value.length > 0),
  };
}
