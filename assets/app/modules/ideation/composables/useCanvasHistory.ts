import { computed, ref, shallowRef } from "vue";

export interface CanvasTarget {
  id: number;
  restoring?: { roundId: number | null };
}

export interface CanvasCommand {
  targets: (undo: boolean) => CanvasTarget[];
  undo: () => Promise<boolean>;
  redo: () => Promise<boolean>;
}

/** Session-local commands, acknowledged before moving between stacks. Like the
 * Flow editor's history queue, keyboard intentions execute in order after writes
 * settle. Text editors keep their own native history. No version history is stored. */
export function useCanvasHistory(
  onError: () => void,
  shouldRetry = () => false,
  prepare?: (targets: CanvasTarget[]) => Promise<boolean>,
) {
  const past = shallowRef<CanvasCommand[]>([]);
  const future = shallowRef<CanvasCommand[]>([]);
  const busy = ref(false);
  let generation = 0;
  let intentions = 0;
  let additions = 0;
  let pending = 0;
  let tail: Promise<void> | undefined;
  function push(command: CanvasCommand) {
    additions++;
    past.value = [...past.value.slice(-49), command];
    future.value = [];
  }
  function enqueue<T>(operation: () => Promise<T>): Promise<T | undefined> {
    const started = generation;
    pending++;
    busy.value = true;
    const execute = async () => {
      if (started !== generation) return undefined;
      try {
        const value = await operation();
        return started === generation ? value : undefined;
      } catch {
        if (started === generation) {
          intentions++;
          onError();
        }
        return undefined;
      }
    };
    const operationResult = tail ? tail.then(execute) : execute();
    const settled = operationResult.finally(() => {
      if (started !== generation) return;
      pending--;
      busy.value = pending > 0;
      if (!pending) tail = undefined;
    });
    tail = settled.then(() => undefined);
    return settled;
  }
  function run<T>(operation: () => Promise<T>): Promise<T | undefined> {
    return busy.value ? Promise.resolve(undefined) : enqueue(operation);
  }
  function complete(command: CanvasCommand, undo: boolean, added: number, succeeded: boolean) {
    const source = undo ? past : future;
    if (!succeeded) {
      // Stop queued intentions after an uncertain write instead of replaying
      // it repeatedly offline. Definitive rejections let older actions proceed.
      if (shouldRetry()) intentions++;
      else source.value = source.value.filter((entry) => entry !== command);
      onError();
      return;
    }
    // A write can record a new action while this acknowledgement is pending.
    // Remove the executed command itself, never whichever action is now last.
    source.value = source.value.filter((entry) => entry !== command);
    if (undo) {
      if (added === additions) future.value = [...future.value, command];
    } else {
      const index = Math.max(0, past.value.length - (additions - added));
      past.value = [...past.value.slice(0, index), command, ...past.value.slice(index)].slice(-50);
    }
  }
  async function prepareCommand(command: CanvasCommand, undo: boolean, started: number) {
    const ready = await prepare!(command.targets(undo));
    if (started !== generation) return false;
    if (!ready && shouldRetry()) intentions++;
    return ready;
  }
  function step(undo: boolean) {
    const intention = intentions;
    return enqueue(async () => {
      if (intention !== intentions) return;
      const source = undo ? past : future;
      const command = source.value.at(-1);
      if (!command) return;
      const started = generation;
      const added = additions;
      if (prepare && !(await prepareCommand(command, undo, started))) return;
      const result = await (undo ? command.undo() : command.redo());
      if (started !== generation) return;
      complete(command, undo, added, result);
    });
  }
  function clear() {
    generation++;
    intentions++;
    pending = 0;
    tail = undefined;
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
