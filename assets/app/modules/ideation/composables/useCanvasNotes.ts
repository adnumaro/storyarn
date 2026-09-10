import { computed, onUnmounted, reactive, watch } from "vue";
import { useIdeaDrafts, type Draft } from "./useIdeaDrafts";
import type {
  Board,
  BoardContext,
  CanvasPlacement,
  Idea,
  IdeaContent,
  Request,
  Reply,
  NoteConnection,
  CreatedIdea,
  ConnectionResult,
} from "../types";
import type { Point } from "./useCanvasViewport";
interface NewNote {
  idea: Idea;
  key: string;
  context: BoardContext;
  version: number;
  pending: boolean;
  error: string | null;
  attempt?: Idea;
  connection?: NoteConnection;
}
interface PlacementAttempt {
  canvas: CanvasPlacement;
  key: string;
  version: number;
}
export interface RemovedNote {
  id: number;
  revision: number;
  deleted_at: string | null;
  idea: Idea;
  connection?: NoteConnection;
}
function connectionVersion(canvas?: CanvasPlacement): number {
  return canvas?.links_version ?? 0;
}
export function useCanvasNotes(
  board: () => Board,
  request: Request,
  context: () => BoardContext,
  replaceSelection: (from: number, to: number) => void,
  onCreated: (idea: CreatedIdea) => void = () => {},
) {
  const activeRoundId = computed(() => board().active_round?.id ?? null);
  const canWrite = () => board().can_edit && board().session?.status === "open";
  const drafts = useIdeaDrafts(request, context, canWrite);
  const newNotes = reactive(new Map<number, NewNote>());
  const created = reactive(new Map<number, Idea>());
  const placements = reactive(new Map<number, CanvasPlacement>());
  const connections = reactive(new Map<number, CanvasPlacement>());
  const removed = reactive(new Set<number>());
  const deleting = reactive(new Set<number>());
  const deleteRequests = reactive(new Set<number>());
  const errors = reactive(new Map<number, string>());
  const timers = new Map<number, ReturnType<typeof setTimeout>>();
  const moving = reactive(new Set<number>());
  const attempts = new Map<number, PlacementAttempt>();
  const keys = new Map<number, string>();
  const aliases = new Map<number, number>();
  const deletions = new Map<number, RemovedNote>();
  let nextId = -1,
    generation = 0;
  const notes = computed(() => {
    const merged = new Map(board().ideas.map((idea) => [idea.id, idea]));
    for (const [id, idea] of created) if (!merged.has(id)) merged.set(id, idea);
    for (const [id, draft] of drafts.drafts)
      if (merged.has(id))
        merged.set(id, { ...draft.idea, canvas: merged.get(id)?.canvas, ...draft.content });
    for (const [id, entry] of newNotes) merged.set(id, entry.idea);
    return [...merged.values()]
      .filter((idea) => !removed.has(idea.id) && !idea.deleted_at)
      .map((idea) => ({
        ...idea,
        canvas: projectedCanvas(idea),
      }));
  });
  function projectedCanvas(idea: Idea): CanvasPlacement {
    const placement = placements.get(idea.id);
    const acknowledged = connections.get(idea.id);
    // Placement and links have independent clocks. A delayed move reply cannot
    // overwrite a newer connection acknowledgement or board projection.
    let links = idea.canvas;
    for (const candidate of [placement, acknowledged])
      if (candidate && connectionVersion(candidate) > connectionVersion(links)) links = candidate;
    const pending = [...newNotes.values()]
      .filter((entry) => entry.connection?.source_ids.includes(idea.id))
      .map((entry) => entry.idea.id);
    return {
      ...idea.canvas,
      ...placement,
      links: [...new Set([...(links?.links ?? []), ...pending])],
      links_version: connectionVersion(links),
    };
  }
  function acknowledgeConnections(result: ConnectionResult) {
    for (const version of result.versions) {
      const note = find(version.id);
      if (!note || (note.canvas?.links_version ?? 0) > version.version) continue;
      const links = new Set((note.canvas?.links ?? []).filter((id) => id > 0));
      for (const change of result.changes.filter((change) => change.source_id === version.id))
        if (change.connected) links.add(change.target_id);
        else links.delete(change.target_id);
      connections.set(version.id, { links: [...links], links_version: version.version });
    }
  }
  function resolveId(id: number): number {
    while (aliases.has(id)) id = aliases.get(id)!;
    return id;
  }
  function key(id: number): string {
    return keys.get(resolveId(id)) ?? String(id);
  }
  function find(id: number): Idea | undefined {
    return notes.value.find((note) => note.id === resolveId(id));
  }
  function add(
    point: CanvasPlacement & Point,
    color = "yellow",
    seed?: Partial<IdeaContent>,
    roundId: number | null = activeRoundId.value,
    connection?: NoteConnection,
  ): number {
    const id = nextId--;
    const initial: Partial<IdeaContent> = seed ?? {
      title: null,
      body: "<p></p>",
    };
    const idea: Idea = {
      id,
      round_id: roundId,
      late_contribution: false,
      session_id: board().session!.id,
      author_id: board().current_user_id,
      author_kind: "human",
      title: initial.title ?? null,
      body: initial.body ?? "<p></p>",
      preview: "",
      state: initial.state ?? "active",
      visibility: board().session?.configuration.private_mode ? "private" : "shared",
      revision: 0,
      published_revision: null,
      source_idea_id: null,
      source_revision: null,
      inserted_at: new Date().toISOString(),
      canvas: { width: 280, color, ...point },
    };
    keys.set(id, crypto.randomUUID());
    newNotes.set(id, {
      idea,
      key: crypto.randomUUID(),
      context: context(),
      version: board().session!.configuration_version,
      pending: false,
      error: null,
      connection: connection ? { source_ids: [...connection.source_ids] } : undefined,
    });
    return id;
  }
  function open(idea: Idea) {
    if (idea.id > 0 && idea.author_id === board().current_user_id) drafts.open(idea);
  }
  function change(id: number, body: string) {
    const entry = newNotes.get(id);
    if (entry) {
      entry.idea.body = body;
      clearTimeout(timers.get(id));
      timers.set(
        id,
        setTimeout(() => void saveNew(id), 800),
      );
    } else drafts.change(id, { body });
  }
  async function saveNew(id: number) {
    if (!canWrite()) return;
    const entry = newNotes.get(id);
    if (!entry || entry.pending || !entry.idea.body.replace(/<[^>]*>/g, "").trim()) return;
    // Preserve the original idempotent create request across uncertain outcomes.
    entry.pending = true;
    const started = generation;
    const snapshot = entry.attempt ?? { ...entry.idea, canvas: { ...entry.idea.canvas } };
    entry.attempt = snapshot;
    const reply = await request<CreatedIdea>(
      "create_idea",
      {
        request_key: entry.key,
        round_id: snapshot.round_id,
        title: snapshot.title,
        body: snapshot.body,
        configuration_version: entry.version,
        canvas: snapshot.canvas,
        ...(entry.connection ? { connection: entry.connection } : {}),
      },
      entry.context,
    );
    if (started !== generation) return;
    entry.pending = false;
    acceptCreation(id, entry, snapshot, reply);
  }
  function acceptCreation(id: number, entry: NewNote, snapshot: Idea, reply: Reply<CreatedIdea>) {
    if (reply.status === "ok") {
      acceptCreated(id, entry, snapshot, reply.value);
    } else {
      entry.error = reply.status === "error" ? reply.code : "unavailable";
      errors.set(id, entry.error);
      if (!["offline", "unavailable"].includes(entry.error)) entry.attempt = undefined;
    }
  }
  function acceptCreated(id: number, entry: NewNote, snapshot: Idea, reply: CreatedIdea) {
    const { connected_from, ...idea } = reply;
    keys.set(idea.id, key(id));
    aliases.set(id, idea.id);
    created.set(idea.id, idea);
    drafts.open(idea);
    if (entry.idea.body !== snapshot.body || entry.idea.state !== snapshot.state)
      drafts.change(idea.id, { body: entry.idea.body, state: entry.idea.state });
    if (deleteRequests.delete(id)) deleteRequests.add(idea.id);
    const latestCanvas = { ...entry.idea.canvas };
    newNotes.delete(id);
    if (connected_from?.length) {
      acknowledgeConnections({
        changes: connected_from.map((source) => ({
          source_id: source.id,
          target_id: idea.id,
          connected: true,
        })),
        versions: connected_from,
      });
    }
    if (JSON.stringify(latestCanvas) !== JSON.stringify(snapshot.canvas))
      move(idea.id, latestCanvas);
    replaceSelection(id, idea.id);
    onCreated(reply);
    if (deleteRequests.has(idea.id)) void flushDelete(idea.id);
  }
  async function save(id: number) {
    id = resolveId(id);
    const entry = newNotes.get(id);
    if (
      entry &&
      !entry.pending &&
      !entry.attempt &&
      !entry.idea.body.replace(/<[^>]*>/g, "").trim()
    ) {
      clearTimeout(timers.get(id));
      timers.delete(id);
      newNotes.delete(id);
      deleteRequests.delete(id);
      return;
    }
    if (id < 0) await saveNew(id);
    else await drafts.save(id);
  }
  function idle(id: number): Promise<void> {
    const pending = () => {
      const current = resolveId(id);
      return (
        newNotes.get(current)?.pending ||
        moving.has(current) ||
        deleting.has(current) ||
        drafts.drafts.get(current)?.status === "saving"
      );
    };
    if (!pending()) return Promise.resolve();
    return new Promise((resolve) => {
      const stop = watch(
        pending,
        (busy) => {
          if (!busy) {
            stop();
            resolve();
          }
        },
        { flush: "post" },
      );
    });
  }
  async function settle(id: number): Promise<boolean> {
    const started = generation;
    await idle(id);
    if (started !== generation) return false;
    const local = newNotes.get(resolveId(id));
    if (local && !local.attempt && !local.idea.body.replace(/<[^>]*>/g, "").trim()) return true;
    await save(resolveId(id));
    await idle(id);
    if (started !== generation) return false;
    id = resolveId(id);
    if (newNotes.has(id) || !find(id)) return false;
    return settleDraft(id, started);
  }
  async function settleDraft(id: number, started: number): Promise<boolean> {
    if (drafts.drafts.get(id)?.status === "unsaved") {
      await drafts.save(id);
      await idle(id);
      if (started !== generation) return false;
    }
    const draft = drafts.drafts.get(id);
    // A rejected old placement must not block an unrelated content operation.
    // Uncertain placement writes still need reconciliation before proceeding.
    return (!draft || draft.status === "saved") && !attempts.has(id);
  }
  async function remove(id: number): Promise<RemovedNote | null> {
    const started = generation;
    await idle(id);
    if (started !== generation) return null;
    id = resolveId(id);
    const entry = newNotes.get(id);
    if (entry) return removeNew(id, entry, started);
    const note = notes.value.find((n) => n.id === id);
    if (!note || note.author_id !== board().current_user_id) return null;
    open(note);
    deleteRequests.add(id);
    await drafts.save(id);
    await idle(id);
    if (started !== generation) return null;
    await flushDelete(id);
    await idle(id);
    return started === generation ? (deletions.get(id) ?? null) : null;
  }
  async function removeNew(
    id: number,
    entry: NewNote,
    started: number,
  ): Promise<RemovedNote | null> {
    clearTimeout(timers.get(id));
    timers.delete(id);
    if (entry.attempt) {
      await saveNew(id);
      if (started !== generation || newNotes.has(id)) return null;
      return remove(resolveId(id));
    }
    const result = {
      id,
      revision: 0,
      deleted_at: null,
      idea: { ...entry.idea },
      connection: entry.connection,
    };
    newNotes.delete(id);
    errors.delete(id);
    return result;
  }
  function deletableDraft(draft: Draft): boolean {
    // Invalid local text (including an emptied note) cannot prevent deletion.
    // A validation rejection made no write; uncertain saves must still reconcile.
    return draft.status === "saved" || (draft.status === "error" && draft.error === "validation");
  }
  async function flushDelete(id: number) {
    if (!canWrite()) return;
    const draft = drafts.drafts.get(id);
    if (!deleteRequests.has(id) || deleting.has(id) || !draft) return;
    if (!deletableDraft(draft)) return;
    deleting.add(id);
    const started = generation;
    const reply = await request<{ id: number; revision: number; deleted_at: string }>(
      "delete_idea",
      { idea_id: id, revision: draft.idea.revision },
      draft.context,
    );
    if (started !== generation) return;
    deleting.delete(id);
    if (reply.status === "ok") {
      deletions.set(id, { ...reply.value, idea: { ...draft.idea, canvas: find(id)?.canvas } });
      removed.add(id);
      deleteRequests.delete(id);
      errors.delete(id);
      created.delete(id);
      drafts.drafts.delete(id);
    } else errors.set(id, reply.status === "error" ? reply.code : "unavailable");
  }
  async function restore(deletion: RemovedNote): Promise<number | null> {
    if (!canWrite()) return null;
    if (!deletion.deleted_at) return restoreLocal(deletion);
    const started = generation;
    const reply = await request<Idea>("restore_idea", {
      idea_id: deletion.id,
      revision: deletion.revision,
      deleted_at: deletion.deleted_at,
    });
    if (started !== generation) return null;
    if (reply.status !== "ok") {
      errors.set(deletion.id, reply.status === "error" ? reply.code : "unavailable");
      return null;
    }
    removed.delete(reply.value.id);
    deletions.delete(reply.value.id);
    errors.delete(reply.value.id);
    created.set(reply.value.id, reply.value);
    drafts.open(reply.value);
    return reply.value.id;
  }
  function restoreLocal(deletion: RemovedNote): number {
    const previous = deletion.idea;
    const id = add(
      { x: previous.canvas?.x ?? 0, y: previous.canvas?.y ?? 0, ...previous.canvas },
      previous.canvas?.color,
      previous,
      previous.round_id,
      deletion.connection,
    );
    aliases.set(deletion.id, id);
    return id;
  }
  function move(id: number, canvas: CanvasPlacement) {
    id = resolveId(id);
    const entry = newNotes.get(id);
    if (entry) {
      entry.idea.canvas = { ...entry.idea.canvas, ...canvas };
      return;
    }
    placements.set(id, { ...notes.value.find((n) => n.id === id)?.canvas, ...canvas });
    void flushMove(id);
  }
  async function flushMove(id: number) {
    if (!canWrite()) return;
    if (moving.has(id)) return;
    const note = notes.value.find((n) => n.id === id);
    const canvas = placements.get(id);
    if (!note || !canvas) return;
    const started = generation;
    const attempt = attempts.get(id) ?? {
      canvas: { ...canvas },
      key: crypto.randomUUID(),
      version: canvas.version ?? 0,
    };
    attempts.set(id, attempt);
    moving.add(id);
    const reply = await request<CanvasPlacement>("move_idea", {
      idea_id: id,
      request_key: attempt.key,
      version: attempt.version,
      ...attempt.canvas,
    });
    if (started !== generation) return;
    moving.delete(id);
    acceptPlacement(id, attempt, reply);
  }
  function acceptPlacement(id: number, attempt: PlacementAttempt, reply: Reply<CanvasPlacement>) {
    if (reply.status === "ok") {
      attempts.delete(id);
      errors.delete(id);
      const latest = placements.get(id);
      if (latest && JSON.stringify(latest) !== JSON.stringify(attempt.canvas)) {
        placements.set(id, { ...latest, version: reply.value.version });
        void flushMove(id);
      } else placements.set(id, reply.value);
    } else {
      errors.set(id, reply.status === "error" ? reply.code : "unavailable");
      if (reply.status === "error" && reply.code !== "offline") {
        attempts.delete(id);
        placements.delete(id);
      }
    }
  }
  function retry(id: number) {
    if (!canWrite()) return;
    if (id < 0) void saveNew(id);
    else {
      void save(id);
      if (attempts.has(id)) void flushMove(id);
      if (deleteRequests.has(id)) void flushDelete(id);
    }
  }
  function reset(retain = true) {
    generation++;
    for (const timer of timers.values()) clearTimeout(timer);
    timers.clear();
    drafts.reset(retain);
    if (retain)
      drafts.recovered.value.push(
        ...[...newNotes.values()].map(
          (n) => ({ title: n.idea.title, body: n.idea.body, state: n.idea.state }) as IdeaContent,
        ),
      );
    newNotes.clear();
    created.clear();
    placements.clear();
    connections.clear();
    removed.clear();
    deleting.clear();
    deleteRequests.clear();
    errors.clear();
    moving.clear();
    attempts.clear();
    keys.clear();
    aliases.clear();
    deletions.clear();
  }
  watch(
    () => board().ideas,
    (ideas) => {
      for (const idea of ideas) {
        drafts.receive(idea);
        created.delete(idea.id);
        if (
          !moving.has(idea.id) &&
          !attempts.has(idea.id) &&
          (idea.canvas?.version ?? 0) >= (placements.get(idea.id)?.version ?? 0)
        )
          placements.delete(idea.id);
      }
    },
  );
  watch(
    () =>
      [...drafts.drafts.values()].map((d) => `${d.idea.id}:${d.status}:${d.idea.revision}`).join(),
    () => {
      for (const id of deleteRequests) void flushDelete(id);
    },
  );
  watch(canWrite, (allowed) => {
    if (!allowed) {
      for (const timer of timers.values()) clearTimeout(timer);
      timers.clear();
    }
  });
  watch(
    () => board().session?.configuration.private_mode,
    () => connections.clear(),
  );
  onUnmounted(() => reset(false));
  return {
    notes,
    drafts,
    errors,
    add,
    open,
    change,
    save,
    move,
    deleting,
    retry,
    reset,
    newNotes,
    remove,
    restore,
    settle,
    resolveId,
    key,
    find,
    acknowledgeConnections,
    connection: (id: number) => newNotes.get(resolveId(id))?.connection,
  };
}
