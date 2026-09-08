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
  Undo2,
  Redo2,
} from "@lucide/vue";
import DockToolButton from "@components/toolbar/DockToolButton.vue";
import ToolbarTooltip from "@components/toolbar/ToolbarTooltip.vue";
import { Input } from "@components/ui/input";
import CanvasNote from "./CanvasNote.vue";
import CanvasGroup from "./CanvasGroup.vue";
import { groupBounds, groupVisibility, type MemberGeometry } from "../lib/groups";
import CanvasCursors from "./CanvasCursors.vue";
import { useCanvasViewport, type Point } from "../composables/useCanvasViewport";
import { useBoardText } from "../composables/useBoardText";
import { notePosition } from "../lib/placement";
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
  view.y = view.height / 2 - (point.y + 120) * view.zoom;
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
defineExpose({ center, fitAll, focus, summaryAnchor });
const visibleSelection = computed(() =>
  selectedIds.filter((id) => notes.some((note) => note.id === id)),
);
const selectedId = computed(() => selectedIds[0] ?? null);
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
      const a = position(source),
        b = position(target);
      return [
        {
          source: source.id,
          target: id,
          x1: a.x + (source.canvas?.width ?? 280) / 2,
          y1: a.y + 120,
          x2: b.x + (target.canvas?.width ?? 280) / 2,
          y2: b.y + 120,
        },
      ];
    }),
  ),
);
function chooseTool(value: string) {
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
  if (interactiveTarget(event.target) || ![0, 1].includes(event.button)) return;
  const element = (event.target as HTMLElement).closest<HTMLElement>("[data-note-id]");
  const id = element ? Number(element.dataset.noteId) : null;
  const panning = space.value || tool.value === "pan" || event.button === 1;
  if (panning) {
    event.preventDefault();
    focus();
    beginDrag(event, null, []);
    return;
  }
  if (historyState.busy) return;
  if (id === null) selectBackground(event);
  else dragSelection(id, event);
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
  if (![0, 1].includes(event.button)) return;
  if (space.value || tool.value === "pan" || event.button === 1) {
    event.preventDefault();
    beginDrag(event, null, []);
    return;
  }
  if (groupNudge) {
    // A keyboard movement is still settling; commit it before any pointer work.
    void flushGroupNudge();
    return;
  }
  if (historyState.busy) return;
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
function cancelDrag() {
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
function nudge(event: KeyboardEvent) {
  if (
    (!visibleSelection.value.length && selectedGroupId.value === null) ||
    !permissions.edit ||
    historyState.busy
  )
    return;
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
  if (groupNudge && groupNudge.id !== group.id) void flushGroupNudge();
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
async function flushGroupNudge() {
  const nudge = groupNudge;
  groupNudge = null;
  if (!nudge) return;
  clearTimeout(nudge.timer);
  await moveGroup(
    nudge.id,
    { x: nudge.origin.x + nudge.delta.x, y: nudge.origin.y + nudge.delta.y },
    nudge.versions,
  );
  for (const note of nudge.notes) positions.value.delete(note.id);
  groupAnchors.value.delete(nudge.id);
}
function keydown(event: KeyboardEvent) {
  if (event.defaultPrevented) return;
  if (interactiveTarget(event.target)) return;
  if (event.metaKey || event.ctrlKey) {
    modifiedShortcut(event);
    return;
  }
  if (event.altKey || event.isComposing) return;
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
  if (!permissions.edit || historyState.busy || event.repeat) return;
  if (key === "d") duplicateSelection();
  else historyShortcut(event, key);
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
  const redo = (key === "z" && event.shiftKey) || (key === "y" && event.ctrlKey);
  if (redo) {
    if (historyState.canRedo) emit("redo");
  } else if (key === "z" && historyState.canUndo) emit("undo");
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
  if (interactiveTarget(event.target) || event.defaultPrevented) return;
  if (operation !== "copy" && (!permissions.edit || historyState.busy)) return;
  if (operation === "paste") {
    if (canCreate.value) emit("paste", event, pastePoint());
  } else if (visibleSelection.value.length) {
    if (operation === "copy") emit("copy", event, [...visibleSelection.value]);
    else emit("cut", event, [...visibleSelection.value]);
  }
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
  if (key === "l" && permissions.edit && !historyState.busy) chooseTool("connect");
  if (key === "1") fitAll();
}
watch(
  () => canCreate.value,
  (allowed) => {
    if (!allowed && tool.value === "note") tool.value = "select";
  },
);
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
  clearTimeout(groupNudge?.timer);
  groupNudge = null;
});
</script>
<template>
  <div
    ref="root"
    id="brainstorming-canvas"
    tabindex="0"
    :aria-label="t('ideation.canvas.label')"
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
    @wheel="wheel"
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
        <line
          v-for="link in links"
          :key="`${link.source}-${link.target}`"
          v-bind="{ x1: link.x1, y1: link.y1, x2: link.x2, y2: link.y2 }"
          stroke="currentColor"
          class="text-muted-foreground/50"
          :stroke-width="2 / view.zoom"
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
          v-if="selectedId === note.id"
          data-canvas-chrome
          class="absolute bottom-full left-1/2 z-20 mb-4 -translate-x-1/2"
          :style="{ transform: `scale(${1 / view.zoom})`, transformOrigin: 'bottom center' }"
        >
          <slot name="selection" />
        </div>
      </div>
      <div
        v-if="tool === 'note' && ghost"
        class="pointer-events-none absolute h-60 w-70 rounded-sm border-2 border-dashed border-primary bg-primary/5"
        :style="{ left: `${ghost.x}px`, top: `${ghost.y}px` }"
      />
    </div>
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
          @click="chooseTool('connect')"
      /></template>
      <template v-if="permissions.edit">
        <div class="mx-0.5 h-6 w-px bg-border" />
        <ToolbarTooltip :label="t('ideation.canvas.undoHelp')">
          <button
            id="brainstorming-undo"
            type="button"
            class="dock-btn disabled:opacity-35"
            :aria-label="t('ideation.canvas.undo')"
            aria-keyshortcuts="Meta+Z Control+Z"
            :disabled="!historyState.canUndo || historyState.busy"
            @click="emit('undo')"
          >
            <Undo2 class="size-5" />
          </button>
        </ToolbarTooltip>
        <ToolbarTooltip :label="t('ideation.canvas.redoHelp')">
          <button
            id="brainstorming-redo"
            type="button"
            class="dock-btn disabled:opacity-35"
            :aria-label="t('ideation.canvas.redo')"
            aria-keyshortcuts="Meta+Shift+Z Control+Shift+Z Control+Y"
            :disabled="!historyState.canRedo || historyState.busy"
            @click="emit('redo')"
          >
            <Redo2 class="size-5" />
          </button>
        </ToolbarTooltip>
      </template>
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
