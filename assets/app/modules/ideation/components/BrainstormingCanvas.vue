<script setup lang="ts">
import { computed, nextTick, onMounted, onUnmounted, ref, watch } from "vue";
import {
  MousePointer2,
  Hand,
  StickyNote,
  Cable,
  Minus,
  Plus,
  Maximize,
  List,
  Search,
  X,
} from "@lucide/vue";
import DockToolButton from "@components/toolbar/DockToolButton.vue";
import ToolbarTooltip from "@components/toolbar/ToolbarTooltip.vue";
import { Input } from "@components/ui/input";
import CanvasNote from "./CanvasNote.vue";
import CanvasGroup from "./CanvasGroup.vue";
import { groupBounds, groupVisibility, type MemberGeometry } from "../lib/groups";
import CanvasCursors from "./CanvasCursors.vue";
import { useCanvasViewport, type Point } from "../composables/useCanvasViewport";
import { useCanvasMarquee } from "../composables/useCanvasMarquee";
import { useBoardText } from "../composables/useBoardText";
import { notePosition } from "../lib/placement";
import {
  connectedPlacement,
  connectionEndpoints,
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
} from "../types";
interface HistoryState {
  canUndo: boolean;
  canRedo: boolean;
  busy: boolean;
}
const {
  notes,
  groupState,
  selectedIds,
  noteKey,
  editingId,
  permissions,
  collaboration,
  members,
  statuses,
  historyState,
} = defineProps<{
  notes: CanvasIdea[];
  groupState?: {
    groups: IdeaGroup[];
    selectedId: number | null;
    save: (id: number, text: GroupText, version: number) => Promise<boolean>;
    move: (id: number, point: Point, expected?: GroupVersions) => Promise<void>;
  };
  selectedIds: number[];
  noteKey: (id: number) => string;
  historyState: HistoryState;
  editingId: number | null;
  permissions: { edit: boolean; create: boolean };
  collaboration: { context: BoardContext; cursors: boolean };
  members: Member[];
  statuses: { [id: number]: string };
}>();
const groups = computed(() => groupState?.groups ?? []);
const selectedGroupId = computed(() => groupState?.selectedId ?? null);
const saveGroup = (id: number, text: GroupText, version: number) =>
  groupState?.save(id, text, version) ?? Promise.resolve(false);
const moveGroup = (id: number, point: Point, expected?: GroupVersions) =>
  groupState?.move(id, point, expected) ?? Promise.resolve();
const canCreate = computed(() => permissions.edit && permissions.create);
const emit = defineEmits<{
  add: [point: Point];
  select: [ids: number[]];
  selectGroup: [id: number | null];
  createGroup: [ids: number[]];
  separateGroup: [id: number];
  deleteGroup: [id: number];
  revealGroup: [id: number];
  edit: [id: number];
  change: [id: number, body: string];
  finish: [];
  move: [moves: Array<{ id: number; point: Point }>];
  connect: [source: number, target: number, connected: boolean];
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
}>();
const root = ref<HTMLElement | null>(null);
const { view, space, transform, world, zoomTo, wheel, fit } = useCanvasViewport(root);
const { t, member } = useBoardText();
const tool = ref("select"),
  query = ref("");
