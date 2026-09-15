<script setup lang="ts">
import { computed, nextTick, onMounted, onUnmounted, ref, watch } from "vue";
import { useElementSize } from "@vueuse/core";
import {
  ArrowDownToLine,
  ArrowLeft,
  ArrowLeftRight,
  ArrowRight,
  Bookmark,
  Cable,
  CircleX,
  Hand,
  List,
  Maximize,
  MessageSquarePlus,
  Minus,
  MousePointer2,
  Plus,
  RotateCcw,
  Search,
  StickyNote,
  X,
} from "@lucide/vue";
import {
  ContextMenu,
  ContextMenuTrigger,
  ContextMenuContent,
  ContextMenuItem,
} from "@components/ui/context-menu";
import DockToolButton from "@components/toolbar/DockToolButton.vue";
import ToolbarTooltip from "@components/toolbar/ToolbarTooltip.vue";
import { Input } from "@components/ui/input";
import { Popover, PopoverContent, PopoverTrigger } from "@components/ui/popover";
import CanvasNote from "./CanvasNote.vue";
import CanvasGroup from "./CanvasGroup.vue";
import { groupBounds, groupVisibility, type MemberGeometry } from "../lib/groups";
import CanvasCursors from "./CanvasCursors.vue";
import RoundBar from "./RoundBar.vue";
import { bandAt, bandOffsets, orderRounds, sameOffsets, type BandOffsets } from "../lib/bands";
import { interactivePath, interactiveTarget } from "../lib/interactive";
import { useCanvasViewport, type Point } from "../composables/useCanvasViewport";
import { useCanvasMarquee } from "../composables/useCanvasMarquee";
import { useBoardText } from "../composables/useBoardText";
import { notePosition } from "../lib/placement";
import {
  connectedPlacement,
  connectionEndpoints,
  displayConnections,
  connectionStyleChanges,
  noteContainsPoint,
  readableViewport,
  type ConnectionDirection,
} from "../lib/connectionGeometry";
import type {
  BoardContext,
  CanvasIdea,
  Idea,
  Member,
  IdeaGroup,
  GroupText,
  GroupVersions,
  ConnectionChange,
  LinkDirection,
  Round,
  RoundTimerContext,
  RoundPrivacy,
  MaskedIdea,
  IdeaState,
} from "../types";
import BrainstormingCanvasComments from "../BrainstormingCanvasComments.vue";
import type { BrainstormingCommentsState, BrainstormingCommentTarget } from "../commentTypes";
interface HistoryState {
  canUndo: boolean;
  canRedo: boolean;
  busy: boolean;
}
const {
  notes,
  groupState,
  selectedIds,
  editingId,
  permissions,
  collaboration,
  members,
  statuses,
  historyState,
  bands = {
    rounds: [],
    offsets: new Map(),
    canManage: false,
    pending: false,
    timer: null,
    counts: new Map(),
    masked: [],
  },
} = defineProps<{
  notes: CanvasIdea[];
  groupState?: {
    groups: IdeaGroup[];
    selectedId: number | null;
    save: (id: number, text: GroupText, version: number) => Promise<boolean>;
    move: (id: number, point: Point, expected?: GroupVersions) => Promise<void>;
  };
  selectedIds: number[];
  historyState: HistoryState;
  editingId: number | null;
  permissions: { edit: boolean; create: boolean; comment?: boolean };
  collaboration: {
    context: BoardContext;
    cursors: boolean;
    comments?: BrainstormingCommentsState;
    baseUrl?: string;
    /** Whose notes the context menu may change state for. */
    userId?: number | null;
  };
  members: Member[];
  statuses: { [id: number]: string };
  /** Round bands in canvas order; their headers are drawn in screen space. */
  bands?: {
    rounds: Round[];
    offsets: BandOffsets;
    canManage: boolean;
    pending: boolean;
    timer?: RoundTimerContext | null;
    counts?: Map<number, number>;
    masked?: MaskedIdea[];
  };
}>();
const groups = computed(() => groupState?.groups ?? []);
const selectedGroupId = computed(() => groupState?.selectedId ?? null);
const saveGroup = (id: number, text: GroupText, version: number) =>
  groupState?.save(id, text, version) ?? Promise.resolve(false);
const moveGroup = (id: number, point: Point, expected?: GroupVersions) =>
  groupState?.move(id, point, expected) ?? Promise.resolve();
const canCreate = computed(() => permissions.edit && permissions.create);
const emit = defineEmits<{
  comment: [target: BrainstormingCommentTarget];
  add: [point: Point];
  select: [ids: number[]];
  selectGroup: [id: number | null];
  createGroup: [ids: number[]];
  separateGroup: [id: number];
  deleteGroup: [id: number];
  revealGroup: [id: number];
  proposeGroupDecision: [id: number];
  edit: [id: number];
  change: [id: number, body: string];
  finish: [];
  move: [moves: Array<{ id: number; point: Point }>];
  connect: [source: number, target: number, connected: boolean];
  changeConnections: [changes: ConnectionChange[]];
  connectSelection: [ids: number[], connected: boolean];
  addConnected: [sourceIds: number[], point: Point];
  remove: [ids: number[]];
  duplicate: [ids: number[]];
  undo: [];
  redo: [];
  copy: [event: ClipboardEvent, ids: number[]];
  cut: [event: ClipboardEvent, ids: number[]];
  paste: [event: ClipboardEvent, point: Point];
  list: [];
  newRound: [];
  bands: [offsets: BandOffsets];
  updatePrivacy: [id: number, attrs: RoundPrivacy];
  reveal: [id: number];
  closeRound: [id: number];
  updatePrompt: [id: number, prompt: string];
  changeState: [id: number, state: IdeaState];
  bringForward: [id: number, point: Point];
}>();
const commentTarget = ref<BrainstormingCommentTarget | null>(null);
// The author's own note under the pointer: its states are one right-click away.
const noteTarget = ref<{ id: number; state: IdeaState } | null>(null);
// Any readable note of another round, to bring into the one in progress.
const bringTarget = ref<{ id: number; point: Point } | null>(null);
const canStartRound = computed(() => bands.canManage && permissions.edit);
// The context menu serves comments, a note's states for its author and, for
// the facilitator, the next round.
function prepareComment(event: MouseEvent) {
  commentTarget.value = null;
  noteTarget.value = null;
  bringTarget.value = null;
  const target = event.target instanceof Element ? event.target : null;
  if (
    !target ||
    target.closest('input, textarea, select, [contenteditable="true"], [data-canvas-chrome]')
  ) {
    event.stopPropagation();
    return;
  }
  const source = permissions.comment ? resolveCommentTarget(target) : null;
  commentTarget.value = source
    ? { ...source, position: world(event.clientX, event.clientY) }
    : null;
  noteTarget.value = resolveNoteTarget(target);
  bringTarget.value = resolveBringTarget(target);
  if (!commentTarget.value && !noteTarget.value && !bringTarget.value && !canStartRound.value)
    event.stopPropagation();
}
function resolveNoteTarget(target: Element) {
  const id = Number(target.closest<HTMLElement>("[data-note-id]")?.dataset.noteId);
  const note = notes.find((candidate) => candidate.id === id);
  if (!note || id <= 0 || !permissions.edit || note.author_id !== collaboration.userId) return null;
  return { id, state: note.state };
}
// The copy lands under the lowest content of the band in progress, at the
// original's x, so it never covers what is already there.
function resolveBringTarget(target: Element) {
  const id = Number(target.closest<HTMLElement>("[data-note-id]")?.dataset.noteId);
  const note = notes.find((candidate) => candidate.id === id);
  const active = bands.rounds.find((round) => round.status === "active");
  if (!note || id <= 0 || !canCreate.value || !active || note.round_id === active.id) return null;
  const top = bandTop(active.id)?.top ?? offsetOf(active.id);
  const bottom = contentBottom(active.id);
  const y = (bottom === null ? top : Math.max(top, offsetOf(active.id) + bottom)) + 24;
  return { id, point: { x: position(note).x, y } };
}
function resolveCommentTarget(target: Element) {
  const noteId = Number(target.closest<HTMLElement>("[data-note-id]")?.dataset.noteId);
  const groupId = Number(target.closest<HTMLElement>("[data-group-id]")?.dataset.groupId);
  if (noteId) return ideaCommentTarget(noteId);
  if (groupId) {
    return groups.value.some((group) => group.id === groupId) ? { ideaId: null, groupId } : null;
  }
  return { ideaId: null, groupId: null };
}
function ideaCommentTarget(noteId: number) {
  const note = notes.find((note) => note.id === noteId);
  return note?.visibility === "shared" && note.published_revision
    ? { ideaId: noteId, groupId: null }
    : null;
}

