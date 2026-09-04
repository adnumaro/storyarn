import { computed, onMounted, onUnmounted, ref, shallowRef, watch } from "vue";
import type { AreaPlugin } from "rete-area-plugin";
import type { FlowAreaExtra, FlowSchemes } from "../lib/rete-schemes";
import type { FlowCommentsPanelState, FlowCommentThread } from "../../types/comments";
import {
  commentCanvasPoint,
  commentPlacement,
  commentPointFromClient,
  commentScreenPoint,
  draftCommentCanvasPoint,
  type CommentNodeView,
  type CommentPoint,
} from "../lib/comment-geometry";
import { activeFlowPlacement, cancelFlowPlacement } from "../lib/flow-placement-state";
import type { useLive } from "@shared/composables/useLive";

interface CanvasCommentsOptions {
  area: AreaPlugin<FlowSchemes, FlowAreaExtra>;
  container: HTMLElement;
  state: () => FlowCommentsPanelState;
  pins: () => FlowCommentThread[];
  focusThreadId: () => number | null;
  live: ReturnType<typeof useLive>;
}

interface PinDrag {
  thread: FlowCommentThread | null;
  pointerId: number;
  start: CommentPoint;
  position: CommentPoint;
  zoom: number;
  moved: boolean;
}

function editableTarget(target: EventTarget | null): boolean {
  return (
    target instanceof Element &&
    Boolean(
      target.closest(
        'input, textarea, select, [contenteditable="true"], [contenteditable=""], [role="textbox"]',
      ),
    )
  );
}

function outsideCommentDialog(target: EventTarget | null): boolean {
  return (
    target instanceof Element &&
    Boolean(target.closest('[role="dialog"]')) &&
    !target.closest("#flow-comment-popover")
  );
}

function ignoreCommentShortcut(event: KeyboardEvent): boolean {
  return (
    event.defaultPrevented ||
    editableTarget(event.target) ||
    event.altKey ||
    event.ctrlKey ||
    event.metaKey ||
    event.shiftKey ||
    outsideCommentDialog(event.target)
  );
}

