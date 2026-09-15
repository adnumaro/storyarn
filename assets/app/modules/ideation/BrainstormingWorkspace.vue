<script setup lang="ts">
import { bandOffsets as layoutBands, NOTE_HEIGHT, type BandOffsets } from "./lib/bands";
import { computed, nextTick, onUnmounted, ref, watch } from "vue";
import {
  Archive,
  ArrowDownToLine,
  Ban,
  CircleX,
  LayoutDashboard,
  Link2,
  ListChecks,
  Plus,
  RotateCcw,
  StickyNote,
  Unplug,
} from "@lucide/vue";
import { Button } from "@components/ui/button";
import { Popover, PopoverContent, PopoverTrigger } from "@components/ui/popover";
import ToolbarTooltip from "@components/toolbar/ToolbarTooltip.vue";
import DashboardContent from "@shell/DashboardContent.vue";
import LiveLink from "@components/navigation/LiveLink.vue";
import BrainstormingCanvas from "./components/BrainstormingCanvas.vue";
import CanvasConnectionTools from "./components/CanvasConnectionTools.vue";
import CanvasShapePicker from "./components/CanvasShapePicker.vue";
import { useCanvasConnections } from "./composables/useCanvasConnections";
import GroupSelectionTools from "./components/GroupSelectionTools.vue";
import { useCanvasGroups } from "./composables/useCanvasGroups";
import IdeaEditor from "./components/IdeaEditor.vue";
import BoardSelect from "./components/BoardSelect.vue";
import RoundStartedToast from "./components/RoundStartedToast.vue";
import { useBoardConnection } from "./composables/useBoardConnection";
import { useCanvasNotes, type RemovedNote } from "./composables/useCanvasNotes";
import {
  useCanvasHistory,
  type CanvasCommand,
  type CanvasTarget,
} from "./composables/useCanvasHistory";
import { readNotes, writeNotes, type NoteCopy } from "./lib/clipboard";
import { useBoardText } from "./composables/useBoardText";
import { sameBody } from "./lib/paste";
import { notePosition } from "./lib/placement";
import type { Point } from "./composables/useCanvasViewport";
import type {
  Board,
  Idea,
  IdeaContent,
  CanvasPlacement,
  NoteShape,
  ConnectionChange,
  Round,
  RoundPrivacy,
  BoardLink,
} from "./types";
import type { BrainstormingCommentsState, BrainstormingCommentTarget } from "./commentTypes";
import { NOTE_COLOR_IDS, noteColor, noteSwatch } from "./lib/noteColors";
const {
  board,
  baseUrl,
  comments,
  linked = null,
} = defineProps<{
  board: Board;
  baseUrl: string;
  comments?: BrainstormingCommentsState;
  linked?: BoardLink | null;
}>();
const { t, error, options, member } = useBoardText();
const selectedIds = ref<number[]>([]);
const selected = computed(() => selectedIds.value[0] ?? null);
const editing = ref<number | null>(null);
const list = ref(false);
const failure = ref<string | null>(null),
  resetNotice = ref(false),
  starting = ref(false);