const root = ref<HTMLElement | null>(null);
// A header rests flush under the app bar: jumping to a round brings its header
// here, scrolling past it pins the header here, and the viewport never scrolls
// above the first header. The search and references controls share that row;
// while a header is anywhere in the chrome's zone it makes room for them.
const HEADER_REST = 0;
const CHROME_ZONE = 60;
// The header row in screen pixels: the bar's min height plus its line.
const HEADER_HEIGHT = 42;
// A group frame rises above its members; over the first band that is above the
// canvas top, and the view may go that far up so its header stays reachable.
const overhang = ref(0);
const { view, space, transform, world, zoomTo, wheel, fit } = useCanvasViewport(root, {
  rest: ({ zoom }) => HEADER_REST + overhang.value * zoom,
});
const chromePanel = ref<HTMLElement | null>(null);
const chromeWidth = ref(0);
const chromeInset = computed(() => 12 + chromeWidth.value + 12);
let chromeObserver: ResizeObserver | undefined;
const { t, member } = useBoardText();
const tool = ref("select"),
  query = ref("");
const searchOpen = ref(false);
const positions = ref(new Map<number, Point>());
const linkSource = ref<number | null>(null);
const ghost = ref<Point | null>(null);
const selectedConnectionKey = ref<string | null>(null);
const connectionTarget = ref<number | null>(null);
const dragConnectionSource = ref<number | null>(null);
const connectionDirections = [
  { value: "none", icon: Minus },
  { value: "forward", icon: ArrowRight },
  { value: "backward", icon: ArrowLeft },
  { value: "both", icon: ArrowLeftRight },
] as const;
interface CanvasDrag {
  pointer: number;
  id: number | null;
  groupId?: number;
  groupVersions?: GroupVersions;
  start: Point;
  origin: Point;
  notes: Array<{ id: number; origin: Point }>;
  moved: boolean;
  capture: HTMLElement | null;
}
let drag: CanvasDrag | null = null;

function position(note: Idea): Point {
  return positions.value.get(note.id) ?? notePosition(note);
}
const noteHeights = ref(new Map<number, number>());
const noteWidths = ref(new Map<number, number>());
const marquee = useCanvasMarquee({
  root,
  world,
  bounds: () =>
    notes.map((note) => ({
      id: note.id,
      ...position(note),
      width: noteWidths.value.get(note.id) ?? note.canvas?.width ?? 280,
      height: noteHeights.value.get(note.id) ?? 96,
    })),
  selection: () => ({ ids: visibleSelection.value, groupId: selectedGroupId.value }),
  select: ({ ids, groupId }) => {
    emit("selectGroup", groups.value.some((group) => group.id === groupId) ? groupId : null);
    emit("select", ids);
  },
});
const { active: selectingArea, area: selectionArea } = marquee;
const groupAnchors = ref(new Map<number, Point>());
const groupHeights = ref(new Map<number, number>());
const openSyntheses = ref(new Set<number>());
const layouts = computed(() => {
  // Loaded note geometry is shared by every frame; only unseen members differ.
  const visibleIds = notes.map((note) => note.id);
  const loaded: MemberGeometry[] = notes.map((note) => ({
    id: note.id,
    canvas: {
      ...note.canvas,
      ...position(note),
      width: noteWidths.value.get(note.id) ?? note.canvas?.width,
    },
    height: noteHeights.value.get(note.id),
  }));
  return groups.value.map((group) => {
    const anchor = groupAnchors.value.get(group.id);
    const projected = {
      ...group,
      synthesis: group.synthesis || (openSyntheses.value.has(group.id) ? " " : null),
      canvas: { ...group.canvas, ...anchor },
    };
    const unseen = group.members
      .filter((member) => !visibleIds.includes(member.idea_id))
      .map((member) => ({
        id: member.idea_id,
        canvas: {
          ...member.canvas,
          width: noteWidths.value.get(member.idea_id) ?? member.canvas.width,
        },
        height: noteHeights.value.get(member.idea_id),
      }));
    const geometry = unseen.length ? [...loaded, ...unseen] : loaded;
    return {
      group,
      visibility: groupVisibility(group, visibleIds),
      bounds: groupBounds(projected, geometry, groupHeights.value.get(group.id)),
    };
  });
});
let noteObserver: ResizeObserver | undefined;
function measureNotes() {
  noteObserver?.disconnect();
  for (const element of root.value?.querySelectorAll<HTMLElement>("[data-note-id]") ?? []) {
    const id = Number(element.dataset.noteId);
    const note = element.querySelector<HTMLElement>(`#canvas-note-${id}`);
    if (note) recordNoteSize(note, id);
  }
}
function recordNoteSize(note: HTMLElement, id: number) {
  const canvasWidth = notes.find((note) => note.id === id)?.canvas?.width ?? 280;
  noteHeights.value.set(id, note.offsetHeight || 96);
  noteWidths.value.set(id, note.offsetWidth || canvasWidth);
  noteObserver?.observe(note);
}
function bounds() {
  return notes.map(noteBounds);
}
function fitAll() {
  fit([...bounds(), ...layouts.value.map((layout) => layout.bounds)]);
}
const orderedRounds = computed(() => orderRounds(bands.rounds));
const multiRound = computed(() => orderedRounds.value.length > 1);
const lastRound = computed(() => orderedRounds.value[orderedRounds.value.length - 1] ?? null);
function offsetOf(roundId: number | null | undefined): number {
  return roundId == null ? 0 : (bands.offsets.get(roundId) ?? 0);
}
// A band is as tall as what it holds. Its lowest note or frame is measured on
// live positions, so a drag past the bottom grows the band as it goes.
function contentBottom(roundId: number): number | null {
  const top = offsetOf(roundId);
  const bottoms = notes
    .filter((note) => note.round_id === roundId)
    .map((note) => position(note).y + (noteHeights.value.get(note.id) ?? 96) - top);
  for (const layout of layouts.value) {
    if (layout.group.members[0]?.round_id !== roundId) continue;
    bottoms.push(layout.bounds.y + layout.bounds.height - top);
  }
  for (const item of bands.masked ?? []) {
    if (item.round_id === roundId) bottoms.push((item.canvas.y ?? 0) + MASKED_HEIGHT - top);
  }
  return bottoms.length ? Math.max(...bottoms) : null;
}
watch(
  layouts,
  (list) => {
    overhang.value = Math.max(0, ...list.map((layout) => -layout.bounds.y));
  },
  { immediate: true },
);
const bandLayout = computed(() => bandOffsets(bands.rounds, contentBottom));
// A jump lands before every note has been measured. While the layout settles,
// the header goes back to its rest line, until the person moves the view.
let settling: { roundId: number; until: number } | null = null;
watch(
  bandLayout,
  (next) => {
    if (!sameOffsets(next, bands.offsets)) emit("bands", next);
    if (settling && performance.now() <= settling.until)
      view.y = HEADER_REST - (next.get(settling.roundId) ?? offsetOf(settling.roundId)) * view.zoom;
    else settling = null;
  },
  { immediate: true },
);
function canvasHeaderTop(round: Round) {
  return view.y + offsetOf(round.id) * view.zoom;
}
// While the viewport is inside a band, its header stays pinned at the rest
// line; the next band's header pushes it out as it arrives.
function headerTop(round: Round) {
  const own = canvasHeaderTop(round);
  if (own >= HEADER_REST) return own;
  return Math.min(HEADER_REST, nextHeaderTop(round) - HEADER_HEIGHT);
}
function headerPinned(round: Round) {
  return canvasHeaderTop(round) < HEADER_REST;
}
function headerUnderChrome(round: Round) {
  return canvasHeaderTop(round) < CHROME_ZONE;
}
// With a header on the chrome row, the search and references sit in that row
// as plain controls; the panel keeps its own frame only over bare canvas.
const chromeFramed = computed(
  () => !orderedRounds.value.some((round) => headerShown(round) && headerUnderChrome(round)),
);
function nextHeaderTop(round: Round) {
  const rounds = orderedRounds.value;
  const index = rounds.findIndex((candidate) => candidate.id === round.id);
  for (const candidate of rounds.slice(index + 1)) {
    if (headerShown(candidate)) return canvasHeaderTop(candidate);
  }
  return Infinity;
}
// Bring a band's header to its rest line, keeping zoom and x. The freshly
// measured layout already knows a round the props have not yet.
function scrollToRound(round: Round) {
  settling = { roundId: round.id, until: performance.now() + 1500 };
  view.y = HEADER_REST - (bandLayout.value.get(round.id) ?? offsetOf(round.id)) * view.zoom;
}
// A session with several rounds opens on the one in progress; the rest fit everything.
function openView() {
  // A deep link may already have asked for a round; the default view yields to it.
  if (settling) return;
  const active = orderedRounds.value.find((round) => round.status === "active");
  if (multiRound.value && active) scrollToRound(active);
  else fitAll();
}
// The header row a band keeps free under its offset, in canvas units.
const HEADER_STRIP = 44;
// Placeholders share one height: what hides in a private round has no measured card.
const MASKED_HEIGHT = 96;
// A single, unnamed round has no header to show, except while its facilitator
// works in it or its clock runs: participants consult the countdown there.
const clockShown = computed(() => {
  const status = bands.timer?.timer?.status;
  return status === "running" || status === "paused" || status === "elapsed";
});
function headerShown(round: Round) {
  return (
    multiRound.value ||
    !!round.prompt ||
    (round.status === "active" && (bands.canManage || clockShown.value))
  );
}
// Where a note of this round may start: under its header. Bands grow with
// their content, so nothing bounds them below.
function bandTop(roundId: number | null): { round: Round; top: number } | null {
  if (roundId == null) return null;
  const round = orderedRounds.value.find((candidate) => candidate.id === roundId);
  if (!round) return null;
  return { round, top: offsetOf(round.id) + (headerShown(round) ? HEADER_STRIP : 0) };
}
// Which header lines a dragged note is pressing against.
const contact = ref(new Set<number>());
// Notes never rise above their header. A multi-selection stops as a whole when
// any of its notes touches its line; the delta comes back clamped in canvas units.
function clampDelta(moving: Array<{ id: number; origin: Point }>, dy: number): number {
  const reaches = moving.flatMap((entry) => {
    const note = notes.find((candidate) => candidate.id === entry.id);
    const band = note ? bandTop(note.round_id) : null;
    return band ? [{ min: band.top - entry.origin.y, roundId: band.round.id }] : [];
  });
  const low = Math.max(-Infinity, ...reaches.map((reach) => reach.min));
  const clamped = Math.max(dy, low);
  // Only the header that actually stops the movement lights up.
  const blocking = reaches.filter((reach) => reach.min === low).map((reach) => reach.roundId);
  contact.value = clamped === dy ? new Set() : new Set(blocking);
  return clamped;
}
// Keep a point under the header of the round it belongs to.
function clampPoint(point: Point, roundId: number | null): Point {
  const band = bandTop(roundId);
  return band ? { x: point.x, y: Math.max(point.y, band.top) } : point;
}
// Where a new note goes: the band under the point decides the round, and the
// note starts under that round's header, never above it.
function placed(point: Point): Point {
  return clampPoint(point, bandAt(orderedRounds.value, bands.offsets, point.y));
}
function center(note: Idea) {
  const rect = noteBounds(note);
  view.x = view.width / 2 - (rect.x + rect.width / 2) * view.zoom;
  view.y = view.height / 2 - (rect.y + rect.height / 2) * view.zoom;
}
function noteBounds(note: Idea) {
  return {
    shape: note.canvas?.shape,
    ...position(note),
    width: noteWidths.value.get(note.id) ?? note.canvas?.width ?? 280,
    height: noteHeights.value.get(note.id) ?? 96,
  };
}
async function revealNote(note: Idea) {
  await nextTick();
  measureNotes();
  Object.assign(view, readableViewport(noteBounds(note), view));
}
function focus() {
  root.value?.focus({ preventScroll: true });
}
function summaryAnchor(id: number): Point | undefined {
  const frame = layouts.value.find((layout) => layout.group.id === id)?.bounds;
  return frame
    ? { x: frame.x + frame.synthesisX - 28, y: frame.y + frame.synthesisY - 64 }
    : undefined;
}
async function focusEditing() {
  await nextTick();
  measureNotes();
  const editor =
    editingId === null
      ? null
      : root.value?.querySelector<HTMLElement>(`#canvas-note-${editingId} [contenteditable=true]`);
  if (editor) editor.focus({ preventScroll: true });
  else focus();
}
defineExpose({ center, fitAll, focus, focusEditing, summaryAnchor, revealNote, scrollToRound });
const visibleSelection = computed(() =>
  selectedIds.filter((id) => notes.some((note) => note.id === id)),
);
const selectedId = computed(() => selectedIds[0] ?? null);
const selectionToolbar = ref<HTMLElement | null>(null);
const { width: selectionToolbarWidth, height: selectionToolbarHeight } =
  useElementSize(selectionToolbar);