const searchOpen = ref(false);
const positions = ref(new Map<number, Point>());
const linkSource = ref<number | null>(null);
const ghost = ref<Point | null>(null);
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
const marquee = useCanvasMarquee({
  root,
  world,
  bounds: () =>
    notes.map((note) => ({
      id: note.id,
      ...position(note),
      width: note.canvas?.width ?? 280,
      height: noteHeights.value.get(note.id) ?? 260,
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
    canvas: { ...note.canvas, ...position(note) },
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
        canvas: member.canvas,
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
    if (note) {
      noteHeights.value.set(id, note.offsetHeight || 260);
      noteObserver?.observe(note);
    }
  }
}
function bounds() {
  return notes.map((n) => ({
    ...position(n),
    width: n.canvas?.width ?? 280,
    height: root.value?.querySelector<HTMLElement>(`#canvas-note-${n.id}`)?.offsetHeight ?? 260,
  }));
}
function fitAll() {
  fit([...bounds(), ...layouts.value.map((layout) => layout.bounds)]);
}
function center(note: Idea) {
  const point = position(note);
  view.x = view.width / 2 - (point.x + (note.canvas?.width ?? 280) / 2) * view.zoom;
  view.y = view.height / 2 - (point.y + (noteHeights.value.get(note.id) ?? 260) / 2) * view.zoom;
}
function noteBounds(note: Idea) {
  return {
    shape: note.canvas?.shape,
    ...position(note),
    width: note.canvas?.width ?? 280,
    height: noteHeights.value.get(note.id) ?? 260,
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
  const selection = notes.filter((note) => selectedIds.includes(note.id)).map(noteBounds);
  if (
    selection.some(
      (bounds) =>
        view.x + bounds.x * view.zoom < 48 ||
        view.y + bounds.y * view.zoom < 80 ||
        view.x + (bounds.x + bounds.width) * view.zoom > view.width - 48 ||
        view.y + (bounds.y + bounds.height) * view.zoom > view.height - 80,
    )
  ) {
    const zoom = view.zoom;
    fit(selection);
    if (view.zoom > zoom) zoomTo(zoom);
  }
  const editor =
    editingId === null
      ? null
      : root.value?.querySelector<HTMLElement>(`#canvas-note-${editingId} [contenteditable=true]`);
  if (editor) editor.focus({ preventScroll: true });
  else focus();
}
defineExpose({ center, fitAll, focus, focusEditing, summaryAnchor, revealNote });
const visibleSelection = computed(() =>
  selectedIds.filter((id) => notes.some((note) => note.id === id)),
);
const selectedId = computed(() => selectedIds[0] ?? null);
const chosenOrigin = ref<number | null>(null);
const connectionSelection = computed(() => {
  const origin = chosenOrigin.value;
  return origin !== null && visibleSelection.value.includes(origin)
    ? [origin, ...visibleSelection.value.filter((id) => id !== origin)]
    : visibleSelection.value;
});
const connectionOrigin = computed(() => {
  if (!permissions.edit) return null;
  if (tool.value === "connect") return linkSource.value;
  return connectionSelection.value.length >= 2 ? connectionSelection.value[0] : null;
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
  emit("connectSelection", [...connectionSelection.value], connected);
  focus();
}
function useConnectionOrigin(id: number) {
  if (connectionWriteBlocked() || !visibleSelection.value.includes(id)) return;
  chosenOrigin.value = id;
}
function addConnected(direction: ConnectionDirection) {
  if (connectionWriteBlocked() || !canCreate.value || !visibleSelection.value.length) return;
  const selected = notes.filter((note) => visibleSelection.value.includes(note.id));
  const obstacles = [...notes.map(noteBounds), ...layouts.value.map((layout) => layout.bounds)];
  const point = connectedPlacement(selected.map(noteBounds), obstacles, direction);
  if (!point) return;
  emit("finish");
  tool.value = "select";
  linkSource.value = null;
  emit("addConnected", [...visibleSelection.value], point);
}
const connectionTools = computed(() => ({
  selection: connectionSelection.value.map((id) => {
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
  onOrigin: useConnectionOrigin,
}));
const matches = computed(() =>
  notes.filter((n) =>
    `${n.title ?? ""} ${n.body.replace(/<[^>]*>/g, " ")}`
      .toLocaleLowerCase()
      .includes(query.value.toLocaleLowerCase()),
  ),
);
const links = computed(() =>
  notes.flatMap((source) =>
    (source.canvas?.links ?? []).flatMap((id) => {
      const target = notes.find((n) => n.id === id);
      if (!target) return [];
      const endpoints = connectionEndpoints(noteBounds(source), noteBounds(target), 6 / view.zoom);
      if (!endpoints) return [];
      return [
        {
          source: source.id,
          target: id,
          ...endpoints,
        },
      ];
    }),
  ),
);
function chooseTool(value: string) {
  marquee.cancel();
  emit("finish");
  tool.value = value;
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
  if (tool.value === "connect" && permissions.edit) {
    if (linkSource.value !== null && linkSource.value !== id) {
      emit("connect", linkSource.value, id, true);
      linkSource.value = null;
      tool.value = "select";
    } else linkSource.value = id;
  }
  emit("selectGroup", null);
  const ids = selectionForNote(id, shift);
  emit("select", ids);
  return ids;
}
function interactiveTarget(target: EventTarget | null): boolean {
  return (
    target instanceof Element &&
    Boolean(
      target.closest(
        'input, textarea, select, button, a, [contenteditable="true"], [role="textbox"], [data-canvas-chrome]',
      ),
    )
  );
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
  emit("selectGroup", null);
  emit("finish");
  emit("select", []);
  focus();
  if (tool.value === "note" && canCreate.value) {
    emit("add", world(event.clientX, event.clientY));
    tool.value = "select";
  }
}
function beginMarquee(event: PointerEvent, clickGroup?: number) {
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
  if (selectingArea.value) {
    marquee.move(event);
    return;
  }
  if (!drag || drag.pointer !== event.pointerId) return;
  const dx = event.clientX - drag.start.x,
    dy = event.clientY - drag.start.y;
  if (Math.hypot(dx, dy) > 3) drag.moved = true;
  if (!drag.moved) return;
  if (drag.groupId !== undefined) {
    groupAnchors.value.set(drag.groupId, {
      x: drag.origin.x + dx / view.zoom,
      y: drag.origin.y + dy / view.zoom,
    });
    for (const note of drag.notes)
      positions.value.set(note.id, {
        x: note.origin.x + dx / view.zoom,
        y: note.origin.y + dy / view.zoom,
      });
  } else if (drag.id === null) {
    view.x = drag.origin.x + dx;
    view.y = drag.origin.y + dy;
  } else {
    for (const note of drag.notes)
      positions.value.set(note.id, {
        x: note.origin.x + dx / view.zoom,
        y: note.origin.y + dy / view.zoom,
      });
  }
}
async function pointerUp(event: PointerEvent) {
  if (marquee.finish(event)) return;
  if (!drag || drag.pointer !== event.pointerId) return;
  if (drag.groupId !== undefined) {
    await finishGroupDrag(event, drag);
    return;
  }
  if (drag.id !== null && drag.moved) {
    emit(
      "move",
      drag.notes.map((note) => ({ id: note.id, point: positions.value.get(note.id)! })),
    );
    for (const note of drag.notes) positions.value.delete(note.id);
  }
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
}
function cancelDrag(event: PointerEvent) {
  marquee.cancel(event);
  if (!drag || drag.pointer !== event.pointerId) return;
  if (drag?.groupId !== undefined) groupAnchors.value.delete(drag.groupId);
  for (const note of drag?.notes ?? []) positions.value.delete(note.id);
  drag = null;
}
function doubleClick(event: MouseEvent) {
  if (interactiveTarget(event.target) || historyState.busy) return;
  const element = (event.target as HTMLElement).closest<HTMLElement>("[data-note-id]");
  if (element) emit("edit", Number(element.dataset.noteId));
  else if (canCreate.value) emit("add", world(event.clientX, event.clientY));
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
  emit(
    "move",
    notes
      .filter((note) => visibleSelection.value.includes(note.id))
      .map((note) => {
        const point = position(note);
        return {
          id: note.id,
          point: { x: point.x + direction.x * step, y: point.y + direction.y * step },
        };
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
  nudge.delta = { x: nudge.delta.x + direction.x * step, y: nudge.delta.y + direction.y * step };
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
  return (
    ghost.value ?? {
      x: (view.width / 2 - view.x) / view.zoom,
      y: (view.height / 2 - view.y) / view.zoom,
    }
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
    emit("add", {
      x: (view.width / 2 - view.x) / view.zoom - 140,
      y: (view.height / 2 - view.y) / view.zoom - 100,
    });
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
  if (chosenOrigin.value !== null && !ids.includes(chosenOrigin.value)) chosenOrigin.value = null;
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
  if (selectingArea.value) event.preventDefault();
  else wheel(event);
}
onMounted(async () => {
  if (typeof ResizeObserver !== "undefined")
    noteObserver = new ResizeObserver((entries) => {
      for (const entry of entries) {
        const id = Number((entry.target as HTMLElement).id.replace("canvas-note-", ""));
        const height = (entry.target as HTMLElement).offsetHeight;
        if (height && noteHeights.value.get(id) !== height) noteHeights.value.set(id, height);
      }
    });
  await nextTick();
  measureNotes();
  fitAll();
});
watch(
  () => notes.map((note) => note.id),
  async () => {
    await nextTick();
    measureNotes();
  },
);
onUnmounted(() => {
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
    @pointerleave="ghost = null"
  >
    <div class="absolute left-0 top-0 origin-top-left" :style="{ transform }">
      <svg
        class="pointer-events-none absolute overflow-visible"
        width="1"
        height="1"
        aria-hidden="true"
      >
        <defs>
          <marker
            id="brainstorming-connection-arrow"
            markerWidth="7"
            markerHeight="7"
            refX="7"
            refY="3.5"
            orient="auto"
          >
            <path d="M0,0 L7,3.5 L0,7" fill="none" stroke="currentColor" stroke-linejoin="round" />
          </marker>
        </defs>
        <line
          v-for="link in links"
          :key="`${link.source}-${link.target}`"
          :data-connection-source="link.source"
          :data-connection-target="link.target"
          v-bind="{ x1: link.x1, y1: link.y1, x2: link.x2, y2: link.y2 }"
          stroke="currentColor"
          class="text-muted-foreground/50"
          :stroke-width="2 / view.zoom"
          marker-end="url(#brainstorming-connection-arrow)"
        />
      </svg>
      <CanvasGroup
        v-for="layout in layouts"
        :key="layout.group.id"
        :group="layout.group"
        :bounds="layout.bounds"
        :visible-count="layout.visibility.visible"
        :zoom="view.zoom"
        :selected="selectedGroupId === layout.group.id"
        :can-edit="permissions.edit"
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
      />
      <div
        v-for="note in notes"
        :key="noteKey(note.id)"
        :data-note-id="note.id"
        class="absolute left-0 top-0"
        :class="selectedIds.includes(note.id) ? 'z-10' : ''"
        :style="{
          transform: `translate(${position(note).x}px, ${position(note).y}px)`,
          width: `${note.canvas?.width ?? 280}px`,
        }"
      >
        <span
          v-if="connectionOrigin === note.id"
          :id="`connection-origin-badge-${note.id}`"
          class="pointer-events-none absolute bottom-0 right-2 z-10 translate-y-1/2 rounded-full border border-primary/30 bg-background px-2 py-0.5 text-[11px] font-medium text-primary shadow-sm"
          :style="{
            transform: `translateY(50%) scale(${1 / view.zoom})`,
            transformOrigin: 'right center',
          }"
          >{{ t("ideation.canvas.connectionOrigin") }}</span
        >
        <CanvasNote
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
              x: position(note).x + (note.canvas?.width ?? 280) + 40,
              y: position(note).y,
            });
          "
        />
        <div
          v-if="selectedId === note.id && !selectionArea"
          data-canvas-chrome
          class="absolute bottom-full left-1/2 z-20 mb-4 -translate-x-1/2"
          :style="{ transform: `scale(${1 / view.zoom})`, transformOrigin: 'bottom center' }"
        >
          <slot name="selection" :connection-tools="connectionTools" />
        </div>
      </div>
      <div
        v-if="tool === 'note' && ghost"
        class="pointer-events-none absolute h-60 w-70 rounded-sm border-2 border-dashed border-primary bg-primary/5"
        :style="{ left: `${ghost.x}px`, top: `${ghost.y}px` }"
      />
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
    <p id="brainstorming-selection-help" class="sr-only">{{ t("ideation.canvas.selectHelp") }}</p>
    <p id="brainstorming-history-help" class="sr-only">{{ t("ideation.canvas.historyHelp") }}</p>
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
    <div data-canvas-chrome class="absolute left-3 top-3 z-20">
      <div class="surface-panel flex items-center p-1">
        <button
          type="button"
          class="toolbar-btn"
          :aria-label="t('ideation.search')"
          @click="searchOpen = !searchOpen"
        >
          <Search class="size-4" /></button
        ><slot name="session" />
      </div>
      <div v-if="searchOpen" class="surface-panel mt-2 w-72 p-3">
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
      </div>
    </div>
    <p
      v-if="tool === 'connect'"
      data-canvas-chrome
      class="surface-panel absolute left-1/2 top-3 z-20 -translate-x-1/2 px-4 py-2 text-xs"
    >
      {{ t(linkSource === null ? "ideation.canvas.connectSource" : "ideation.canvas.connectTarget")
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
</template>