// The list view keeps a creative-state filter; the canvas shows every note in place.
const state = ref("all");
const roundPending = ref(false);
let oldestLoadedIdeaId: number | null = null;
let historyGeneration = 0;
let cancelHistoryPreparation: (() => void) | undefined;
const rounds = computed(() => {
  const entries = new Map(board.rounds.map((round) => [round.id, round]));
  if (board.active_round) entries.set(board.active_round.id, board.active_round);
  return [...entries.values()].sort((a, b) => a.number - b.number);
});
const privateRounds = computed(
  () => new Set(rounds.value.filter((round) => round.private).map((round) => round.id)),
);
const activeRoundPrivate = computed(() => !!board.active_round?.private);
const canvas = ref<InstanceType<typeof BrainstormingCanvas> | null>(null);
// Popovers under a tooltip anchor to their button explicitly, as the pickers do.
const colorTrigger = ref<HTMLButtonElement>();
const linksTrigger = ref<HTMLButtonElement>();
const { request, context, online, sync } = useBoardConnection(() => board, reset);
async function createComment(target: BrainstormingCommentTarget) {
  const reply = await request("comments_open", {
    idea_id: target.ideaId,
    group_id: target.groupId,
    position: target.position,
  });
  if (reply.status === "error") failure.value = reply.code;
}
async function useReferences(ideaId: number | null) {
  const reply = await request("references_open", { idea_id: ideaId });
  if (reply.status === "error") failure.value = reply.code;
}
const preparingDecision = ref(false);
const decisionReady = computed(() => !preparingDecision.value && online.value && writable.value);
watch(
  () => board.epoch,
  () => {
    preparingDecision.value = false;
  },
);
// A group of a private round is only visible to its members' authors; the
// server would refuse the decision, so the proposal is not even sent.
function groupInPrivateRound(groupId: number) {
  const group = groups.groups.value.find((group) => group.id === groupId);
  return (
    group?.idea_ids.some((ideaId) => {
      const note = board.ideas.find((idea) => idea.id === ideaId);
      return note?.round_id != null && privateRounds.value.has(note.round_id);
    }) ?? false
  );
}
function decisionBlocked(groupId?: number) {
  if (!decisionReady.value) return true;
  if (groupId === undefined) return !decisionSelection.value;
  return groupInPrivateRound(groupId);
}
async function proposeDecision(groupId?: number) {
  if (decisionBlocked(groupId)) return;
  const at = context();
  preparingDecision.value = true;
  const payload =
    groupId === undefined ? { idea_ids: [...selectedIds.value] } : { group_id: groupId };
  const reply = await request("decisions_new", payload);
  if (at.epoch !== board.epoch || at.session_id !== board.session?.id) return;
  preparingDecision.value = false;
  if (reply.status === "error") failure.value = reply.code;
}
// Bands are as tall as their content. The canvas measures and reports the
// layout; until it does, note geometry from the board gives a first estimate.
const measuredBands = ref<BandOffsets | null>(null);
const bandOffsets = computed<BandOffsets>(
  () =>
    measuredBands.value ??
    layoutBands(rounds.value, (roundId) => {
      const bottoms = board.ideas
        .filter((idea) => idea.round_id === roundId && typeof idea.canvas?.y === "number")
        .map((idea) => (idea.canvas?.y ?? 0) + NOTE_HEIGHT);
      return bottoms.length ? Math.max(...bottoms) : null;
    }),
);
watch(
  () => board.session?.id,
  () => {
    measuredBands.value = null;
  },
);
const notes = useCanvasNotes(
  () => board,
  request,
  context,
  (from, to) => {
    selectedIds.value = selectedIds.value.map((id) => (id === from ? to : id));
    if (editing.value === from) editing.value = to;
  },
  (idea) => connections.created(idea),
  () => bandOffsets.value,
);
// Placeholders for other people's private notes, in canvas units like everything else.
const masked = computed(() =>
  board.masked_ideas.map((item) => ({
    ...item,
    canvas: {
      ...item.canvas,
      y: (item.canvas.y ?? 0) + (bandOffsets.value.get(item.round_id) ?? 0),
    },
  })),
);
// Notes per round for the headers: what this client holds plus what it cannot read.
const roundCounts = computed(() => {
  const counts = new Map<number, number>();
  const bump = (roundId: number | null | undefined) => {
    if (roundId != null) counts.set(roundId, (counts.get(roundId) ?? 0) + 1);
  };
  for (const note of notes.notes.value) if (note.id > 0) bump(note.round_id);
  for (const item of board.masked_ideas) bump(item.round_id);
  return counts;
});
const selectionPrivate = computed(() =>
  selectedNotes(selectedIds.value).some(
    (note) => note.round_id != null && privateRounds.value.has(note.round_id),
  ),
);
const current = computed(() => notes.notes.value.find((n) => n.id === selected.value));
const selectionShape = computed(() => {
  const shapes = new Set(
    selectedNotes(selectedIds.value).map((note) => note.canvas?.shape ?? "rectangle"),
  );
  return shapes.size === 1 ? [...shapes][0] : null;
});
const writable = computed(() => board.can_edit && board.session?.status === "open");
const decisionSelection = computed(() => {
  const sources = selectedNotes(selectedIds.value);
  return (
    sources.length > 0 &&
    sources.length <= 20 &&
    sources.length === selectedIds.value.length &&
    sources.every(
      (note) => note.id > 0 && note.visibility === "shared" && !!note.published_revision,
    )
  );
});
const canCreate = computed(() => writable.value && board.session?.contributions_open !== false);
const own = computed(() => current.value?.author_id === board.current_user_id);
const draft = computed(() =>
  selected.value !== null ? notes.drafts.drafts.get(selected.value) : undefined,
);
const visible = computed(() =>
  notes.notes.value.map((note) => ({
    ...note,
    key: notes.key(note.id),
    round_number: rounds.value.find((round) => round.id === note.round_id)?.number,
  })),
);
// A parked note with a copy brought ahead is no longer waiting for later.
const forwarded = computed(
  () => new Set(notes.notes.value.map((note) => note.source_idea_id).filter((id) => id != null)),
);
const listed = computed(() =>
  visible.value.filter(
    (note) =>
      (state.value === "all" || note.state === state.value) &&
      !(state.value === "parked" && forwarded.value.has(note.id)),
  ),
);
const statuses = computed(() =>
  Object.fromEntries([...notes.drafts.drafts.values()].map((d) => [d.idea.id, d.status])),
);
const history = useCanvasHistory(
  () => {
    if (failure.value !== "unavailable")
      failure.value = online.value ? "undo_unavailable" : "offline";
  },
  () => !online.value || failure.value === "unavailable",
  prepareHistory,
);
const connections = useCanvasConnections({
  notes,
  request,
  context,
  history,
  allowed: () => writable.value,
  notify: (code) => {
    failure.value = code;
  },
});
const mutationBusy = computed(() => history.busy.value || connections.pending.value !== null);
const groups = useCanvasGroups(
  () => board,
  request,
  history,
  (code, replacing) => {
    if (replacing === undefined || failure.value === replacing) failure.value = code;
  },
  (id) => {
    if (id !== null) select([]);
  },
  async (ids) => {
    for (const id of ids) if (!(await notes.settle(id))) return false;
    return true;
  },
  () => bandOffsets.value,
);
function groupingProblem(ids: number[], sources: ReturnType<typeof selectedNotes>) {
  if (sources.some((note) => note.round_id != null && privateRounds.value.has(note.round_id)))
    return "private_round";
  if (sources.some((note) => groups.groups.value.some((group) => group.idea_ids.includes(note.id))))
    return "already_grouped";
  const shared = sources.every((note) => note.id > 0 && note.visibility === "shared");
  return sources.length >= 2 && sources.length === ids.length && shared ? null : "invalid_group";
}
async function createGroup(ids = selectedIds.value) {
  if (!groups.allowed.value || mutationBusy.value) return;
  const sources = selectedNotes(ids);
  const problem = groupingProblem(ids, sources);
  if (problem) {
    // The toolbar disables its button; the keyboard shortcut still needs an answer.
    if (ids.length) failure.value = problem;
    return;
  }
  finish();
  const x = Math.min(...sources.map((note) => notePosition(note).x)) - 28;
  const y = Math.min(...sources.map((note) => notePosition(note).y)) - 64;
  const width =
    Math.max(...sources.map((note) => notePosition(note).x + (note.canvas?.width ?? 280))) - x + 28;
  const height = Math.max(...sources.map((note) => notePosition(note).y + 260)) - y + 28;
  await groups.create(ids, { x, y, width, height });
  canvas.value?.focus();
}
function separateGroup(id: number) {
  return groups.separate(id, canvas.value?.summaryAnchor?.(id));
}
function groupMembership(id: number, ids: number[], add: boolean) {
  return groups.membership(id, ids, add, canvas.value?.summaryAnchor?.(id));
}
async function revealGroup(id: number) {
  const group = groups.groups.value.find((group) => group.id === id);
  if (!group) return;
  if (group.idea_ids.some((noteId) => !notes.find(noteId))) {
    failure.value = null;
    await request("browse_ideas", { before_id: Math.min(...group.idea_ids) });
  }
  await nextTick();
  canvas.value?.fitAll();
}
let editingBefore: Idea | undefined;
function reset(reason: string) {
  oldestLoadedIdeaId = null;
  rememberLoadedIdeas();
  cancelHistoryPreparation?.();
  historyGeneration++;
  roundPending.value = false;
  notes.reset(reason !== "access_changed");
  groups.reset();
  connections.reset();
  selectedIds.value = [];
  editing.value = null;
  history.clear();
  editingBefore = undefined;
  resetNotice.value = reason !== "access_changed" && notes.drafts.recovered.value.length > 0;
}
async function locate(note: Idea) {
  list.value = false;
  select(note.id);
  await nextTick();
  canvas.value?.center(note);
  edit(note.id);
}
function finish() {
  const id = editing.value;
  const before = editingBefore;
  editing.value = null;
  editingBefore = undefined;
  if (id === null) return;
  const after = notes.find(id);
  void notes.save(id);
  if (
    before &&
    before.revision > 0 &&
    after &&
    !sameBody(before.body, after.body) &&
    after.body.replace(/<[^>]*>/g, "").trim()
  ) {
    history.push(contentCommand(id, { body: before.body }, { body: after.body }));
  }
}
function select(ids: number[] | number | null) {
  const next = typeof ids === "number" ? [ids] : (ids ?? []);
  if (next.length !== 1 || next[0] !== selected.value) finish();
  selectedIds.value = next;
}
function presenceCommand(
  id: number,
  initiallyCreated: boolean,
  deletion?: RemovedNote,
): CanvasCommand {
  const initial = notes.find(id);
  const initialConnection = notes.connection(id);
  const at = context();
  const valid = () => at.epoch === board.epoch && at.session_id === board.session?.id;
  let removed = deletion;
  async function hide() {
    if (!valid()) return false;
    const result = await notes.remove(id);
    if (!result) {
      // Finishing an untouched local note already cancels it, without a server
      // deletion. Its creation is still safely undoable/redoable in this session.
      if (!initiallyCreated || !initial || notes.resolveId(id) >= 0 || notes.find(id)) return false;
      removed = {
        id: notes.resolveId(id),
        revision: 0,
        deleted_at: null,
        idea: initial,
        connection: initialConnection,
      };
      select([]);
      return true;
    }
    removed = result;
    select([]);
    return true;
  }
  async function show() {
    if (!removed || !valid()) return false;
    const restored = await notes.restore(removed);
    if (restored === null) return false;
    id = restored;
    select(id);
    return true;
  }
  const targets = (undo: boolean): CanvasTarget[] => {
    const restoring = initiallyCreated !== undo ? removed?.idea : undefined;
    return [
      {
        id: notes.resolveId(id),
        ...(restoring ? { restoring: { roundId: restoring.round_id } } : {}),
      },
    ];
  };
  return initiallyCreated
    ? { targets, undo: hide, redo: show }
    : { targets, undo: show, redo: hide };
}
function contentCommand(
  id: number,
  before: Partial<IdeaContent>,
  after: Partial<IdeaContent>,
): CanvasCommand {
  async function apply(expected: Partial<IdeaContent>, value: Partial<IdeaContent>) {
    if (!(await notes.settle(id))) return false;
    const note = notes.find(id);
    if (
      !note ||
      Object.entries(expected).some(([key, value]) =>
        key === "body"
          ? !sameBody(note.body, String(value))
          : note[key as keyof IdeaContent] !== value,
      )
    )
      return false;
    notes.open(note);
    notes.drafts.change(note.id, value);
    const saved = await notes.settle(note.id);
    if (saved) select(note.id);
    return saved;
  }
  return {
    targets: () => [{ id: notes.resolveId(id) }],
    undo: () => apply(after, before),
    redo: () => apply(before, after),
  };
}
function historyRangeLoaded() {
  if (oldestLoadedIdeaId === null || board.ideas_next === null) return true;
  if (board.idea_before !== null && board.idea_before <= oldestLoadedIdeaId) return true;
  return board.ideas.some((idea) => idea.id <= oldestLoadedIdeaId!);
}
function prepareHistory(targets: CanvasTarget[]): Promise<boolean> {
  if (connections.pending.value) return Promise.resolve(false);
  // Current targets can be used directly, even during a background refresh.
  // A removed note retains enough local context to be restored on this canvas.
  const available = targets.every((target) => notes.find(target.id) || target.restoring);
  if (available) return Promise.resolve(true);
  if (!board.loading && historyRangeLoaded()) return Promise.resolve(true);
  // The target left the loaded history range: page the board back to it first.
  const at = context();
  const expected = ++historyGeneration;
  return new Promise((resolve) => {
    const complete = (ready: boolean) => {
      stop();
      cancelHistoryPreparation = undefined;
      resolve(ready);
    };
    const check = () => {
      const latest = context();
      const valid =
        expected === historyGeneration &&
        at.epoch === latest.epoch &&
        at.session_id === latest.session_id;
      if (!valid || !online.value || failure.value || board.error) complete(false);
      else if (!board.loading && historyRangeLoaded()) complete(true);
    };
    const stop = watch(
      () => [
        board.idea_before,
        board.loading,
        board.ideas,
        board.error,
        board.epoch,
        board.session?.id,
        failure.value,
        online.value,
      ],
      check,
      { flush: "post" },
    );
    cancelHistoryPreparation = () => complete(false);
    void request("browse_ideas", { before_id: oldestLoadedIdeaId });
    check();
  });
}
function refresh() {
  failure.value = null;
  sync();
}
// Bring a band's header to the top once the board knows the round. A round that
// was just started arrives with the next refresh, so wait for it briefly.
let focusStop: (() => void) | undefined;
function focusRound(target: number | ((round: Round) => boolean)) {
  focusStop?.();
  const find = () =>
    typeof target === "number"
      ? rounds.value.find((round) => round.id === target)
      : rounds.value.find(target);
  const show = (round: Round) => {
    list.value = false;
    void nextTick(() => canvas.value?.scrollToRound(round));
  };
  const found = find();
  if (found) {
    show(found);
    return;
  }
  const stop = watch(rounds, () => {
    const round = find();
    if (!round) return;
    stop();
    focusStop = undefined;
    show(round);
  });
  const timer = setTimeout(() => {
    stop();
    focusStop = undefined;
  }, 10_000);
  focusStop = () => {
    stop();
    clearTimeout(timer);
    focusStop = undefined;
  };
}
async function newRound() {
  if (!board.can_manage || !board.session || roundPending.value) return;
  finish();
  failure.value = null;
  roundPending.value = true;
  // The board still shows the previous round when the reply lands; wait for the new one.
  const previous = board.active_round?.id ?? null;
  startingRound = true;
  const reply = await request("new_round", { revision: board.session.revision });
  roundPending.value = false;
  if (reply.status !== "ok") {
    startingRound = false;
    failure.value = reply.status === "error" ? reply.code : "unavailable";
    return;
  }
  focusRound((round) => round.status === "active" && round.id !== previous);
}
async function updatePrompt(id: number, prompt: string) {
  if (!board.can_manage || !board.session || roundPending.value) return;
  failure.value = null;
  const reply = await request("update_round", {
    revision: board.session.revision,
    round_id: id,
    prompt: prompt.trim() || null,
  });
  if (reply.status !== "ok") failure.value = reply.status === "error" ? reply.code : "unavailable";
}
// A round somebody else started shows up as a toast; the one we start is focused.
const startedRound = ref<Round | null>(null);
let knownRoundIds: Set<number> | null = null;
let startingRound = false;
function goToStartedRound(round: Round) {
  startedRound.value = null;
  focusRound(round.id);
}
watch(
  rounds,
  (list) => {
    const ids = new Set(list.map((round) => round.id));
    if (knownRoundIds !== null) {
      const fresh = list.find(
        (round) => round.status === "active" && !knownRoundIds!.has(round.id),
      );
      if (fresh && !startingRound) startedRound.value = fresh;
      if (fresh) startingRound = false;
    }
    knownRoundIds = ids;
  },
  { immediate: true },
);
async function updatePrivacy(id: number, attrs: RoundPrivacy) {
  await roundWrite("set_round_privacy", { round_id: id, ...attrs });
}
async function revealRound(id: number) {
  await roundWrite("reveal_round", { round_id: id });
}
async function roundWrite(event: string, payload: Record<string, unknown>) {
  if (!board.can_manage || !board.session || roundPending.value) return;
  failure.value = null;
  roundPending.value = true;
  const reply = await request(event, { revision: board.session.revision, ...payload });
  roundPending.value = false;
  if (reply.status !== "ok") failure.value = reply.status === "error" ? reply.code : "unavailable";
}
async function closeRound(id: number) {
  if (!board.can_manage || !board.session || roundPending.value) return;
  finish();
  failure.value = null;
  roundPending.value = true;
  const reply = await request("close_round", { revision: board.session.revision, round_id: id });
  roundPending.value = false;
  if (reply.status !== "ok") failure.value = reply.status === "error" ? reply.code : "unavailable";
}
function add(point: Point, roundId?: number) {
  if (!canCreate.value || mutationBusy.value) return;
  finish();
  const id = notes.add(point, current.value?.canvas?.color, undefined, roundId);
  history.push(presenceCommand(id, true));
  selectedIds.value = [id];
  editing.value = id;
}
function edit(id: number) {
  const note = notes.find(id);
  if (!note || !writable.value || mutationBusy.value || note.author_id !== board.current_user_id)
    return;
  if (editing.value === id) return;
  select(id);
  notes.open(note);
  editingBefore = { ...note };
  editing.value = id;
}
function placementCommand(
  id: number,
  before: CanvasPlacement,
  after: CanvasPlacement,
): CanvasCommand {
  const roundId = notes.find(id)?.round_id ?? null;
  const offset = () => (roundId === null ? 0 : (bandOffsets.value.get(roundId) ?? 0));
  const shifted = (canvas: CanvasPlacement, by: number): CanvasPlacement =>
    typeof canvas.y === "number" ? { ...canvas, y: canvas.y + by } : canvas;
  // History describes a placement within its round, independent of the space
  // occupied by earlier rounds when the action is undone or redone.
  const previous = shifted(before, -offset());
  const next = shifted(after, -offset());
  function matches(canvas: CanvasPlacement | undefined, expected: CanvasPlacement) {
    const placement = {
      ...shifted(canvas ?? {}, -offset()),
      shape: canvas?.shape ?? "rectangle",
      width: canvas?.width ?? 280,
    };
    return Object.entries(expected).every(
      ([key, value]) => placement[key as keyof CanvasPlacement] === value,
    );
  }
  async function apply(expected: CanvasPlacement, value: CanvasPlacement) {
    if (!(await notes.settle(id))) return false;
    const note = notes.find(id);
    if (!note || note.round_id !== roundId || !matches(note.canvas, expected)) return false;
    notes.move(note.id, shifted(value, offset()));
    if (!(await notes.settle(note.id))) return false;
    const saved = notes.find(note.id)?.canvas;
    return matches(saved, value);
  }
  return {
    targets: () => [{ id: notes.resolveId(id) }],
    undo: () => apply(next, previous),
    redo: () => apply(previous, next),
  };
}
function group(commands: CanvasCommand[]): CanvasCommand {
  // Track completed members so retrying an interrupted batch never repeats them.
  let applied = commands.length;
  return {
    targets: (undo) =>
      (undo ? commands.slice(0, applied) : commands.slice(applied)).flatMap((command) =>
        command.targets(undo),
      ),
    undo: async () => {
      while (applied > 0) {
        if (!(await commands[applied - 1].undo())) return false;
        applied--;
      }
      return true;
    },
    redo: async () => {
      while (applied < commands.length) {
        if (!(await commands[applied].redo())) return false;
        applied++;
      }
      return true;
    },
  };
}
function move(moves: Array<{ id: number; point: Point }>) {
  if (!writable.value || mutationBusy.value) return;
  finish();
  const commands: CanvasCommand[] = [];
  for (const { id, point } of moves) {
    const note = notes.find(id);
    if (!note) continue;
    const before = notePosition(note);
    if (before.x === point.x && before.y === point.y) continue;
    notes.move(id, point);
    commands.push(placementCommand(id, before, point));
  }
  if (commands.length) history.push(group(commands));
}
function color(value: string) {
  if (!current.value || mutationBusy.value) return;
  const before = noteColor(current.value.canvas?.color);
  if (before === value) return;
  const id = current.value.id;
  notes.move(id, { color: value });
  history.push(placementCommand(id, { color: before }, { color: value }));
}
function shape(value: NoteShape) {
  if (!writable.value || mutationBusy.value) return;
  const commands: CanvasCommand[] = [];
  for (const note of selectedNotes(selectedIds.value)) {
    const before = note.canvas?.shape ?? "rectangle";
    if (before === value) continue;
    const after = { shape: value };
    notes.move(note.id, { ...notePosition(note), ...after });
    commands.push(placementCommand(note.id, { shape: before }, after));
  }
  if (commands.length) history.push(group(commands));
}
async function remove(ids: number[]) {
  if (!writable.value || mutationBusy.value) return;
  finish();
  const at = context();
  const commands = await history.run(async () => {
    const commands: CanvasCommand[] = [];
    for (const id of ids) {
      if (at.epoch !== board.epoch || at.session_id !== board.session?.id) break;
      const note = notes.find(id);
      if (note?.author_id !== board.current_user_id) continue;
      const deletion = await notes.remove(id);
      if (deletion) commands.push(presenceCommand(id, false, deletion));
    }
    return commands;
  });
  if (commands?.length) {
    history.push(group(commands));
    select([]);
  }
}
// Where a note lands when it has no place of its own: under the lowest note
// of the round in progress. The canvas measures that; here it is estimated
// from note geometry.
function landing(x: number): Point {
  const active = board.active_round;
  const top = active ? (bandOffsets.value.get(active.id) ?? 0) : 0;
  const bottoms = notes.notes.value
    .filter((other) => other.round_id === active?.id && typeof other.canvas?.y === "number")
    .map((other) => (other.canvas?.y ?? 0) + NOTE_HEIGHT);
  return { x, y: (bottoms.length ? Math.max(...bottoms) : top + 60) + 24 };
}
function bringForward(id: number, point?: Point) {
  const note = notes.notes.value.find((candidate) => candidate.id === id);
  const active = board.active_round;
  if (!note || !active || !canCreate.value || note.round_id === active.id) return;
  notes.bringForward(note, point ?? landing(note.canvas?.x ?? 0));
}
function changeState(value: "active" | "parked" | "discarded", id = current.value?.id) {
  const note = id === undefined ? null : notes.find(id);
  if (!note || note.author_id !== board.current_user_id || mutationBusy.value) return;
  finish();
  notes.open(note);
  notes.drafts.change(note.id, { state: value });
  void notes.save(note.id);
  history.push(contentCommand(note.id, { state: note.state }, { state: value }));
  select([]);
}
async function connect(source: number, target: number, connected: boolean) {
  if (!writable.value || mutationBusy.value) return;
  finish();
  if (connected && related(source, target)) return;
  await connections.change([
    {
      source_id: source,
      target_id: target,
      connected,
      ...(connected ? { direction: "none" } : {}),
    },
  ]);
}
function related(source: number, target: number) {
  return (
    notes.find(source)?.canvas?.links?.includes(target) ||
    notes.find(target)?.canvas?.links?.includes(source)
  );
}
async function changeConnections(changes: ConnectionChange[]) {
  if (!writable.value || mutationBusy.value) return;
  finish();
  await connections.change(changes);
}
async function connectSelection(ids: number[], connected: boolean) {
  if (!writable.value || mutationBusy.value) return;
  const available = new Set(visible.value.map((note) => note.id));
  const selected = [...new Set(ids)].filter((id) => available.has(id));
  if (selected.length < 2) return;
  const changes: ConnectionChange[] = connected
    ? selected
        .slice(1)
        .filter((id) => !related(selected[0], id))
        .map((id) => ({ source_id: selected[0], target_id: id, connected, direction: "none" }))
    : selected.flatMap((id) =>
        (notes.find(id)?.canvas?.links ?? [])
          .filter((target) => selected.includes(target))
          .map((target) => ({ source_id: id, target_id: target, connected })),
      );
  finish();
  await connections.change(changes);
}
async function addConnected(ids: number[], point: Point) {
  if (!canCreate.value || mutationBusy.value || !ids.length) return;
  if (ids.length > 100) {
    failure.value = "selection_too_large";
    return;
  }
  const sources = selectedNotes(ids);
  if (sources.length !== new Set(ids).size) return;
  const color = sources[0]?.canvas?.color;
  const at = context();
  finish();
  await history.run(async () => {
    const sourceIds = await settledConnectionSources(ids);
    if (
      !sourceIds ||
      at.epoch !== board.epoch ||
      at.session_id !== board.session?.id ||
      !canCreate.value
    )
      return;
    const id = notes.add(point, color, undefined, undefined, { source_ids: sourceIds });
    history.push(presenceCommand(id, true));
    selectedIds.value = [id];
    editing.value = id;
    await nextTick();
    const created = notes.find(id);
    if (created) await canvas.value?.revealNote?.(created);
  });
}
async function settledConnectionSources(ids: number[]) {
  for (const id of ids) {
    if (!(await notes.settle(id))) {
      failure.value = "save_before_connect";
      return null;
    }
  }
  const sources = [...new Set(ids.map(notes.resolveId))];
  if (sources.some((id) => id <= 0 || !notes.find(id))) {
    failure.value = "save_before_connect";
    return null;
  }
  return sources;
}
function selectedNotes(ids: number[]) {
  return visible.value.filter((note) => ids.includes(note.id));
}
function copy(event: ClipboardEvent, ids: number[]) {
  writeNotes(event, selectedNotes(ids));
}
function cut(event: ClipboardEvent, ids: number[]) {
  if (!writable.value || mutationBusy.value) return;
  const owned = selectedNotes(ids).filter((note) => note.author_id === board.current_user_id);
  if (writeNotes(event, owned)) void remove(owned.map((note) => note.id));
}
async function insert(copies: NoteCopy[], point: Point) {
  if (!canCreate.value || mutationBusy.value || !copies.length) return;
  if (copies.reduce((count, note) => count + (note.connections?.length ?? 0), 0) > 100) {
    failure.value = "selection_too_large";
    return;
  }
  finish();
  const at = context();
  const valid = () => at.epoch === board.epoch && at.session_id === board.session?.id;
  const minX = Math.min(...copies.map((note) => note.canvas.x ?? 0));
  const minY = Math.min(...copies.map((note) => note.canvas.y ?? 0));
  const ids = copies.map((copy) =>
    notes.add(
      {
        ...copy.canvas,
        x: point.x + (copy.canvas.x ?? 0) - minX,
        y: point.y + (copy.canvas.y ?? 0) - minY,
      },
      copy.canvas.color,
      copy,
    ),
  );
  history.push(group(ids.map((id) => presenceCommand(id, true))));
  select(ids);
  canvas.value?.focus();
  await history.run(async () => {
    for (const id of ids) {
      if (!valid()) return;
      await notes.settle(id);
    }
  });
  if (valid() && ids.every((id) => notes.find(id))) await copyConnections(copies, ids);
}
async function copyConnections(copies: NoteCopy[], ids: number[]) {
  const changes: ConnectionChange[] = copies.flatMap((copy, source) =>
    (copy.connections ?? []).map((target) => ({
      source_id: ids[source],
      target_id: ids[target],
      connected: true,
      direction: copy.directions?.[target] ?? "forward",
    })),
  );
  // The notes' presence command already owns undo for this paste. Preserve the
  // same retryable connection batch without adding a second history entry.
  await connections.change(changes, { recordHistory: false });
}
function duplicate(ids: number[]) {
  const originals = selectedNotes(ids);
  if (!originals.length) return;
  const copies = originals.map(
    (note): NoteCopy => ({
      title: note.title,
      body: note.body,
      canvas: {
        ...notePosition(note),
        width: note.canvas?.width ?? 280,
        color: note.canvas?.color,
        shape: note.canvas?.shape ?? "rectangle",
      },
      connections: (note.canvas?.links ?? [])
        .map((id) => originals.findIndex((n) => n.id === id))
        .filter((index) => index >= 0),
      directions: Object.fromEntries(
        (note.canvas?.links ?? []).flatMap((id) => {
          const index = originals.findIndex((other) => other.id === id);
          return index < 0 ? [] : [[index, note.canvas?.link_directions?.[id] ?? "forward"]];
        }),
      ),
    }),
  );
  void insert(copies, {
    x: Math.min(...originals.map((note) => notePosition(note).x)) + 40,
    y: Math.min(...originals.map((note) => notePosition(note).y)) + 40,
  });
}
function paste(event: ClipboardEvent, point: Point) {
  if (!canCreate.value || mutationBusy.value) return;
  const copies = readNotes(event);
  if (copies?.length) {
    event.preventDefault();
    void insert(copies, point);
  }
}
function undo() {
  if (connections.pending.value && !history.busy.value) return;
  finish();
  void history.undo();
  canvas.value?.focus();
}
function redo() {
  if (connections.pending.value && !history.busy.value) return;
  finish();
  void history.redo();
  canvas.value?.focus();
}
async function startSession() {
  if (starting.value) return;
  starting.value = true;
  const reply = await request<{ id: number }>("create_session", {
    title: t("ideation.canvas.untitledSession"),
    preset: "openPreset",
  });
  if (reply.status === "ok") await request("open_session", { id: reply.value.id });
  else failure.value = reply.status === "error" ? reply.code : "unavailable";
  if (reply.status === "error" && reply.code === "offline")
    failure.value = "session_creation_unknown";
  else starting.value = false;
}
watch(
  () => board.session?.id,
  () => {
    reset("navigation");
    state.value = "all";
    list.value = false;
    historyGeneration++;
    focusStop?.();
    startedRound.value = null;
    knownRoundIds = null;
    startingRound = false;
  },
  { immediate: true },
);
watch(
  () => board.can_edit,
  (now, before) => {
    if (before && !now) {
      editing.value = null;
      editingBefore = undefined;
      cancelHistoryPreparation?.();
      history.clear();
      connections.reset();
      selectedIds.value = selectedIds.value.filter((id) => notes.find(id));
    }
  },
);
watch(
  () => rounds.value.map((round) => `${round.id}:${round.private}`).join(),
  () => {
    cancelHistoryPreparation?.();
    history.clear();
    connections.reset();
    if (current.value && current.value.author_id !== board.current_user_id) select(null);
  },
);
function rememberLoadedIdeas() {
  for (const idea of board.ideas) {
    if (oldestLoadedIdeaId === null || idea.id < oldestLoadedIdeaId) oldestLoadedIdeaId = idea.id;
  }
}
watch(() => board.ideas, rememberLoadedIdeas, { immediate: true });
watch(visible, (notes) => {
  const ids = new Set(notes.map((note) => note.id));
  const next = selectedIds.value.filter((id) => ids.has(id));
  if (next.length !== selectedIds.value.length) select(next);
});
// Deep links from the session tree: a round to scroll to, or the parked list.
// They arrive as a prop so the first render honours them; `seq` re-applies a
// repeated link.
watch(
  () => linked?.seq,
  () => {
    if (!linked?.seq) return;
    if (linked.round_id) focusRound(linked.round_id);
    if (linked.view === "later") {
      finish();
      state.value = "parked";
      list.value = true;
    }
  },
  { immediate: true },
);
onUnmounted(() => {
  cancelHistoryPreparation?.();
  focusStop?.();
  history.clear();
  connections.reset();
});
</script>
<template>
  <div
    id="brainstorming-workspace"
    :aria-busy="board.loading"
    :data-persisted-note-count="board.ideas.length"
    class="relative flex h-full min-h-0 flex-col"
  >
    <div
      v-if="board.error || failure || !online"
      role="alert"
      class="z-40 flex items-center justify-between gap-3 border-b bg-destructive/10 px-4 py-2 text-xs"
    >
      <span>{{ error(board.error || failure || "offline") }}</span
      ><Button
        v-if="connections.pending.value"
        variant="ghost"
        size="sm"
        :disabled="history.busy.value"
        @click="connections.retry"
        >{{ t("ideation.retry") }}</Button
      >
      <Button v-else variant="ghost" size="sm" @click="refresh">{{ t("ideation.refresh") }}</Button>
    </div>
    <div
      v-if="board.session?.status === 'open' && !board.session.contributions_open"
      id="brainstorming-contributions-closed"
      role="status"
      class="border-b bg-muted/30 px-4 py-2 text-xs text-muted-foreground"
    >
      {{ t(writable ? "ideation.timer.closedHelp" : "ideation.timer.contributionsClosed") }}
    </div>
    <details
      v-if="resetNotice && notes.drafts.recovered.value.length"
      class="z-40 border-b bg-background p-3 text-xs"
    >
      <summary>{{ t("ideation.recoveredDrafts") }}</summary>
      <div class="max-h-60 space-y-2 overflow-auto py-3">
        <p>{{ t("ideation.recoveredDraftsHelp") }}</p>
        <IdeaEditor
          v-for="(item, index) in notes.drafts.recovered.value"
          :key="index"
          :value="item.body"
          readonly
          :label="t('ideation.recoveredDrafts')"
        />
      </div>
    </details>
    <DashboardContent
      v-if="!board.session"
      :title="t('ideation.title')"
      :subtitle="
        t(board.session_missing ? 'ideation.sessionMissingHelp' : 'ideation.canvas.dashboardHelp')
      "
      :is-empty="!board.sessions.length"
      :empty-message="t('ideation.noSessions')"
      :empty-icon="StickyNote"
    >
      <div class="space-y-2">
        <LiveLink
          v-for="session in board.sessions.filter((s) => !s.deleted_at)"
          :key="session.id"
          :to="`${baseUrl}/${session.id}`"
          mode="patch"
          class="flex items-center gap-3 rounded-lg border p-4 transition-colors hover:bg-accent/40"
          ><StickyNote class="size-5 text-muted-foreground" />
          <div>
            <p class="text-sm font-medium">{{ session.title }}</p>
            <p v-if="session.objective" class="text-xs text-muted-foreground">
              {{ session.objective }}
            </p>
          </div></LiveLink
        >
      </div>
      <template #supplementary
        ><Button v-if="board.can_edit" :disabled="starting" @click="startSession"
          ><Plus class="size-4" />{{ t("ideation.newSession") }}</Button
        ></template
      >
    </DashboardContent>
    <div v-if="board.session" class="relative min-h-0 flex-1">
      <BrainstormingCanvas
        v-show="!list"
        ref="canvas"
        :key="`${board.epoch}:${board.session.id}`"
        :notes="visible"
        :group-state="{
          groups: groups.groups.value,
          selectedId: groups.selected.value,
          save: groups.save,
          move: groups.move,
        }"
        :selected-ids="selectedIds"
        :history-state="{
          canUndo: history.canUndo.value,
          canRedo: history.canRedo.value,
          busy: mutationBusy,
        }"
        :editing-id="editing"
        :permissions="{
          edit: writable,
          create: canCreate,
          comment: board.can_edit && online,
        }"
        :collaboration="{
          context: context(),
          cursors: !activeRoundPrivate,
          comments,
          baseUrl,
          userId: board.current_user_id,
        }"
        :members="board.members"
        :statuses="statuses"
        :bands="{
          rounds,
          offsets: bandOffsets,
          canManage: board.can_manage,
          pending: roundPending,
          timer: board.session
            ? {
                session: board.session,
                epoch: board.epoch,
                timer: board.timer,
                canEdit: board.can_edit,
              }
            : null,
          counts: roundCounts,
          masked,
        }"
        @bands="measuredBands = $event"
        @update-privacy="updatePrivacy"
        @reveal="revealRound"
        @new-round="newRound"
        @close-round="closeRound"
        @update-prompt="updatePrompt"
        @comment="createComment"
        @add="add"
        @select="select"
        @select-group="groups.choose"
        @create-group="createGroup"
        @separate-group="separateGroup"
        @delete-group="groups.remove"
        @reveal-group="revealGroup"
        @propose-group-decision="proposeDecision"
        @edit="edit"
        @change="notes.change"
        @change-state="(id, state) => changeState(state, id)"
        @bring-forward="bringForward"
        @finish="finish"
        @move="move"
        @connect="connect"
        @connect-selection="connectSelection"
        @change-connections="changeConnections"
        @add-connected="addConnected"
        @remove="remove"
        @duplicate="duplicate"
        @copy="copy"
        @cut="cut"
        @paste="paste"
        @undo="undo"
        @redo="redo"
        @list="list = true"
      >
        <template #session="{ compact }">
          <Button
            id="brainstorming-session-references"
            variant="ghost"
            size="sm"
            :disabled="!online"
            @click="useReferences(null)"
            :aria-label="t('brainstormingReferences.title')"
            ><Link2 class="size-4" /><span v-if="!compact">{{
              t("brainstormingReferences.title")
            }}</span></Button
          >
        </template>
        <template #selection="{ connectionTools }">
          <div
            v-if="current"
            class="surface-panel flex items-center gap-1 overflow-x-auto p-1.5 whitespace-nowrap"
          >
            <ToolbarTooltip
              v-if="writable"
              :label="
                t(
                  decisionSelection
                    ? 'brainstormingDecisions.propose'
                    : 'brainstormingDecisions.sharedSourcesOnly',
                )
              "
              ><Button
                id="brainstorming-propose-decision"
                variant="ghost"
                size="icon-sm"
                :disabled="!decisionSelection || !online || mutationBusy || preparingDecision"
                :aria-label="t('brainstormingDecisions.propose')"
                @click="proposeDecision()"
                ><ListChecks class="size-4" /></Button
            ></ToolbarTooltip>
            <ToolbarTooltip
              v-if="current.visibility === 'shared' && current.published_revision"
              :label="t('brainstormingReferences.ideaReferences')"
              ><Button
                id="brainstorming-idea-references"
                variant="ghost"
                size="icon-sm"
                :disabled="!online"
                :aria-label="t('brainstormingReferences.ideaReferences')"
                @click="useReferences(current.id)"
                ><Link2 class="size-4"
              /></Button>
            </ToolbarTooltip>

            <GroupSelectionTools
              v-if="writable"
              :notes="selectedNotes(selectedIds)"
              :groups="groups.groups.value"
              :private-round="selectionPrivate"
              :busy="mutationBusy"
              @create="createGroup()"
              @membership="groupMembership"
            />
            <CanvasConnectionTools v-if="writable" v-bind="connectionTools" />
            <CanvasShapePicker
              v-if="writable"
              :value="selectionShape"
              :count="selectedIds.length"
              :disabled="mutationBusy"
              @change="shape"
              @close="canvas?.focusEditing()"
            />
            <template v-if="writable"
              ><Popover
                ><ToolbarTooltip :label="t('ideation.canvas.color')"
                  ><PopoverTrigger as-child
                    ><button
                      ref="colorTrigger"
                      type="button"
                      class="toolbar-btn"
                      :aria-label="t('ideation.canvas.color')"
                    >
                      <Ban
                        v-if="noteColor(current.canvas?.color) === 'none'"
                        class="size-4 text-muted-foreground"
                      /><span
                        v-else
                        class="size-4 rounded-full border border-foreground/10"
                        :style="{
                          background: noteSwatch(current.canvas?.color, current.canvas?.shape),
                        }"
                      /></button></PopoverTrigger
                ></ToolbarTooltip>
                <PopoverContent :reference="colorTrigger" class="flex w-auto gap-2 p-2"
                  ><button
                    v-for="id in NOTE_COLOR_IDS"
                    :key="id"
                    type="button"
                    class="flex size-6 items-center justify-center rounded-full border border-black/10 ring-offset-2 ring-offset-background focus-visible:ring-2 focus-visible:ring-ring aria-pressed:ring-2 aria-pressed:ring-ring"
                    :style="
                      id === 'none'
                        ? undefined
                        : { background: noteSwatch(id, current.canvas?.shape) }
                    "
                    :aria-label="t(`ideation.canvas.colors.${id}`)"
                    :aria-pressed="noteColor(current.canvas?.color) === id"
                    @click="color(id)"
                  >
                    <Ban
                      v-if="id === 'none'"
                      class="size-3.5 text-muted-foreground"
                    /></button></PopoverContent></Popover
            ></template>
            <Popover v-if="current.canvas?.links?.length"
              ><ToolbarTooltip :label="t('ideation.canvas.connections')"
                ><PopoverTrigger as-child
                  ><button
                    ref="linksTrigger"
                    type="button"
                    class="toolbar-btn"
                    :aria-label="t('ideation.canvas.connections')"
                  >
                    <Unplug class="size-3.5" /></button></PopoverTrigger
              ></ToolbarTooltip>
              <PopoverContent :reference="linksTrigger" class="w-64 space-y-1"
                ><button
                  v-for="id in current.canvas.links"
                  :key="id"
                  type="button"
                  class="flex w-full items-center gap-2 rounded p-2 text-left text-xs hover:bg-accent"
                  :disabled="!writable"
                  @click="connect(current!.id, id, false)"
                >
                  <Unplug class="size-3 shrink-0" /><span class="truncate">{{
                    notes.notes.value.find((n) => n.id === id)?.preview ||
                    t("ideation.canvas.connection")
                  }}</span>
                </button></PopoverContent
              ></Popover
            >
            <template v-if="own && writable && current.id > 0"
              ><ToolbarTooltip
                :label="t(current.state === 'active' ? 'ideation.parked' : 'ideation.bringBack')"
                ><button
                  type="button"
                  class="toolbar-btn"
                  :aria-label="
                    t(current.state === 'active' ? 'ideation.parked' : 'ideation.bringBack')
                  "
                  @click="changeState(current.state === 'active' ? 'parked' : 'active')"
                >
                  <Archive v-if="current.state === 'active'" class="size-3.5" /><RotateCcw
                    v-else
                    class="size-3.5"
                  /></button></ToolbarTooltip
            ></template>
            <ToolbarTooltip
              v-if="own && writable && current.id > 0 && current.state !== 'discarded'"
              :label="t('ideation.canvas.discard')"
              ><button
                type="button"
                class="toolbar-btn"
                :aria-label="t('ideation.canvas.discard')"
                @click="changeState('discarded')"
              >
                <CircleX class="size-3.5" /></button
            ></ToolbarTooltip>
          </div>
          <div
            v-if="selected !== null && (notes.errors.get(selected) || draft?.error)"
            role="alert"
            class="surface-panel mt-2 flex max-w-sm items-center gap-2 whitespace-normal p-2 text-xs"
          >
            <span>{{ error(notes.errors.get(selected) || draft?.error || "unavailable") }}</span
            ><Button v-if="writable" size="sm" variant="ghost" @click="notes.retry(selected!)">{{
              t("ideation.retry")
            }}</Button>
          </div>
          <div v-if="draft?.conflict" class="surface-panel mt-2 w-80 space-y-2 p-3 text-xs">
            <p>{{ t("ideation.conflictHelp") }}</p>
            <IdeaEditor
              :value="draft.conflict.current.body"
              readonly
              :label="t('ideation.currentVersion')"
            /><Button size="sm" variant="ghost" @click="notes.drafts.resolve(selected!, false)">{{
              t("ideation.useCurrent")
            }}</Button
            ><Button v-if="writable" size="sm" @click="notes.drafts.resolve(selected!, true)">{{
              t("ideation.saveMine")
            }}</Button>
          </div>
        </template>
      </BrainstormingCanvas>
      <RoundStartedToast
        v-if="!list"
        :round="startedRound"
        @go="goToStartedRound"
        @dismiss="startedRound = null"
      />
      <div v-if="list" class="h-full overflow-auto p-4 lg:p-6">
        <DashboardContent
          :title="board.session.title"
          :subtitle="board.session.objective ?? undefined"
          ><div class="flex items-center gap-2">
            <Button variant="outline" size="sm" @click="list = false"
              ><LayoutDashboard class="size-4" />{{ t("ideation.canvas.back") }}</Button
            ><BoardSelect
              v-model="state"
              :label="t('ideation.state')"
              :options="options(['active', 'parked', 'discarded', 'all'])"
            /><Button
              v-if="canCreate"
              id="brainstorming-list-new"
              size="sm"
              @click="
                list = false;
                add(landing(0), board.active_round?.id);
              "
              ><Plus class="size-4" />{{ t("ideation.newIdea") }}</Button
            >
          </div>
          <div class="divide-y rounded-lg border">
            <div
              v-for="note in listed"
              :id="`canvas-list-note-${note.id}`"
              :key="note.id"
              class="flex items-start gap-3 p-4 hover:bg-accent/30"
            >
              <button
                type="button"
                class="flex min-w-0 flex-1 items-start gap-3 text-left"
                @click="locate(note)"
              >
                <StickyNote class="mt-1 size-4 shrink-0 text-muted-foreground" />
                <div>
                  <p v-if="note.title" class="text-sm font-medium">{{ note.title }}</p>
                  <p class="text-sm">{{ note.body.replace(/<[^>]*>/g, " ") }}</p>
                  <p class="mt-2 text-xs text-muted-foreground">
                    {{ member(note.author_id, board.members) }} ·
                    {{ t(`ideation.${note.state}`) }}
                    <span v-if="note.round_id">
                      ·
                      {{
                        rounds.find((round) => round.id === note.round_id)
                          ? t("ideation.rounds.number", {
                              number: rounds.find((round) => round.id === note.round_id)!.number,
                            })
                          : t("ideation.rounds.assigned")
                      }}</span
                    >
                    <span v-if="note.late_contribution"> · {{ t("ideation.rounds.late") }}</span>
                  </p>
                </div>
              </button>
              <Button
                v-if="
                  note.state === 'parked' && canCreate && note.round_id !== board.active_round?.id
                "
                :id="`canvas-list-bring-${note.id}`"
                variant="outline"
                size="sm"
                class="shrink-0"
                @click="bringForward(note.id)"
                ><ArrowDownToLine class="size-4" />{{ t("ideation.bringForward") }}</Button
              >
            </div>
          </div></DashboardContent
        >
      </div>
      <p
        v-if="!writable"
        class="surface-panel pointer-events-none absolute right-3 top-3 px-3 py-2 text-xs text-muted-foreground"
      >
        {{ t(board.session.status === "archived" ? "ideation.archivedHelp" : "ideation.readOnly") }}
      </p>
      <div v-if="board.ideas_next" class="surface-panel absolute right-3 top-3 z-30 p-1">
        <Button
          size="sm"
          variant="ghost"
          @click="request('browse_ideas', { before_id: board.ideas_next })"
          >{{ t("ideation.canvas.more") }}</Button
        >
      </div>
    </div>
  </div>
</template>