const selectionToolbarPosition = computed(() => {
  const note = notes.find((note) => note.id === selectedId.value);
  if (!note) return {};
  const bounds = noteBounds(note);
  const width = selectionToolbarWidth.value || 320;
  const height = selectionToolbarHeight.value || 44;
  const x = view.x + (bounds.x + bounds.width / 2) * view.zoom - width / 2;
  const above = view.y + bounds.y * view.zoom - height - 12;
  const y = above >= 64 ? above : view.y + (bounds.y + bounds.height) * view.zoom + 12;
  return {
    left: `${Math.max(8, Math.min(view.width - width - 8, x))}px`,
    top: `${Math.max(64, Math.min(view.height - height - 80, y))}px`,
  };
});
function connectionWriteBlocked() {
  return (
    !permissions.edit ||
    historyState.busy ||
    drag !== null ||
    selectingArea.value ||
    groupNudge !== null
  );
}
function connectSelection(connected: boolean) {
  if (connectionWriteBlocked() || visibleSelection.value.length < 2) return;
  emit("finish");
  tool.value = "select";
  linkSource.value = null;
  emit("connectSelection", [...visibleSelection.value], connected);
  focus();
}
function addConnected(direction: ConnectionDirection) {
  if (connectionWriteBlocked() || !canCreate.value || !visibleSelection.value.length) return;
  const selected = notes.filter((note) => visibleSelection.value.includes(note.id));
  const obstacles = [...notes.map(noteBounds), ...layouts.value.map((layout) => layout.bounds)];
  const placed = connectedPlacement(selected.map(noteBounds), obstacles, direction);
  const point = placed ? clampPoint(placed, selected[0]?.round_id ?? null) : placed;
  if (!point) return;
  emit("finish");
  tool.value = "select";
  linkSource.value = null;
  emit("addConnected", [...visibleSelection.value], point);
}
const connectionTools = computed(() => ({
  selection: visibleSelection.value.map((id) => {
    const note = notes.find((note) => note.id === id)!;
    return {
      id,
      label:
        note.title ||
        note.preview ||
        note.body.replace(/<[^>]*>/g, " ").trim() ||
        t("ideation.untitled"),
    };
  }),
  hasConnections: notes.some(
    (note) =>
      visibleSelection.value.includes(note.id) &&
      note.canvas?.links?.some((id) => visibleSelection.value.includes(id)),
  ),
  canCreate: canCreate.value,
  busy: historyState.busy,
  onConnect: () => connectSelection(true),
  onDisconnect: () => connectSelection(false),
  onCreate: addConnected,
}));
const matches = computed(() =>
  notes.filter((n) =>
    `${n.title ?? ""} ${n.body.replace(/<[^>]*>/g, " ")}`
      .toLocaleLowerCase()
      .includes(query.value.toLocaleLowerCase()),
  ),
);
const links = computed(() =>
  displayConnections(notes).flatMap((connection) => {
    const source = notes.find((note) => note.id === connection.source)!;
    const target = notes.find((note) => note.id === connection.target)!;
    const endpoints = connectionEndpoints(noteBounds(source), noteBounds(target), 4 / view.zoom);
    return endpoints ? [{ ...connection, ...endpoints }] : [];
  }),
);
const selectedConnection = computed(() =>
  links.value.find((link) => link.key === selectedConnectionKey.value),
);
const previewConnection = computed(() => {
  const sourceId = dragConnectionSource.value ?? linkSource.value;
  const source = notes.find((note) => note.id === sourceId);
  if (!source || !ghost.value) return null;
  const target = notes.find((note) => note.id === connectionTarget.value);
  const sourceBounds = noteBounds(source);
  if (dragConnectionSource.value !== null && drag) Object.assign(sourceBounds, drag.origin);
  const targetBounds = target ? noteBounds(target) : { ...ghost.value, width: 1, height: 1 };
  return connectionEndpoints(sourceBounds, targetBounds, 4 / view.zoom);
});
function noteLabel(id: number) {
  const note = notes.find((note) => note.id === id);
  return (
    note?.title ||
    note?.preview ||
    note?.body.replace(/<[^>]*>/g, " ").trim() ||
    t("ideation.untitled")
  );
}
function selectConnection(key: string) {
  if (historyState.busy) return;
  emit("finish");
  emit("select", []);
  emit("selectGroup", null);
  selectedConnectionKey.value = key;
  tool.value = "select";
  linkSource.value = null;
  connectionTarget.value = null;
  focus();
}
function changeConnectionDirection(direction: LinkDirection) {
  const connection = selectedConnection.value;
  if (!connection || connectionWriteBlocked() || connection.direction === direction) return;
  emit("changeConnections", connectionStyleChanges(connection, direction));
  focus();
}
function removeConnection() {
  const connection = selectedConnection.value;
  if (!connection || connectionWriteBlocked()) return;
  emit(
    "changeConnections",
    connection.edges.map((edge) => ({ ...edge, connected: false })),
  );
  selectedConnectionKey.value = null;
  focus();
}
function connectionTargetAt(point: Point, sourceId: number): number | null {
  // Pointer capture keeps event.target on the dragged note, so hit-test world geometry.
  for (const note of [...notes].reverse()) {
    if (note.id === sourceId) continue;
    if (noteContainsPoint(noteBounds(note), point)) return note.id;
  }
  return null;
}
function chooseTool(value: string) {
  marquee.cancel();
  emit("finish");
  tool.value = value;
  selectedConnectionKey.value = null;
  connectionTarget.value = null;
  linkSource.value = null;
  root.value?.focus();
}
function selectionForNote(id: number, shift: boolean): number[] {
  const included = visibleSelection.value.includes(id);
  if (shift) {
    if (included) return visibleSelection.value.filter((selected) => selected !== id);
    return [...visibleSelection.value, id];
  }
  return included ? [...visibleSelection.value] : [id];
}
function selectNote(id: number, shift: boolean): number[] {
  selectedConnectionKey.value = null;
  if (tool.value === "connect" && permissions.edit) {
    if (linkSource.value !== null && linkSource.value !== id) {
      emit("connect", linkSource.value, id, true);
      linkSource.value = null;
      connectionTarget.value = null;
      tool.value = "select";
    } else linkSource.value = id;
  }
  emit("selectGroup", null);
  const ids = selectionForNote(id, shift);
  emit("select", ids);
  return ids;
}
function pointerDown(event: PointerEvent) {
  if (ignorePointer(event)) return;
  const element = (event.target as HTMLElement).closest<HTMLElement>("[data-note-id]");
  const id = element ? Number(element.dataset.noteId) : null;
  if (panning(event)) {
    event.preventDefault();
    focus();
    beginDrag(event, null, []);
    return;
  }
  if (groupNudge) return settleThenSelect(id, event);
  if (historyState.busy) return;
  if (id === null && tool.value === "select") beginMarquee(event);
  else if (id === null) selectBackground(event);
  else dragSelection(id, event);
}
function ignorePointer(event: PointerEvent) {
  return (
    drag !== null ||
    selectingArea.value ||
    interactiveTarget(event.target) ||
    ![0, 1].includes(event.button)
  );
}
function panning(event: PointerEvent) {
  return space.value || tool.value === "pan" || event.button === 1;
}
// Commit the settling keyboard movement first. Selection proceeds; a drag
// would race the movement's version check, so it waits for the next press.
function settleThenSelect(id: number | null, event: PointerEvent) {
  void flushGroupNudge();
  if (id === null) selectBackground(event);
  else selectNote(id, event.shiftKey);
}
function ensureGroupReadability(id: number, field: "title" | "synthesis") {
  const layout = layouts.value.find((layout) => layout.group.id === id);
  if (!layout) return;
  const frame = layout.bounds;
  const x =
    frame.x + (field === "synthesis" ? frame.synthesisX + 152 : Math.min(frame.width / 2, 300));
  const y = frame.y + (field === "synthesis" ? frame.synthesisY + 156 : 32);
  const outside =
    view.x + x * view.zoom < 100 ||
    view.x + x * view.zoom > view.width - 100 ||
    view.y + y * view.zoom < 80 ||
    view.y + y * view.zoom > view.height - 100;
  if (view.zoom < 0.8 || outside) {
    view.zoom = Math.max(view.zoom, 0.85);
    view.x = view.width / 2 - x * view.zoom;
    view.y = view.height / 2 - y * view.zoom;
  }
}
function selectGroup(id: number | null) {
  selectedConnectionKey.value = null;
  emit("finish");
  emit("select", []);
  emit("selectGroup", id);
}
function groupPointer(event: PointerEvent, group: IdeaGroup, move: boolean) {
  if (ignorePointer(event)) return;
  if (panning(event)) {
    event.preventDefault();
    beginDrag(event, null, []);
    return;
  }
  if (groupNudge) {
    // Commit the settling keyboard movement; keep the click as a selection.
    void flushGroupNudge();
    selectGroup(group.id);
    focus();
    return;
  }
  if (historyState.busy) return;
  if (emptyGroupBody(event, move)) {
    beginMarquee(event, group.id);
    return;
  }
  selectGroup(group.id);
  focus();
  if (
    !move ||
    !permissions.edit ||
    groupVisibility(
      group,
      notes.map((note) => note.id),
    ).partial
  )
    return;
  beginGroupDrag(event, group);
}
function emptyGroupBody(event: PointerEvent, move: boolean) {
  const target = event.target as HTMLElement;
  return !move && tool.value === "select" && !target.closest("[data-group-content]");
}
function beginGroupDrag(event: PointerEvent, group: IdeaGroup) {
  event.preventDefault();
  const capture = (event.currentTarget as HTMLElement | null) ?? root.value;
  drag = {
    pointer: event.pointerId,
    id: null,
    groupId: group.id,
    groupVersions: groupVersions(group),
    start: { x: event.clientX, y: event.clientY },
    origin: { ...group.canvas },
    notes: notes
      .filter((note) => group.idea_ids.includes(note.id))
      .map((note) => ({ id: note.id, origin: position(note) })),
    moved: false,
    capture,
  };
  capture?.setPointerCapture(event.pointerId);
}
function selectBackground(event: PointerEvent) {
  selectedConnectionKey.value = null;
  emit("selectGroup", null);
  emit("finish");
  emit("select", []);
  focus();
  if (tool.value === "note" && canCreate.value) {
    emit("add", placed(world(event.clientX, event.clientY)));
    tool.value = "select";
  }
}
function beginMarquee(event: PointerEvent, clickGroup?: number) {
  selectedConnectionKey.value = null;
  marquee.begin(event, clickGroup);
  emit("finish");
  focus();
}
function dragSelection(id: number, event: PointerEvent) {
  const connecting = tool.value === "connect";
  const ids = selectNote(id, event.shiftKey);
  if (!permissions.edit || connecting || !ids.includes(id)) return;
  event.preventDefault();
  focus();
  beginDrag(event, id, ids);
}
function beginDrag(event: PointerEvent, id: number | null, ids: number[]) {
  const note = notes.find((n) => n.id === id);
  const origin = note ? position(note) : { x: view.x, y: view.y };
  drag = {
    pointer: event.pointerId,
    id,
    start: { x: event.clientX, y: event.clientY },
    origin,
    notes: notes
      .filter((note) => ids.includes(note.id))
      .map((note) => ({ id: note.id, origin: position(note) })),
    moved: false,
    capture:
      id === null
        ? root.value
        : (event.target as HTMLElement).closest<HTMLElement>("[data-note-id]"),
  };
  drag.capture?.setPointerCapture(event.pointerId);
}
function pointerMove(event: PointerEvent) {
  ghost.value = world(event.clientX, event.clientY);
  updateToolTarget(ghost.value);
  if (selectingArea.value) {
    marquee.move(event);
    return;
  }
  if (!drag || drag.pointer !== event.pointerId) return;
  const dx = event.clientX - drag.start.x,
    dy = event.clientY - drag.start.y;
  if (Math.hypot(dx, dy) > 3) drag.moved = true;
  if (!drag.moved) return;
  updateDropTarget(drag, ghost.value);
  if (drag.groupId !== undefined) {
    const delta = clampDelta(drag.notes, dy / view.zoom);
    groupAnchors.value.set(drag.groupId, {
      x: drag.origin.x + dx / view.zoom,
      y: drag.origin.y + delta,
    });
    for (const note of drag.notes)
      positions.value.set(note.id, { x: note.origin.x + dx / view.zoom, y: note.origin.y + delta });
  } else if (drag.id === null) {
    settling = null;
    view.x = drag.origin.x + dx;
    view.y = drag.origin.y + dy;
  } else {
    const delta = clampDelta(drag.notes, dy / view.zoom);
    for (const note of drag.notes)
      positions.value.set(note.id, { x: note.origin.x + dx / view.zoom, y: note.origin.y + delta });
  }
}
function updateToolTarget(point: Point) {
  if (tool.value === "connect" && linkSource.value !== null)
    connectionTarget.value = connectionTargetAt(point, linkSource.value);
}
function updateDropTarget(current: CanvasDrag, point: Point) {
  if (current.id === null || current.notes.length !== 1 || current.groupId !== undefined) return;
  connectionTarget.value = connectionTargetAt(point, current.id);
  dragConnectionSource.value = connectionTarget.value === null ? null : current.id;
}
function finishNoteDrag(current: CanvasDrag) {
  if (dragConnectionSource.value !== null && connectionTarget.value !== null) {
    emit("connect", current.id!, connectionTarget.value, true);
  } else {
    emit(
      "move",
      current.notes.map((note) => ({ id: note.id, point: positions.value.get(note.id)! })),
    );
  }
  for (const note of current.notes) positions.value.delete(note.id);
  contact.value = new Set();
}
async function pointerUp(event: PointerEvent) {
  if (marquee.finish(event)) return;
  if (!drag || drag.pointer !== event.pointerId) return;
  if (drag.groupId !== undefined) {
    await finishGroupDrag(event, drag);
    return;
  }
  if (drag.id !== null && drag.moved) finishNoteDrag(drag);
  connectionTarget.value = null;
  dragConnectionSource.value = null;
  if (drag.capture?.hasPointerCapture(event.pointerId))
    drag.capture.releasePointerCapture(event.pointerId);
  drag = null;
}
async function finishGroupDrag(event: PointerEvent, finished: CanvasDrag) {
  drag = null;
  if (finished.capture?.hasPointerCapture(event.pointerId))
    finished.capture.releasePointerCapture(event.pointerId);
  if (finished.moved)
    await moveGroup(
      finished.groupId!,
      groupAnchors.value.get(finished.groupId!)!,
      finished.groupVersions,
    );
  for (const note of finished.notes) positions.value.delete(note.id);
  groupAnchors.value.delete(finished.groupId!);
  contact.value = new Set();
}
function cancelDrag(event: PointerEvent) {
  marquee.cancel(event);
  connectionTarget.value = null;
  dragConnectionSource.value = null;
  contact.value = new Set();
  if (!drag || drag.pointer !== event.pointerId) return;
  if (drag?.groupId !== undefined) groupAnchors.value.delete(drag.groupId);
  for (const note of drag?.notes ?? []) positions.value.delete(note.id);
  drag = null;
}
function cancelActiveDrag() {
  const current = drag;
  if (!current) return;
  drag = null;
  for (const note of current.notes) positions.value.delete(note.id);
  if (current.groupId !== undefined) groupAnchors.value.delete(current.groupId);
  connectionTarget.value = null;
  dragConnectionSource.value = null;
  if (current.capture?.hasPointerCapture(current.pointer))
    current.capture.releasePointerCapture(current.pointer);
}
function doubleClick(event: MouseEvent) {
  if (interactivePath(event) || historyState.busy) return;
  const element = (event.target as HTMLElement).closest<HTMLElement>("[data-note-id]");
  if (element) emit("edit", Number(element.dataset.noteId));
  else if (canCreate.value) emit("add", placed(world(event.clientX, event.clientY)));
}
function nudgeBlocked() {
  const nothingSelected = !visibleSelection.value.length && selectedGroupId.value === null;
  return nothingSelected || !permissions.edit || historyState.busy || drag !== null;
}
function nudge(event: KeyboardEvent) {
  if (nudgeBlocked()) return;
  const directions: { [key: string]: Point } = {
    ArrowUp: { x: 0, y: -1 },
    ArrowDown: { x: 0, y: 1 },
    ArrowLeft: { x: -1, y: 0 },
    ArrowRight: { x: 1, y: 0 },
  };
  const direction = directions[event.key];
  if (!direction) return;
  event.preventDefault();
  const step = event.shiftKey ? 20 : 2;
  if (selectedGroupId.value !== null) {
    const group = groups.value.find((group) => group.id === selectedGroupId.value);
    const visibleIds = notes.map((note) => note.id);
    if (group && !groupVisibility(group, visibleIds).partial) nudgeGroup(group, direction, step);
    return;
  }
  const selection = notes.filter((note) => visibleSelection.value.includes(note.id));
  const delta = clampDelta(
    selection.map((note) => ({ id: note.id, origin: position(note) })),
    direction.y * step,
  );
  contact.value = new Set();
  if (direction.y !== 0 && delta === 0) return;
  emit(
    "move",
    selection.map((note) => {
      const point = position(note);
      return { id: note.id, point: { x: point.x + direction.x * step, y: point.y + delta } };
    }),
  );
}
interface GroupNudge {
  id: number;
  origin: Point;
  delta: Point;
  versions: GroupVersions;
  notes: Array<{ id: number; origin: Point }>;
  timer: ReturnType<typeof setTimeout> | undefined;
}
const NUDGE_SETTLE_MS = 160;
let groupNudge: GroupNudge | null = null;
function groupVersions(group: IdeaGroup): GroupVersions {
  return {
    version: group.version,
    member_versions: group.members.map((member) => ({
      id: member.idea_id,
      version: member.canvas.version ?? 0,
    })),
  };
}
// Consecutive arrow presses become one movement, one write and one history
// step, moving the frame and its notes immediately like a drag does.
function nudgeGroup(group: IdeaGroup, direction: Point, step: number) {
  if (groupNudge && groupNudge.id !== group.id) {
    void flushGroupNudge();
    if (groupNudge) return;
  }
  groupNudge ??= {
    id: group.id,
    origin: { x: group.canvas.x, y: group.canvas.y },
    delta: { x: 0, y: 0 },
    versions: groupVersions(group),
    notes: notes
      .filter((note) => group.idea_ids.includes(note.id))
      .map((note) => ({ id: note.id, origin: position(note) })),
    timer: undefined,
  };
  const nudge = groupNudge;
  clearTimeout(nudge.timer);
  const dy = clampDelta(nudge.notes, nudge.delta.y + direction.y * step);
  contact.value = new Set();
  nudge.delta = { x: nudge.delta.x + direction.x * step, y: dy };
  groupAnchors.value.set(nudge.id, {
    x: nudge.origin.x + nudge.delta.x,
    y: nudge.origin.y + nudge.delta.y,
  });
  for (const note of nudge.notes)
    positions.value.set(note.id, {
      x: note.origin.x + nudge.delta.x,
      y: note.origin.y + nudge.delta.y,
    });
  nudge.timer = setTimeout(() => void flushGroupNudge(), NUDGE_SETTLE_MS);
}
function nudgeTarget(nudge: GroupNudge): Point {
  return { x: nudge.origin.x + nudge.delta.x, y: nudge.origin.y + nudge.delta.y };
}
async function flushGroupNudge() {
  const nudge = groupNudge;
  if (!nudge) return;
  clearTimeout(nudge.timer);
  if (historyState.busy) {
    // Another canvas write is in flight. Keep the movement queued with its
    // preview in place rather than dropping it without a word.
    nudge.timer = setTimeout(() => void flushGroupNudge(), NUDGE_SETTLE_MS);
    return;
  }
  groupNudge = null;
  await moveGroup(nudge.id, nudgeTarget(nudge), nudge.versions);
  for (const note of nudge.notes) positions.value.delete(note.id);
  groupAnchors.value.delete(nudge.id);
}
function keydown(event: KeyboardEvent) {
  if (ignoreKey(event)) return;
  if (selectingArea.value) {
    event.preventDefault();
    if (event.key === "Escape") marquee.cancel();
    return;
  }
  if (event.altKey) {
    connectedNoteShortcut(event);
    return;
  }
  if (event.metaKey || event.ctrlKey) {
    modifiedShortcut(event);
    return;
  }
  if (event.key === "Escape") {
    cancelActiveDrag();
    chooseTool("select");
    emit("select", []);
    emit("selectGroup", null);
    return;
  }
  if (event.key === "Enter") {
    editFocusedNote(event);
    return;
  }
  if (removeShortcut(event)) return;
  shortcut(event);
  nudge(event);
}
function ignoreKey(event: KeyboardEvent) {
  if (event.defaultPrevented || event.isComposing) return true;
  const target = event.target;
  if (
    target instanceof Element &&
    target.closest('input, textarea, select, [contenteditable="true"], [role="textbox"]')
  )
    return true;
  const historyKey = ["z", "y"].includes(event.key.toLowerCase());
  if (historyKey && !event.altKey && (event.metaKey || event.ctrlKey)) return false;
  return interactiveTarget(target);
}
function connectedNoteShortcut(event: KeyboardEvent) {
  if (!event.shiftKey || event.metaKey || event.ctrlKey) return;
  const directions: { [key: string]: ConnectionDirection | undefined } = {
    ArrowUp: "up",
    ArrowRight: "right",
    ArrowDown: "down",
    ArrowLeft: "left",
  };
  const direction = directions[event.key];
  if (!direction || !visibleSelection.value.length) return;
  event.preventDefault();
  if (!event.repeat) addConnected(direction);
}
function editFocusedNote(event: KeyboardEvent) {
  if (selectedGroupId.value !== null) {
    event.preventDefault();
    root.value
      ?.querySelector<HTMLButtonElement>(`#group-title-edit-${selectedGroupId.value}`)
      ?.click();
    return;
  }
  const focused = (event.target as HTMLElement).closest<HTMLElement>("[data-note-id]");
  const id = focused ? Number(focused.dataset.noteId) : selectedId.value;
  if (id !== null && permissions.edit && !historyState.busy) {
    event.preventDefault();
    emit("edit", id);
  }
}
function removeGroupShortcut(event: KeyboardEvent) {
  if (!["Delete", "Backspace"].includes(event.key) || selectedGroupId.value === null) return false;
  event.preventDefault();
  if (permissions.edit && !historyState.busy) emit("deleteGroup", selectedGroupId.value);
  return true;
}
function removeShortcut(event: KeyboardEvent) {
  if (["Delete", "Backspace"].includes(event.key) && selectedConnection.value) {
    event.preventDefault();
    removeConnection();
    return true;
  }
  if (removeGroupShortcut(event)) return true;
  if (
    !["Delete", "Backspace"].includes(event.key) ||
    !visibleSelection.value.length ||
    !permissions.edit ||
    historyState.busy
  )
    return false;
  event.preventDefault();
  emit("remove", [...visibleSelection.value]);
  return true;
}
function modifiedShortcut(event: KeyboardEvent) {
  if (event.altKey || event.isComposing) return;
  const key = event.key.toLowerCase();
  if (key === "a") {
    event.preventDefault();
    emit("finish");
    emit("selectGroup", null);
    emit(
      "select",
      notes.map((note) => note.id),
    );
    return;
  }
  // Copy, cut and paste are handled by native clipboard events. Preventing
  // their keydown would suppress the browser's clipboard access.
  if (key === "g") {
    groupShortcut(event);
    return;
  }
  if (!["d", "z", "y"].includes(key)) return;
  event.preventDefault();
  if (!permissions.edit) return;
  if (key === "d") {
    if (!historyState.busy && !event.repeat) duplicateSelection();
  } else historyShortcut(event, key);
}
function groupShortcut(event: KeyboardEvent) {
  event.preventDefault();
  if (!permissions.edit || historyState.busy || event.repeat) return;
  if (!event.shiftKey) {
    emit("createGroup", [...visibleSelection.value]);
    return;
  }
  const group = groups.value.find((group) => group.id === selectedGroupId.value);
  if (
    group &&
    !groupVisibility(
      group,
      notes.map((note) => note.id),
    ).partial
  )
    emit("separateGroup", group.id);
}
function duplicateSelection() {
  if (canCreate.value && visibleSelection.value.length)
    emit("duplicate", [...visibleSelection.value]);
}
function historyShortcut(event: KeyboardEvent, key: string) {
  const redo = key === "y" || event.shiftKey;
  const available = redo ? historyState.canRedo : historyState.canUndo;
  if (!available && !historyState.busy) return;
  if (redo) emit("redo");
  else emit("undo");
}
function pastePoint(): Point {
  return placed(
    ghost.value ?? {
      x: (view.width / 2 - view.x) / view.zoom,
      y: (view.height / 2 - view.y) / view.zoom,
    },
  );
}
function clipboard(event: ClipboardEvent, operation: "copy" | "cut" | "paste") {
  if (ignoreClipboard(event)) return;
  if (operation !== "copy" && (!permissions.edit || historyState.busy)) return;
  if (operation === "paste") {
    if (canCreate.value) emit("paste", event, pastePoint());
  } else if (visibleSelection.value.length) {
    if (operation === "copy") emit("copy", event, [...visibleSelection.value]);
    else emit("cut", event, [...visibleSelection.value]);
  }
}
function ignoreClipboard(event: ClipboardEvent) {
  if (interactiveTarget(event.target) || event.defaultPrevented) return true;
  if (!selectingArea.value) return false;
  event.preventDefault();
  return true;
}
function shortcut(event: KeyboardEvent) {
  const key = event.key.toLowerCase();
  if (key === "n" && canCreate.value && !historyState.busy) {
    event.preventDefault();
    emit(
      "add",
      placed({
        x: (view.width / 2 - view.x) / view.zoom - 140,
        y: (view.height / 2 - view.y) / view.zoom - 100,
      }),
    );
  }
  if (key === "v") chooseTool("select");
  if (key === "h") chooseTool("pan");
  if (key === "l") connectionShortcut(event);
  if (key === "1") fitAll();
}
function connectionShortcut(event: KeyboardEvent) {
  if (connectionWriteBlocked() || event.repeat) return;
  event.preventDefault();
  if (visibleSelection.value.length >= 2) connectSelection(!event.shiftKey);
  else if (!event.shiftKey) chooseTool("connect");
}
watch(
  () => canCreate.value,
  (allowed) => {
    if (!allowed && tool.value === "note") tool.value = "select";
  },
);
watch(visibleSelection, (ids) => {
  if (ids.length) selectedConnectionKey.value = null;
});
watch(links, (current) => {
  if (!current.some((link) => link.key === selectedConnectionKey.value))
    selectedConnectionKey.value = null;
});
// Controls, resizes and navigation may change the viewport mid-gesture.
watch(
  [
    () => view.x,
    () => view.y,
    () => view.zoom,
    () => view.width,
    () => view.height,
    () => historyState.busy,
  ],
  () => marquee.cancel(),
);
function canvasWheel(event: WheelEvent) {
  settling = null;
  if (selectingArea.value) event.preventDefault();
  else wheel(event);
}
onMounted(async () => {
  if (typeof ResizeObserver !== "undefined" && chromePanel.value) {
    chromeObserver = new ResizeObserver(([entry]) => {
      chromeWidth.value = entry!.contentRect.width;
    });
    chromeObserver.observe(chromePanel.value);
  }
  if (typeof ResizeObserver !== "undefined")
    noteObserver = new ResizeObserver((entries) => {
      for (const entry of entries) {
        const id = Number((entry.target as HTMLElement).id.replace("canvas-note-", ""));
        const note = entry.target as HTMLElement;
        const height = note.offsetHeight;
        const width = note.offsetWidth;
        if (height && noteHeights.value.get(id) !== height) noteHeights.value.set(id, height);
        if (width && noteWidths.value.get(id) !== width) noteWidths.value.set(id, width);
      }
    });
  await nextTick();
  measureNotes();
  openView();
});
watch(
  () => notes.map((note) => note.id),
  async () => {
    await nextTick();
    measureNotes();
  },
);
onUnmounted(() => {
  chromeObserver?.disconnect();
  noteObserver?.disconnect();
  const nudge = groupNudge;
  groupNudge = null;
  clearTimeout(nudge?.timer);
  // Best effort: a movement the user already saw should not vanish with the view.
  if (nudge) void moveGroup(nudge.id, nudgeTarget(nudge), nudge.versions);
});
</script>
<template>
  <div
    @contextmenu.capture="prepareComment"
    ref="root"
    id="brainstorming-canvas"
    tabindex="0"
    :aria-label="t('ideation.canvas.label')"
    aria-describedby="brainstorming-selection-help brainstorming-history-help brainstorming-connection-help"
    aria-keyshortcuts="Meta+Z Control+Z Meta+Shift+Z Control+Shift+Z Meta+Y Control+Y L Shift+L Alt+Shift+ArrowUp Alt+Shift+ArrowRight Alt+Shift+ArrowDown Alt+Shift+ArrowLeft"
    class="absolute inset-0 touch-none overflow-hidden outline-none"
    :class="
      space || tool === 'pan'
        ? 'cursor-grab active:cursor-grabbing'
        : tool === 'select'
          ? ''
          : 'cursor-crosshair'
    "
    :style="{
      backgroundImage:
        'radial-gradient(circle, hsl(var(--muted-foreground) / 0.2) 1px, transparent 1px)',
      backgroundSize: `${24 * view.zoom}px ${24 * view.zoom}px`,
      backgroundPosition: `${view.x}px ${view.y}px`,
    }"
    @wheel="canvasWheel"
    @pointerdown="pointerDown"
    @pointermove="pointerMove"
    @pointerup="pointerUp"
    @pointercancel="cancelDrag"
    @lostpointercapture="cancelDrag"
    @dblclick="doubleClick"
    @keydown="keydown"
    @copy="clipboard($event, 'copy')"
    @cut="clipboard($event, 'cut')"
    @paste="clipboard($event, 'paste')"
    @pointerleave="
      ghost = null;
      connectionTarget = null;
    "
  >
    <ContextMenu>
      <ContextMenuTrigger
        as-child
        :disabled="!permissions.comment && !permissions.edit && !canStartRound"
      >
        <div class="absolute inset-0">
          <div class="absolute left-0 top-0 origin-top-left" :style="{ transform }">
            <CanvasGroup
              v-for="layout in layouts"
              :key="layout.group.id"
              :group="layout.group"
              :bounds="layout.bounds"
              :visible-count="layout.visibility.visible"
              :zoom="view.zoom"
              :selected="selectedGroupId === layout.group.id"
              :can-edit="permissions.edit"
              :can-propose-decision="permissions.edit && collaboration.cursors"
              :busy="historyState.busy"
              :save="saveGroup"
              @pointer="groupPointer"
              @edit="ensureGroupReadability"
              @finish="focus"
              @resize="(id, height) => groupHeights.set(id, height)"
              @synthesis-visibility="
                (id, visible) => (visible ? openSyntheses.add(id) : openSyntheses.delete(id))
              "
              @select="selectGroup"
              @separate="emit('separateGroup', $event)"
              @remove="emit('deleteGroup', $event)"
              @reveal="emit('revealGroup', $event)"
              @propose-decision="emit('proposeGroupDecision', $event)"
            />
            <svg class="pointer-events-none absolute overflow-visible" width="1" height="1">
              <defs>
                <marker
                  id="brainstorming-connection-arrow"
                  markerWidth="6"
                  markerHeight="6"
                  refX="6"
                  refY="3"
                  orient="auto-start-reverse"
                >
                  <path
                    d="M0,0 L6,3 L0,6"
                    fill="none"
                    stroke="context-stroke"
                    stroke-linejoin="round"
                  />
                </marker>
              </defs>
              <g
                v-for="link in links"
                :key="link.key"
                class="transition-colors hover:text-primary focus-within:text-primary"
                :class="
                  selectedConnectionKey === link.key ? 'text-primary' : 'text-muted-foreground/65'
                "
              >
                <line
                  :data-connection-source="link.source"
                  :data-connection-target="link.target"
                  v-bind="{ x1: link.x1, y1: link.y1, x2: link.x2, y2: link.y2 }"
                  stroke="currentColor"
                  :stroke-width="(selectedConnectionKey === link.key ? 1.75 : 1.25) / view.zoom"
                  :marker-start="
                    ['backward', 'both'].includes(link.direction)
                      ? 'url(#brainstorming-connection-arrow)'
                      : undefined
                  "
                  :marker-end="
                    ['forward', 'both'].includes(link.direction)
                      ? 'url(#brainstorming-connection-arrow)'
                      : undefined
                  "
                />
                <line
                  :id="`canvas-connection-${link.key}`"
                  data-canvas-chrome
                  role="button"
                  tabindex="0"
                  :aria-label="
                    t('ideation.canvas.connectionLabel', {
                      source: noteLabel(link.source),
                      target: noteLabel(link.target),
                    })
                  "
                  :aria-pressed="selectedConnectionKey === link.key"
                  class="pointer-events-auto cursor-pointer outline-none"
                  v-bind="{ x1: link.x1, y1: link.y1, x2: link.x2, y2: link.y2 }"
                  stroke="transparent"
                  :stroke-width="12 / view.zoom"
                  @pointerdown.stop="selectConnection(link.key)"
                  @click.stop="selectConnection(link.key)"
                  @dblclick.stop
                  @keydown.enter.prevent.stop="selectConnection(link.key)"
                  @keydown.space.prevent.stop="selectConnection(link.key)"
                />
              </g>
              <line
                v-if="previewConnection"
                id="brainstorming-connection-preview"
                v-bind="previewConnection"
                stroke="currentColor"
                class="text-primary"
                :stroke-width="1.5 / view.zoom"
                :stroke-dasharray="`${4 / view.zoom} ${4 / view.zoom}`"
              />
            </svg>
            <div
              v-for="note in notes"
              :key="note.key ?? String(note.id)"
              :data-note-id="note.id"
              class="pointer-events-none absolute left-0 top-0"
              :class="
                selectedIds.includes(note.id) ? 'z-10' : note.state === 'discarded' ? '-z-[1]' : ''
              "
              :style="{
                transform: `translate(${position(note).x}px, ${position(note).y}px)`,
                width: `${note.canvas?.width ?? 280}px`,
              }"
            >
              <div
                v-if="connectionTarget === note.id"
                :id="`connection-target-${note.id}`"
                class="pointer-events-none absolute -inset-1 rounded-md border border-primary bg-primary/5"
                :style="{
                  width: `${noteBounds(note).width + 8}px`,
                  height: `${noteBounds(note).height + 8}px`,
                }"
              />
              <CanvasNote
                class="pointer-events-auto"
                :note="note"
                :can-create="canCreate"
                :round-number="note.round_number"
                :body="note.body"
                :editing="editingId === note.id"
                :selected="selectedIds.includes(note.id)"
                :author="member(note.author_id, members)"
                :status="statuses[note.id]"
                @change="emit('change', note.id, $event)"
                @finish="emit('finish')"
                @quick-create="
                  emit('finish');
                  emit('add', {
                    x: position(note).x + noteBounds(note).width + 40,
                    y: position(note).y,
                  });
                "
              />
            </div>
            <div
              v-for="item in bands.masked ?? []"
              :key="`masked-${item.id}`"
              :id="`canvas-masked-${item.id}`"
              data-masked-note
              role="img"
              :aria-label="t('ideation.rounds.hiddenNote')"
              class="pointer-events-none absolute left-0 top-0 rounded-lg border border-dashed border-muted-foreground/40 bg-muted/60"
              :style="{
                transform: `translate(${item.canvas.x ?? 0}px, ${item.canvas.y ?? 0}px)`,
                width: `${item.canvas.width ?? 280}px`,
                height: `${MASKED_HEIGHT}px`,
              }"
            />
            <div
              v-if="tool === 'note' && ghost"
              class="pointer-events-none absolute h-12 w-40 rounded-md border border-dashed border-primary/70 bg-primary/5"
              :style="{ left: `${ghost.x}px`, top: `${ghost.y}px` }"
            />
          </div>
          <template v-for="round in orderedRounds" :key="`round-${round.id}`">
            <div
              v-if="headerShown(round)"
              :id="`brainstorming-band-${round.id}`"
              class="absolute left-0 right-0 z-10"
              :class="headerPinned(round) ? 'pointer-events-auto' : 'pointer-events-none'"
              :data-pinned="headerPinned(round) || undefined"
              :style="{ top: `${headerTop(round)}px` }"
            >
              <RoundBar
                :round="round"
                :single="!multiRound"
                :sticky="headerUnderChrome(round)"
                :inset="headerUnderChrome(round) ? chromeInset : 0"
                :last="round.id === lastRound?.id"
                :can-manage="bands.canManage"
                :pending="bands.pending"
                :contact="contact.has(round.id)"
                :timer="round.status === 'active' ? (bands.timer ?? null) : null"
                :count="bands.counts?.get(round.id) ?? 0"
                @close="emit('closeRound', $event)"
                @update-privacy="(id, attrs) => emit('updatePrivacy', id, attrs)"
                @reveal="emit('reveal', $event)"
                @new-round="emit('newRound')"
                @update-prompt="(id, prompt) => emit('updatePrompt', id, prompt)"
              />
            </div>
          </template>
          <div
            v-if="selectedId !== null && !selectionArea"
            id="brainstorming-note-toolbar"
            ref="selectionToolbar"
            data-canvas-chrome
            class="absolute z-30 max-w-[calc(100%-16px)]"
            :style="selectionToolbarPosition"
          >
            <slot name="selection" :connection-tools="connectionTools" />
          </div>
          <div
            v-if="selectedConnection && permissions.edit"
            id="brainstorming-connection-toolbar"
            data-canvas-chrome
            class="surface-panel absolute z-30 flex -translate-x-1/2 -translate-y-full items-center gap-0.5 p-1"
            :style="{
              left: `${Math.min(view.width - 100, Math.max(100, view.x + ((selectedConnection.x1 + selectedConnection.x2) / 2) * view.zoom))}px`,
              top: `${Math.max(48, Math.min(view.height - 80, view.y + ((selectedConnection.y1 + selectedConnection.y2) / 2) * view.zoom - 12))}px`,
            }"
            role="toolbar"
            :aria-label="t('ideation.canvas.connectionDirection')"
          >
            <ToolbarTooltip
              v-for="direction in connectionDirections"
              :key="direction.value"
              :label="t(`ideation.canvas.connectionDirections.${direction.value}`)"
            >
              <button
                :id="`connection-direction-${direction.value}`"
                type="button"
                class="toolbar-btn"
                :class="
                  selectedConnection.direction === direction.value
                    ? 'bg-primary/10 text-primary'
                    : ''
                "
                :aria-label="t(`ideation.canvas.connectionDirections.${direction.value}`)"
                :aria-pressed="selectedConnection.direction === direction.value"
                :disabled="historyState.busy"
                @click="changeConnectionDirection(direction.value)"
              >
                <component :is="direction.icon" class="size-4" />
              </button>
            </ToolbarTooltip>
          </div>
          <div
            v-if="selectionArea"
            id="brainstorming-selection-area"
            aria-hidden="true"
            class="pointer-events-none absolute z-20 border border-primary bg-primary/10"
            :style="{
              left: `${selectionArea.x}px`,
              top: `${selectionArea.y}px`,
              width: `${selectionArea.width}px`,
              height: `${selectionArea.height}px`,
            }"
          />
          <p id="brainstorming-selection-help" class="sr-only">
            {{ t("ideation.canvas.selectHelp") }}
          </p>
          <p id="brainstorming-history-help" class="sr-only">
            {{ t("ideation.canvas.historyHelp") }}
          </p>
          <p id="brainstorming-connection-help" class="sr-only">
            {{ t("ideation.canvas.connectionHelp") }}
          </p>
          <CanvasCursors
            v-if="collaboration.cursors"
            :container="root"
            :view="view"
            :context="collaboration.context"
          />
          <div
            v-if="!notes.length && !groups.length"
            class="pointer-events-none absolute inset-0 flex flex-col items-center justify-center gap-3 px-8 pb-20 text-center"
          >
            <StickyNote class="size-9 text-muted-foreground/35" />
            <p class="text-lg font-medium">{{ t("ideation.canvas.empty") }}</p>
            <p class="max-w-sm text-sm text-muted-foreground">
              {{
                t(
                  !permissions.edit
                    ? "ideation.readOnly"
                    : canCreate
                      ? "ideation.canvas.emptyHelp"
                      : "ideation.timer.closedHelp",
                )
              }}
            </p>
          </div>
          <div
            data-canvas-chrome
            class="absolute left-3 z-20"
            :class="chromeFramed ? 'top-3' : 'top-0'"
          >
            <div
              ref="chromePanel"
              :class="
                chromeFramed
                  ? 'surface-panel flex w-fit items-center p-1'
                  : 'flex h-[42px] w-fit items-center gap-0.5'
              "
            >
              <Popover v-model:open="searchOpen">
                <PopoverTrigger as-child>
                  <button type="button" class="toolbar-btn" :aria-label="t('ideation.search')">
                    <Search class="size-4" />
                  </button>
                </PopoverTrigger>
                <PopoverContent align="start" :side-offset="8" class="w-72 p-3" data-canvas-chrome>
                  <Input
                    v-model="query"
                    :placeholder="t('ideation.search')"
                    :aria-label="t('ideation.search')"
                  />
                  <div class="mt-2 max-h-64 overflow-auto">
                    <button
                      v-for="note in matches"
                      :key="note.id"
                      type="button"
                      class="block w-full truncate rounded-md px-2 py-2 text-left text-sm hover:bg-accent"
                      @click="
                        center(note);
                        emit('selectGroup', null);
                        emit('select', [note.id]);
                        searchOpen = false;
                      "
                    >
                      {{ note.title || note.body.replace(/<[^>]*>/g, " ") }}
                    </button>
                  </div>
                </PopoverContent>
              </Popover>
              <slot name="session" />
            </div>
          </div>
          <p
            v-if="tool === 'connect'"
            data-canvas-chrome
            class="surface-panel absolute left-1/2 top-3 z-20 -translate-x-1/2 px-4 py-2 text-xs"
          >
            {{
              t(
                linkSource === null
                  ? "ideation.canvas.connectSource"
                  : "ideation.canvas.connectTarget",
              )
            }}<button
              type="button"
              class="ml-3"
              :aria-label="t('ideation.cancel')"
              @click="chooseTool('select')"
            >
              <X class="size-3" />
            </button>
          </p>
          <div
            data-canvas-chrome
            class="surface-panel absolute bottom-3 left-1/2 z-30 flex -translate-x-1/2 items-center gap-1 px-2 py-2"
          >
            <DockToolButton
              :icon="MousePointer2"
              :active="tool === 'select'"
              :tooltip-title="t('ideation.canvas.select')"
              :tooltip-description="`${t('ideation.canvas.selectHelp')} ${t('ideation.canvas.historyHelp')}`"
              @click="chooseTool('select')"
            />
            <DockToolButton
              :icon="Hand"
              :active="tool === 'pan'"
              :tooltip-title="t('ideation.canvas.pan')"
              @click="chooseTool('pan')"
            />
            <template v-if="permissions.edit"
              ><div class="mx-0.5 h-6 w-px bg-border" />
              <DockToolButton
                v-if="canCreate"
                id="new-brainstorming-idea"
                :icon="StickyNote"
                :active="tool === 'note'"
                :tooltip-title="t('ideation.canvas.note')"
                :tooltip-description="t('ideation.canvas.noteHelp')"
                @click="chooseTool('note')" /><DockToolButton
                :icon="Cable"
                :active="tool === 'connect'"
                :tooltip-title="t('ideation.canvas.connect')"
                :tooltip-description="t('ideation.canvas.connectionHelp')"
                @click="chooseTool('connect')"
            /></template>
            <div class="mx-0.5 h-6 w-px bg-border" />
            <DockToolButton
              :icon="List"
              :tooltip-title="t('ideation.list')"
              @click="
                emit('finish');
                emit('list');
              "
            />
          </div>
          <div
            data-canvas-chrome
            class="surface-panel absolute bottom-20 right-3 z-20 flex items-center gap-1 p-1 sm:bottom-3"
          >
            <button
              type="button"
              class="toolbar-btn"
              :aria-label="t('ideation.canvas.zoomOut')"
              @click="zoomTo(view.zoom / 1.2)"
            >
              <Minus class="size-3.5" /></button
            ><button
              type="button"
              class="toolbar-btn min-w-12 tabular-nums"
              :aria-label="t('ideation.canvas.resetZoom')"
              @click="zoomTo(1)"
            >
              {{ Math.round(view.zoom * 100) }}%</button
            ><button
              type="button"
              class="toolbar-btn"
              :aria-label="t('ideation.canvas.zoomIn')"
              @click="zoomTo(view.zoom * 1.2)"
            >
              <Plus class="size-3.5" /></button
            ><ToolbarTooltip :label="t('ideation.canvas.fit')"
              ><button
                type="button"
                class="toolbar-btn"
                :aria-label="t('ideation.canvas.fit')"
                @click="fitAll"
              >
                <Maximize class="size-3.5" /></button
            ></ToolbarTooltip>
          </div>
        </div>
      </ContextMenuTrigger>
      <ContextMenuContent
        v-if="commentTarget || noteTarget || bringTarget || canStartRound"
        @close-auto-focus.prevent="root?.focus({ preventScroll: true })"
      >
        <ContextMenuItem
          v-if="commentTarget"
          id="brainstorming-comment-context-add"
          @select="emit('comment', commentTarget)"
        >
          <MessageSquarePlus class="size-4" />{{ t("brainstormingComments.add_comment") }}
        </ContextMenuItem>
        <template v-if="noteTarget">
          <ContextMenuItem
            v-if="noteTarget.state !== 'parked'"
            id="brainstorming-note-context-park"
            @select="emit('changeState', noteTarget.id, 'parked')"
          >
            <Bookmark class="size-4" />{{ t("ideation.parked") }}
          </ContextMenuItem>
          <ContextMenuItem
            v-if="noteTarget.state !== 'active'"
            id="brainstorming-note-context-restore"
            @select="emit('changeState', noteTarget.id, 'active')"
          >
            <RotateCcw class="size-4" />{{ t("ideation.bringBack") }}
          </ContextMenuItem>
          <ContextMenuItem
            v-if="noteTarget.state !== 'discarded'"
            id="brainstorming-note-context-discard"
            @select="emit('changeState', noteTarget.id, 'discarded')"
          >
            <CircleX class="size-4" />{{ t("ideation.canvas.discard") }}
          </ContextMenuItem>
        </template>
        <ContextMenuItem
          v-if="bringTarget"
          id="brainstorming-note-context-bring"
          @select="emit('bringForward', bringTarget.id, bringTarget.point)"
        >
          <ArrowDownToLine class="size-4" />{{ t("ideation.bringForward") }}
        </ContextMenuItem>
        <ContextMenuItem
          v-if="canStartRound"
          id="brainstorming-round-context-new"
          :disabled="bands.pending"
          @select="emit('newRound')"
        >
          <Plus class="size-4" />{{ t("ideation.rounds.newRound") }}
        </ContextMenuItem>
      </ContextMenuContent>
    </ContextMenu>
    <BrainstormingCanvasComments
      v-if="collaboration.comments && collaboration.context.session_id !== null"
      :state="collaboration.comments"
      :view="view"
      :epoch="collaboration.context.epoch"
      :session-id="collaboration.context.session_id"
      :base-url="collaboration.baseUrl ?? ''"
      :notes="notes"
      :groups="groups"
      @focus="
        (point) => {
          view.x = view.width / 2 - point.x * view.zoom;
          view.y = view.height / 2 - point.y * view.zoom;
        }
      "
    />
  </div>
</template>
