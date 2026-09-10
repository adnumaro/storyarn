import { shallowRef } from "vue";
import type {
  BoardContext,
  ConnectionChange,
  ConnectionAcknowledgement,
  ConnectionResult,
  ConnectionVersion,
  CreatedIdea,
  Request,
} from "../types";
import type { useCanvasNotes } from "./useCanvasNotes";
import type { CanvasCommand, useCanvasHistory } from "./useCanvasHistory";

type VersionToken = ConnectionVersion;
interface Attempt {
  request_key: string;
  changes: ConnectionChange[];
  versions: ConnectionVersion[];
  context: BoardContext;
  retryable?: boolean;
}
interface PendingConnection {
  attempt: Attempt;
  before: Map<number, VersionToken>;
  recordHistory: boolean;
}
interface Options {
  notes: ReturnType<typeof useCanvasNotes>;
  request: Request;
  context: () => BoardContext;
  history: ReturnType<typeof useCanvasHistory>;
  allowed: () => boolean;
  notify: (code: string | null) => void;
}

/** Only acknowledged local undo/redo advances a shared state token. A remote
 * change never rebases an old command, even if it recreates the same links. */
export function useCanvasConnections(options: Options) {
  const { notes, request, context, history, allowed, notify } = options;
  const current = new Map<number, VersionToken>();
  const pending = shallowRef<PendingConnection | null>(null);
  let generation = 0;

  function token(id: number, version: number): VersionToken {
    let value = current.get(id);
    if (!value || value.version !== version) {
      value = { id, version };
      current.set(id, value);
    }
    return value;
  }
  function atCurrentBoard(at: BoardContext) {
    const now = context();
    return at.epoch === now.epoch && at.session_id === now.session_id;
  }
  function attempt(changes: ConnectionChange[], versions: ConnectionVersion[]): Attempt {
    return {
      request_key: crypto.randomUUID(),
      changes: changes.map((change) => ({ ...change })),
      versions: versions.map((version) => ({ ...version })),
      context: context(),
    };
  }
  async function send(write: Attempt): Promise<ConnectionResult | null> {
    write.retryable = false;
    if (!allowed() || !atCurrentBoard(write.context)) return null;
    const started = generation;
    const reply = await request<ConnectionResult>(
      "update_idea_connections",
      { request_key: write.request_key, changes: write.changes, versions: write.versions },
      write.context,
    );
    if (started !== generation || !allowed() || !atCurrentBoard(write.context)) return null;
    if (reply.status !== "ok") {
      write.retryable = reply.status === "error" && ["offline", "unavailable"].includes(reply.code);
      notify(reply.status === "error" ? reply.code : "stale_connections");
      return null;
    }
    notes.acknowledgeConnections(reply.value);
    notify(null);
    return reply.value;
  }
  function command(
    changes: ConnectionAcknowledgement[],
    before: Map<number, VersionToken>,
    after: Map<number, VersionToken>,
  ): CanvasCommand {
    let uncertain: Attempt | null = null;
    async function apply(undo: boolean) {
      const expected = undo ? after : before;
      const destination = undo ? before : after;
      const mutation = changes.map((change): ConnectionChange => {
        const connected = undo
          ? (change.previous_connected ?? !change.connected)
          : change.connected;
        const direction = undo ? change.previous_direction : change.direction;
        return {
          source_id: change.source_id,
          target_id: change.target_id,
          connected,
          ...(connected && direction ? { direction } : {}),
        };
      });
      uncertain ??= attempt(mutation, [...expected.values()]);
      const result = await send(uncertain);
      if (!result) return false;
      uncertain = null;
      for (const version of result.versions) {
        const restored = destination.get(version.id)!;
        restored.version = version.version;
        current.set(version.id, restored);
      }
      return true;
    }
    return {
      targets: () =>
        [...new Set(changes.flatMap((change) => [change.source_id, change.target_id]))].map(
          (id) => ({ id }),
        ),
      undo: () => apply(true),
      redo: () => apply(false),
    };
  }
  async function submit(write: PendingConnection) {
    const result = await send(write.attempt);
    if (!result) {
      if (!write.attempt.retryable && pending.value === write) pending.value = null;
      return false;
    }
    if (pending.value === write) pending.value = null;
    if (!result.changes.length) return true;
    const sources = new Set(result.changes.map((change) => change.source_id));
    const after = new Map<number, VersionToken>();
    const before = new Map([...write.before].filter(([id]) => sources.has(id)));
    for (const version of result.versions) {
      if (!sources.has(version.id)) continue;
      const next = { ...version };
      current.set(version.id, next);
      after.set(version.id, next);
    }
    if (write.recordHistory) history.push(command(result.changes, before, after));
    return true;
  }
  async function change(changes: ConnectionChange[], { recordHistory = true } = {}) {
    if (!allowed() || history.busy.value || !changes.length) return;
    if (pending.value) {
      notify("connections_pending");
      return;
    }
    if (changes.length > 100) {
      notify("selection_too_large");
      return;
    }
    const started = generation;
    await history.run(async () => {
      const ids = [...new Set(changes.flatMap((change) => [change.source_id, change.target_id]))];
      for (const id of ids) {
        if (!(await notes.settle(id))) {
          notify("save_before_connect");
          return;
        }
      }
      if (started !== generation || !allowed()) return;
      const resolved = changes.map((change) => ({
        ...change,
        source_id: notes.resolveId(change.source_id),
        target_id: notes.resolveId(change.target_id),
      }));
      if (resolved.some((change) => change.source_id <= 0 || change.target_id <= 0)) {
        notify("save_before_connect");
        return;
      }
      const versions = [...new Set(resolved.map((change) => change.source_id))].map((id) => ({
        id,
        version: notes.find(id)?.canvas?.links_version ?? 0,
      }));
      const write: PendingConnection = {
        attempt: attempt(resolved, versions),
        before: new Map(versions.map(({ id, version }) => [id, token(id, version)])),
        recordHistory,
      };
      pending.value = write;
      await submit(write);
    });
  }
  async function retry() {
    const write = pending.value;
    if (!write || !allowed() || history.busy.value) return;
    await history.run(() => submit(write));
  }
  function created(idea: CreatedIdea) {
    for (const source of idea.connected_from ?? []) {
      const previous = current.get(source.id);
      // A delayed/replayed creation cannot replace the token shared by newer
      // local commands, otherwise their subsequent undo chain would split.
      if (previous && previous.version >= source.version) continue;
      // Creation only adds the fresh destination. Advance our prior token only
      // when the server confirms no intervening connection write occurred.
      if (previous?.version === source.before_version) {
        previous.version = source.version;
      } else token(source.id, source.version);
    }
  }
  function reset() {
    generation++;
    pending.value = null;
    current.clear();
  }
  return { change, retry, reset, created, pending };
}