export function useCanvasComments(options: CanvasCommentsOptions) {
  const { area, container, live } = options;
  const viewport = shallowRef({ ...area.area.transform });
  const nodeViews = shallowRef<ReadonlyMap<string, CommentNodeView>>(new Map());
  const bounds = shallowRef({ width: 0, height: 0 });
  const hoverId = ref<number | null>(null);
  const drag = shallowRef<PinDrag | null>(null);
  const movedPositions = ref(new Map<number, { position: CommentPoint; revision: number }>());
  const draftPosition = ref<CommentPoint | null>(null);
  const moveError = ref(false);
  let disposed = false;
  let frame: number | null = null;
  let suppressedClick = false;
  let placedPointer: number | null = null;
  let focusedThreadId: number | null = null;
  let observer: ResizeObserver | null = null;
  let surface: HTMLElement | null = null;

  const placing = computed(() => options.state().canComment && Boolean(options.state().placing));
  const selectedThread = computed(() => options.state().thread);
  const visibleThreads = computed(() => {
    const threads = options.pins().filter((thread) => thread.status === "open");
    const selected = selectedThread.value;
    if (options.state().open && selected && !threads.some((thread) => thread.id === selected.id))
      return [...threads, selected];
    return threads;
  });
  const pins = computed(() =>
    visibleThreads.value.flatMap((thread) => {
      const position = movedPositions.value.get(thread.id)?.position ?? thread.position;
      const point = commentCanvasPoint(thread, nodeViews.value, position);
      return point ? [{ thread, point, screen: commentScreenPoint(point, viewport.value) }] : [];
    }),
  );
  const draftPoint = computed(() => {
    const state = options.state();
    const position = draftPosition.value ?? state.draftPosition;
    if (!state.open || state.presentation !== "canvas" || state.thread || !position) return null;
    const point = draftCommentCanvasPoint(position, state.selectedNodeId, nodeViews.value);
    return point ? commentScreenPoint(point, viewport.value) : null;
  });
  const activePoint = computed(() =>
    selectedThread.value
      ? (pins.value.find((pin) => pin.thread.id === selectedThread.value?.id)?.screen ?? null)
      : draftPoint.value,
  );
  const hoveredPin = computed(() => pins.value.find((pin) => pin.thread.id === hoverId.value));

  function focusThread() {
    const id = options.focusThreadId();
    if (id == null) {
      focusedThreadId = null;
      return;
    }
    if (id === focusedThreadId || bounds.value.width === 0) return;
    const thread = visibleThreads.value.find((item) => item.id === id);
    const point = thread && commentCanvasPoint(thread, area.nodeViews);
    if (!point) return;
    focusedThreadId = id;
    const zoom = area.area.transform.k || 1;
    // Leave room for the conversation, without picking the node or acquiring an edit lock.
    void area.area.translate(
      bounds.value.width * 0.4 - point.x * zoom,
      bounds.value.height / 2 - point.y * zoom,
    );
  }

  function refresh() {
    if (disposed) return;
    viewport.value = { ...area.area.transform };
    nodeViews.value = new Map(
      [...area.nodeViews].map(([id, view]) => [id, { position: { ...view.position } }]),
    );
    const rect = container.getBoundingClientRect();
    bounds.value = { width: rect.width, height: rect.height };
    focusThread();
  }

  function scheduleRefresh() {
    if (disposed || frame != null) return;
    frame = requestAnimationFrame(() => {
      frame = null;
      refresh();
    });
  }

  function nodeIdAt(target: EventTarget | null): number | null {
    if (!(target instanceof Element)) return null;
    const raw = target.closest<HTMLElement>("[data-flow-comment-node]")?.dataset.flowCommentNode;
    const id = raw == null ? NaN : Number(raw);
    return Number.isSafeInteger(id) ? id : null;
  }

  function placeAt(event: PointerEvent) {
    if (!placing.value || event.button !== 0 || event.altKey || event.ctrlKey || event.metaKey)
      return;
    if (!(event.target instanceof Element) || !container.contains(event.target)) return;
    if (
      event.target.closest(
        'button, a, input, textarea, select, [contenteditable="true"], [data-flow-interactive="true"], [data-testid="flow-context-menu"], .minimap',
      )
    )
      return;
    event.preventDefault();
    event.stopImmediatePropagation();
    placedPointer = event.pointerId;
    const point = commentPointFromClient(
      { x: event.clientX, y: event.clientY },
      container.getBoundingClientRect(),
      area.area.transform,
    );
    live.pushEvent(
      "comments_place",
      commentPlacement(point, nodeIdAt(event.target), area.nodeViews),
    );
  }

  function finishPlacement(event: PointerEvent) {
    if (placedPointer == null || event.pointerId !== placedPointer) return;
    event.preventDefault();
    event.stopImmediatePropagation();
    placedPointer = null;
  }

  function onKeyDown(event: KeyboardEvent) {
    if (ignoreCommentShortcut(event)) return;
    if (event.key.toLowerCase() === "c" && options.state().canComment) {
      event.preventDefault();
      event.stopImmediatePropagation();
      cancelFlowPlacement();
      live.pushEvent("comments_mode", { active: !placing.value });
    } else if (
      event.key === "Escape" &&
      (placing.value || (options.state().open && options.state().presentation === "canvas"))
    ) {
      event.preventDefault();
      event.stopImmediatePropagation();
      hoverId.value = null;
      live.pushEvent(
        placing.value ? "comments_mode" : "comments_close",
        placing.value ? { active: false } : {},
      );
    }
  }

  function selectThread(thread: FlowCommentThread, event: MouseEvent) {
    if (suppressedClick && event.detail !== 0) {
      suppressedClick = false;
      return;
    }
    suppressedClick = false;
    hoverId.value = null;
    live.pushEvent("comments_select_thread", { thread_id: thread.id, presentation: "canvas" });
  }

  function startDrag(event: PointerEvent, thread: FlowCommentThread | null) {
    if (!options.state().canComment || event.button !== 0) return;
    if (thread && movedPositions.value.has(thread.id)) return;
    const position = dragPositionFor(thread);
    if (!position) return;
    suppressedClick = false;
    moveError.value = false;
    drag.value = {
      thread,
      pointerId: event.pointerId,
      start: { x: event.clientX, y: event.clientY },
      position: { ...position },
      zoom: area.area.transform.k || 1,
      moved: false,
    };
    (event.currentTarget as HTMLElement).setPointerCapture?.(event.pointerId);
  }

  function dragPositionFor(thread: FlowCommentThread | null) {
    if (!thread) return draftPosition.value ?? options.state().draftPosition;
    return thread.position ?? { x: 16, y: 16 };
  }

  function onDragMove(event: PointerEvent) {
    const current = drag.value;
    if (!current || current.pointerId !== event.pointerId) return;
    const dx = event.clientX - current.start.x;
    const dy = event.clientY - current.start.y;
    if (!current.moved && Math.hypot(dx, dy) < 4) return;
    const position = {
      x: current.position.x + dx / current.zoom,
      y: current.position.y + dy / current.zoom,
    };
    drag.value = { ...current, moved: true };
    hoverId.value = null;
    if (current.thread)
      movedPositions.value.set(current.thread.id, { position, revision: current.thread.revision });
    else draftPosition.value = position;
  }

  function onDragEnd(event: PointerEvent) {
    const current = drag.value;
    if (!current || current.pointerId !== event.pointerId) return;
    drag.value = null;
    if (!current.moved) return;
    suppressedClick = event.type !== "pointercancel";
    if (event.type === "pointercancel" || !options.state().canComment) {
      if (current.thread) movedPositions.value.delete(current.thread.id);
      draftPosition.value = null;
      return;
    }
    if (current.thread) persistThreadPosition(current.thread);
    else persistDraftPosition();
  }

  function persistDraftPosition() {
    const position = draftPosition.value;
    if (!position) return;
    const rollbackDraft = () => {
      if (draftPosition.value !== position) return;
      draftPosition.value = null;
      moveError.value = true;
    };
    live.pushEvent(
      "comments_place",
      { node_id: options.state().selectedNodeId, ...position, moving_draft: true },
      (reply) => {
        if (reply.ok !== true) rollbackDraft();
      },
      rollbackDraft,
    );
  }

  function persistThreadPosition({ id, revision }: FlowCommentThread) {
    const position = movedPositions.value.get(id)?.position;
    if (!position) return;
    const rollback = () => {
      if (movedPositions.value.get(id)?.revision !== revision) return;
      movedPositions.value.delete(id);
      moveError.value = true;
    };
    live.pushEvent(
      "comments_move",
      { thread_id: id, ...position, expected_revision: revision },
      (reply) => {
        if (reply.ok !== true) rollback();
      },
      rollback,
    );
  }

  watch(
    () => options.pins().map((thread) => [thread.id, thread.revision]),
    () => {
      for (const [id, pending] of movedPositions.value) {
        const latest = options.pins().find((thread) => thread.id === id);
        if (!latest || latest.revision !== pending.revision) movedPositions.value.delete(id);
      }
      scheduleRefresh();
    },
  );
  watch(
    () => [options.state().draftPosition, options.state().thread?.id],
    () => {
      draftPosition.value = null;
    },
  );
  watch(() => options.focusThreadId(), focusThread);
  watch(
    placing,
    (active) => {
      if (active) cancelFlowPlacement();
      container.style.cursor = active ? "crosshair" : "";
    },
    { immediate: true },
  );
  watch(activeFlowPlacement, (target) => {
    if (target && placing.value) live.pushEvent("comments_mode", { active: false });
  });

  onMounted(() => {
    surface = container.parentElement;
    surface?.addEventListener("pointerdown", placeAt, true);
    surface?.addEventListener("pointerup", finishPlacement, true);
    surface?.addEventListener("pointercancel", finishPlacement, true);
    document.addEventListener("keydown", onKeyDown, true);
    window.addEventListener("pointermove", onDragMove);
    window.addEventListener("pointerup", onDragEnd);
    window.addEventListener("pointercancel", onDragEnd);
    observer = new ResizeObserver(refresh);
    observer.observe(container);
    area.addPipe((context) => {
      if (
        [
          "translated",
          "zoomed",
          "nodetranslated",
          "noderesized",
          "nodecreated",
          "noderemoved",
          "rendered",
        ].includes(context.type)
      )
        scheduleRefresh();
      return context;
    });
    refresh();
  });
  onUnmounted(() => {
    disposed = true;
    if (frame != null) cancelAnimationFrame(frame);
    observer?.disconnect();
    surface?.removeEventListener("pointerdown", placeAt, true);
    surface?.removeEventListener("pointerup", finishPlacement, true);
    surface?.removeEventListener("pointercancel", finishPlacement, true);
    document.removeEventListener("keydown", onKeyDown, true);
    window.removeEventListener("pointermove", onDragMove);
    window.removeEventListener("pointerup", onDragEnd);
    window.removeEventListener("pointercancel", onDragEnd);
    container.style.cursor = "";
  });

  return {
    pins,
    placing,
    bounds,
    hoverId,
    hoveredPin,
    activePoint,
    draftPoint,
    moveError,
    selectThread,
    startDrag,
  };
}
