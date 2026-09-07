import { computed, onUnmounted, reactive, watch } from "vue";
import { useIdeaDrafts } from "./useIdeaDrafts";
import type {
  Board,
  BoardContext,
  CanvasPlacement,
  Idea,
  IdeaContent,
  Request,
  Reply,
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
}
interface PlacementAttempt {
  canvas: CanvasPlacement;
  key: string;
  version: number;
}
export function useCanvasNotes(
  board: () => Board,
  request: Request,
  context: () => BoardContext,
  replaceSelection: (from: number, to: number) => void,
) {
  const drafts = useIdeaDrafts(request, context);
  const newNotes = reactive(new Map<number, NewNote>());
  const created = reactive(new Map<number, Idea>());
  const placements = reactive(new Map<number, CanvasPlacement>());
  const removed = reactive(new Set<number>());
  const deleting = reactive(new Set<number>());
  const deleteRequests = reactive(new Set<number>());
  const errors = reactive(new Map<number, string>());
  const timers = new Map<number, ReturnType<typeof setTimeout>>();
  const moving = new Set<number>();
  const attempts = new Map<number, PlacementAttempt>();
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
        canvas: { ...idea.canvas, ...placements.get(idea.id) },
      }));
  });
  function add(point: Point, color = "yellow", source?: Idea): number {
    const id = nextId--;
    const initial = source ?? {
      title: null,
      body: "<p></p>",
      preview: "",
      id: null,
      revision: null,
    };
    const idea: Idea = {
      id,
      session_id: board().session!.id,
      author_id: board().current_user_id,
      author_kind: "human",
      title: initial.title,
      body: initial.body,
      preview: initial.preview,
      state: "active",
      visibility: board().session?.configuration.private_mode ? "private" : "shared",
      revision: 0,
      published_revision: null,
      source_idea_id: initial.id,
      source_revision: initial.revision,
      inserted_at: new Date().toISOString(),
      canvas: { ...point, width: 280, color },
    };
    newNotes.set(id, {
      idea,
      key: crypto.randomUUID(),
      context: context(),
      version: board().session!.configuration_version,
      pending: false,
      error: null,
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
    const entry = newNotes.get(id);
    if (!entry || entry.pending || !entry.idea.body.replace(/<[^>]*>/g, "").trim()) return;
    // Preserve the original idempotent create request across uncertain outcomes.
    entry.pending = true;
    const started = generation;
    const snapshot = entry.attempt ?? { ...entry.idea, canvas: { ...entry.idea.canvas } };
    entry.attempt = snapshot;
    const reply = await request<Idea>(
      entry.idea.source_idea_id ? "derive_idea" : "create_idea",
      {
        request_key: entry.key,
        title: snapshot.title,
        body: snapshot.body,
        configuration_version: entry.version,
        canvas: snapshot.canvas,
        idea_id: snapshot.source_idea_id,
        revision: snapshot.source_revision,
      },
      entry.context,
    );
    if (started !== generation) return;
    entry.pending = false;
    if (reply.status === "ok") {
      acceptCreated(id, entry, snapshot, reply.value);
    } else {
      entry.error = reply.status === "error" ? reply.code : "unavailable";
      errors.set(id, entry.error);
      if (entry.error !== "offline") entry.attempt = undefined;
    }
  }
  function acceptCreated(id: number, entry: NewNote, snapshot: Idea, idea: Idea) {
    created.set(idea.id, idea);
    drafts.open(idea);
    if (entry.idea.body !== snapshot.body || entry.idea.state !== snapshot.state)
      drafts.change(idea.id, { body: entry.idea.body, state: entry.idea.state });
    if (deleteRequests.delete(id)) deleteRequests.add(idea.id);
    const latestCanvas = { ...entry.idea.canvas };
    newNotes.delete(id);
    if (JSON.stringify(latestCanvas) !== JSON.stringify(snapshot.canvas))
      move(idea.id, latestCanvas);
    replaceSelection(id, idea.id);
    if (deleteRequests.has(idea.id)) void flushDelete(idea.id);
  }
  async function save(id: number) {
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
  async function remove(id: number) {
    const entry = newNotes.get(id);
    if (entry) {
      clearTimeout(timers.get(id));
      timers.delete(id);
      if (entry.pending || entry.attempt) {
        deleteRequests.add(id);
        if (!entry.pending) await saveNew(id);
      } else {
        newNotes.delete(id);
        errors.delete(id);
      }
      return;
    }
    const note = notes.value.find((n) => n.id === id);
    if (!note || note.author_id !== board().current_user_id) return;
    open(note);
    deleteRequests.add(id);
    await drafts.save(id);
    await flushDelete(id);
  }
  async function flushDelete(id: number) {
    const draft = drafts.drafts.get(id);
    if (!deleteRequests.has(id) || deleting.has(id) || !draft) return;
    // Invalid local text (including an emptied note) cannot prevent deletion.
    // A validation rejection made no write; uncertain saves must still reconcile.
    const settled =
      draft.status === "saved" || (draft.status === "error" && draft.error === "validation");
    if (!settled) return;
    deleting.add(id);
    const started = generation;
    const reply = await request<{ id: number }>(
      "delete_idea",
      { idea_id: id, revision: draft.idea.revision },
      draft.context,
    );
    if (started !== generation) return;
    deleting.delete(id);
    if (reply.status === "ok") {
      removed.add(id);
      deleteRequests.delete(id);
      errors.delete(id);
      created.delete(id);
      drafts.drafts.delete(id);
    } else errors.set(id, reply.status === "error" ? reply.code : "unavailable");
  }
  function move(id: number, canvas: CanvasPlacement) {
    const entry = newNotes.get(id);
    if (entry) {
      entry.idea.canvas = { ...entry.idea.canvas, ...canvas };
      return;
    }
    placements.set(id, { ...notes.value.find((n) => n.id === id)?.canvas, ...canvas });
    void flushMove(id);
  }
  async function flushMove(id: number) {
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
    removed.clear();
    deleting.clear();
    deleteRequests.clear();
    errors.clear();
    moving.clear();
    attempts.clear();
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
  };
}
