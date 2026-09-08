<script setup lang="ts">
import { computed, nextTick, onMounted, ref } from "vue";
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
import CanvasCursors from "./CanvasCursors.vue";
import { useCanvasViewport, type Point } from "../composables/useCanvasViewport";
import { useBoardText } from "../composables/useBoardText";
import { notePosition } from "../lib/placement";
import type { BoardContext, Idea, Member } from "../types";
interface HistoryState {
  canUndo: boolean;
  canRedo: boolean;
  busy: boolean;
}
const {
  notes,
  selectedIds,
  noteKey,
  editingId,
  writable,
  cursorEnabled = true,
  members,
  statuses,
  context,
  historyState,
} = defineProps<{
  notes: Idea[];
  selectedIds: number[];
  noteKey: (id: number) => string;
  historyState: HistoryState;
  editingId: number | null;
  writable: boolean;
  cursorEnabled?: boolean;
  members: Member[];
  statuses: { [id: number]: string };
  context: BoardContext;
}>();
const emit = defineEmits<{
  add: [point: Point];
  select: [ids: number[]];
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
let drag: {
  pointer: number;
  id: number | null;
  start: Point;
  origin: Point;
  notes: Array<{ id: number; origin: Point }>;
  moved: boolean;
  capture: HTMLElement | null;
} | null = null;

function position(note: Idea): Point {
  return positions.value.get(note.id) ?? notePosition(note);
}
function bounds() {
  return notes.map((n) => ({
    ...position(n),
    width: n.canvas?.width ?? 280,
    height: root.value?.querySelector<HTMLElement>(`#canvas-note-${n.id}`)?.offsetHeight ?? 260,
  }));
}
function fitAll() {
  fit(bounds());
}
function center(note: Idea) {
  const point = position(note);
  view.x = view.width / 2 - (point.x + (note.canvas?.width ?? 280) / 2) * view.zoom;
  view.y = view.height / 2 - (point.y + 120) * view.zoom;
}
function focus() {
  root.value?.focus({ preventScroll: true });
}
defineExpose({ center, fitAll, focus });
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
  if (tool.value === "connect" && writable) {
    if (linkSource.value !== null && linkSource.value !== id) {
      emit("connect", linkSource.value, id, true);
      linkSource.value = null;
      tool.value = "select";
    } else linkSource.value = id;
  }
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
function selectBackground(event: PointerEvent) {
  emit("finish");
  emit("select", []);
  focus();
  if (tool.value === "note" && writable) {
    emit("add", world(event.clientX, event.clientY));
    tool.value = "select";
  }
}
function dragSelection(id: number, event: PointerEvent) {
  const connecting = tool.value === "connect";
  const ids = selectNote(id, event.shiftKey);
  if (!writable || connecting || !ids.includes(id)) return;
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
  if (drag.id === null) {
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
function pointerUp(event: PointerEvent) {
  if (!drag || drag.pointer !== event.pointerId) return;
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
function cancelDrag() {
  for (const note of drag?.notes ?? []) positions.value.delete(note.id);
  drag = null;
}
function doubleClick(event: MouseEvent) {
  if (interactiveTarget(event.target) || historyState.busy) return;
  const element = (event.target as HTMLElement).closest<HTMLElement>("[data-note-id]");
  if (element) emit("edit", Number(element.dataset.noteId));
  else if (writable) emit("add", world(event.clientX, event.clientY));
}
function nudge(event: KeyboardEvent) {
  if (!visibleSelection.value.length || !writable || historyState.busy) return;
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
  const focused = (event.target as HTMLElement).closest<HTMLElement>("[data-note-id]");
  const id = focused ? Number(focused.dataset.noteId) : selectedId.value;
  if (id !== null && writable && !historyState.busy) {
    event.preventDefault();
    emit("edit", id);
  }
}
function removeShortcut(event: KeyboardEvent) {
  if (
    !["Delete", "Backspace"].includes(event.key) ||
    !visibleSelection.value.length ||
    !writable ||
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
    emit(
      "select",
      notes.map((note) => note.id),
    );
    return;
  }
  // Copy, cut and paste are handled by native clipboard events. Preventing
  // their keydown would suppress the browser's clipboard access.
  if (!["d", "z", "y"].includes(key)) return;
  event.preventDefault();
  if (!writable || historyState.busy || event.repeat) return;
  if (key === "d") {
    if (visibleSelection.value.length) emit("duplicate", [...visibleSelection.value]);
  } else historyShortcut(event, key);
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
  if (operation !== "copy" && (!writable || historyState.busy)) return;
  if (operation === "paste") emit("paste", event, pastePoint());
  else if (visibleSelection.value.length) {
    if (operation === "copy") emit("copy", event, [...visibleSelection.value]);
    else emit("cut", event, [...visibleSelection.value]);
  }
}
function shortcut(event: KeyboardEvent) {
  const key = event.key.toLowerCase();
  if (key === "n" && writable && !historyState.busy) {
    event.preventDefault();
    emit("add", {
      x: (view.width / 2 - view.x) / view.zoom - 140,
      y: (view.height / 2 - view.y) / view.zoom - 100,
    });
  }
  if (key === "v") chooseTool("select");
  if (key === "h") chooseTool("pan");
  if (key === "l" && writable && !historyState.busy) chooseTool("connect");
  if (key === "1") fitAll();
}
onMounted(async () => {
  await nextTick();
  fitAll();
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
    <CanvasCursors v-if="cursorEnabled" :container="root" :view="view" :context="context" />
    <div
      v-if="!notes.length"
      class="pointer-events-none absolute inset-0 flex flex-col items-center justify-center gap-3 px-8 pb-20 text-center"
    >
      <StickyNote class="size-9 text-muted-foreground/35" />
      <p class="text-lg font-medium">{{ t("ideation.canvas.empty") }}</p>
      <p class="max-w-sm text-sm text-muted-foreground">
        {{ t(writable ? "ideation.canvas.emptyHelp" : "ideation.readOnly") }}
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
      <template v-if="writable"
        ><div class="mx-0.5 h-6 w-px bg-border" />
        <DockToolButton
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
      <template v-if="writable">
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
