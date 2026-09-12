import { computed, onMounted, onUnmounted, ref, shallowRef, watch } from "vue";
import type { CommentContextReference } from "@components/comments/types";
import { commentContextCycleDirection } from "@components/comments/commentKeyboard";
import type { AreaPlugin } from "rete-area-plugin";
import {
  CommentMagneticDrag,
  type CommentMagneticInitial,
  type CommentMagneticPreview,
} from "@components/comments/commentMagnetism";
import type { FlowAreaExtra, FlowSchemes } from "../lib/rete-schemes";
import type { FlowCommentsPanelState, FlowCommentThread } from "../../types/comments";
import {
  commentCanvasPoint,
  commentPointFromClient,
  commentScreenPoint,
  draftCommentCanvasPoint,
  type CommentNodeView,
  type CommentPoint,
} from "../lib/comment-geometry";
import { flowCommentSnapAdapter, resolveFlowCommentPosition } from "../lib/comment-snap-adapter";
import { activeFlowPlacement, cancelFlowPlacement } from "../lib/flow-placement-state";
import { useFlowCommentDraftRecovery } from "./useFlowCommentDraftRecovery";
import type { useLive } from "@shared/composables/useLive";

interface CanvasCommentsOptions {
  area: AreaPlugin<FlowSchemes, FlowAreaExtra>;
  container: HTMLElement;
  state: () => FlowCommentsPanelState;
  pins: () => FlowCommentThread[];
  focusThreadId: () => number | null;
  draftStorageKey: () => string | null;
  live: ReturnType<typeof useLive>;
}

interface PinDrag {
  thread: FlowCommentThread | null;
  draftId: string | null;
  pointerId: number | null;
  target: HTMLElement;
  start: CommentPoint;
  pointer: CommentPoint;
  session: CommentMagneticDrag;
  moved: boolean;
}
interface PendingMove extends CommentMagneticInitial {
  request: number;
  revision: number;
}
interface PendingDraft extends CommentMagneticInitial {
  request: number;
  draftId: string | null;
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
const keyboardDirections: Partial<Record<string, CommentPoint>> = {
  ArrowLeft: { x: -1, y: 0 },
  ArrowRight: { x: 1, y: 0 },
  ArrowUp: { x: 0, y: -1 },
  ArrowDown: { x: 0, y: 1 },
};
function ignorePinShortcut(event: KeyboardEvent): boolean {
  return editableTarget(event.target) || event.ctrlKey || event.metaKey;
}

export function useCanvasComments(options: CanvasCommentsOptions) {
  const { area, container, live } = options;
  const adapter = flowCommentSnapAdapter(area, container);
  const viewport = shallowRef({ ...area.area.transform });
  const nodeViews = shallowRef<ReadonlyMap<string, CommentNodeView>>(new Map());
  const bounds = ref({ width: 1, height: 1 });
  const hoverId = ref<number | null>(null);
  const drag = shallowRef<PinDrag | null>(null);
  const dragPreview = shallowRef<CommentMagneticPreview | null>(null);
  const pendingMoves = ref(new Map<number, PendingMove>());
  const pendingDraft = shallowRef<PendingDraft | null>(null);
  const magnetism = ref(true);
  const moveError = ref(false);
  let request = 0;
  let altHeld = false;
  let disposed = false;
  let frame: number | null = null;
  let suppressedClick = false;
  let placedPointer: number | null = null;
  let focusedThreadId: number | null = null;
  let observer: ResizeObserver | null = null;
  let targetObserver: MutationObserver | null = null;
  let surface: HTMLElement | null = null;

  const placing = computed(() => options.state().canComment && options.state().placing === true);
  const selectedThread = computed(() => options.state().thread);
  const visibleThreads = computed(() => {
    const selected = options.state().open ? selectedThread.value : null;
    const visible = options.pins().filter((thread) => thread.status === "open");
    return selected && !visible.some((thread) => thread.id === selected.id)
      ? [...visible, selected]
      : visible;
  });
  const pins = computed(() =>
    visibleThreads.value.flatMap((thread) => {
      const pending = pendingMoves.value.get(thread.id);
      const moving = drag.value?.thread?.id === thread.id ? dragPreview.value : null;
      const point = moving?.position ?? pending?.position ?? threadPoint(thread);
      return point && thread.source.status === "available"
        ? [{ thread, point, screen: commentScreenPoint(point, viewport.value) }]
        : [];
    }),
  );

  function threadPoint(thread: FlowCommentThread) {
    void nodeViews.value;
    return thread.source.type === "flow_canvas" && thread.position
      ? resolveFlowCommentPosition(thread.position, thread.context, area, container)
      : commentCanvasPoint(thread, area.nodeViews);
  }
  function currentDraft(): CommentMagneticInitial | null {
    void nodeViews.value;
    const state = options.state();
    if (!state.open || state.presentation !== "canvas" || state.thread || !state.draftPosition)
      return null;
    const position = draftCommentCanvasPoint(
      state.draftPosition,
      state.selectedNodeId,
      area.nodeViews,
    );
    if (!position) return null;
    const context =
      state.selectedNodeId == null
        ? (state.draftContext ?? null)
        : {
            type: "flow_node",
            id: String(state.selectedNodeId),
            offset: state.draftPosition,
          };
    const resolved = resolveFlowCommentPosition(position, context, area, container);
    return resolved ? { position: resolved, context } : null;
  }
  const { restoreStoredDraft } = useFlowCommentDraftRecovery({
    state: options.state,
    storageKey: options.draftStorageKey,
    placement: currentDraft,
    ready: () =>
      bounds.value.width > 0 && bounds.value.height > 0 && options.focusThreadId() == null,
    live,
  });
  const draftPoint = computed(() => {
    // Node snapshots make legacy relative drafts reactive to canvas changes.
    void nodeViews.value;
    const confirmed = currentDraft();
    if (!confirmed) return null;
    const moving = drag.value && !drag.value.thread ? dragPreview.value : null;
    return commentScreenPoint((moving ?? pendingDraft.value ?? confirmed).position, viewport.value);
  });
  const panelState = computed<FlowCommentsPanelState>(() => {
    const state = options.state();
    const moving = drag.value && !drag.value.thread ? dragPreview.value : null;
    void nodeViews.value;
    const confirmed = currentDraft();
    const draft = moving ?? pendingDraft.value ?? confirmed;
    return {
      ...state,
      ...(draft
        ? { draftPosition: draft.position, draftContext: draft.context, selectedNodeId: null }
        : {}),
      draftPending: Boolean(moving || pendingDraft.value),
    };
  });
  const activePoint = computed(() => {
    const selected = selectedThread.value;
    return selected
      ? (pins.value.find((pin) => pin.thread.id === selected.id)?.screen ?? null)
      : draftPoint.value;
  });
  const hoveredPin = computed(() =>
    drag.value ? null : (pins.value.find((pin) => pin.thread.id === hoverId.value) ?? null),
  );
  const snapOutline = computed(() => {
    const geometry = dragPreview.value?.candidate?.geometry;
    if (geometry?.kind !== "rect") return null;
    const rect = container.getBoundingClientRect();
    return {
      left: geometry.left - rect.left,
      top: geometry.top - rect.top,
      width: geometry.width,
      height: geometry.height,
    };
  });
  const moving = computed(() => Boolean(drag.value?.moved));
  const keyboardDragging = computed(() => drag.value?.pointerId === null);
  const isPending = (id: number) => pendingMoves.value.has(id);

  function focusThread() {
    const id = options.focusThreadId();
    if (id == null) {
      focusedThreadId = null;
      return;
    }
    if (id === focusedThreadId) return;
    const thread = visibleThreads.value.find((item) => item.id === id);
    const point = thread && commentCanvasPoint(thread, area.nodeViews);
    if (!point) return;
    focusedThreadId = id;
    const rect = container.getBoundingClientRect();
    const zoom = area.area.transform.k || 1;
    void area.area.translate(rect.width * 0.4 - point.x * zoom, rect.height / 2 - point.y * zoom);
  }
  function refresh() {
    if (disposed) return;
    viewport.value = { ...area.area.transform };
    nodeViews.value = new Map(
      [...area.nodeViews.entries()].map(([id, view]) => [id, { position: { ...view.position } }]),
    );
    const rect = container.getBoundingClientRect();
    bounds.value = { width: rect.width, height: rect.height };
    if (drag.value?.moved) updatePreview();
    focusThread();
  }
  function scheduleRefresh() {
    if (disposed || frame != null) return;
    frame = requestAnimationFrame(() => {
      frame = null;
      refresh();
    });
  }

  function placeAt(event: PointerEvent) {
    if (!placing.value || event.button !== 0 || event.ctrlKey || event.metaKey) return;
    if (
      event.target instanceof Element &&
      event.target.closest(
        'button, a, input, textarea, select, [contenteditable], [data-flow-interactive], [data-testid="flow-context-menu"], [data-testid="minimap"]',
      )
    )
      return;
    event.preventDefault();
    event.stopImmediatePropagation();
    placedPointer = event.pointerId;
    const pointer = { x: event.clientX, y: event.clientY };
    const position = commentPointFromClient(
      pointer,
      container.getBoundingClientRect(),
      area.area.transform,
    );
    const session = new CommentMagneticDrag(adapter, { position, context: null }, pointer);
    const preview = session.update(pointer, !magnetism.value || event.altKey);
    live.pushEvent("comments_place", {
      node_id: null,
      ...preview.position,
      context: preview.context,
    });
  }
  function finishPlacement(event: PointerEvent) {
    if (placedPointer !== event.pointerId) return;
    placedPointer = null;
    event.preventDefault();
    event.stopImmediatePropagation();
  }

  function handleDragKey(event: KeyboardEvent): boolean {
    if (!drag.value) return false;
    if (event.key === "Escape") {
      cancelDrag();
      return true;
    }
    if (editableTarget(event.target)) return false;
    if (event.key === "Alt") {
      altHeld = true;
      updatePreview();
    }
    const cycleDirection = commentContextCycleDirection(event);
    if (cycleDirection != null) {
      cycleContext(cycleDirection);
      return true;
    }
    if (event.key === "Enter" && drag.value.pointerId == null) {
      commitDrag();
      return true;
    }
    return false;
  }
  function canvasCommentsOpen() {
    return options.state().open && options.state().presentation === "canvas";
  }
  function onKeyDown(event: KeyboardEvent) {
    if (handleDragKey(event)) {
      event.preventDefault();
      event.stopImmediatePropagation();
      return;
    }
    if (ignoreCommentShortcut(event)) return;
    if (event.key.toLowerCase() === "c" && options.state().canComment) {
      event.preventDefault();
      cancelFlowPlacement();
      live.pushEvent("comments_mode", { active: !placing.value });
    } else if (event.key === "Escape" && (placing.value || canvasCommentsOpen())) {
      event.preventDefault();
      hoverId.value = null;
      live.pushEvent(
        placing.value ? "comments_mode" : "comments_close",
        placing.value ? { active: false } : {},
      );
    }
  }
  function onKeyUp(event: KeyboardEvent) {
    if (event.key === "Alt") {
      altHeld = false;
      if (drag.value?.moved) updatePreview();
    }
  }
  function selectThread(thread: FlowCommentThread, event?: MouseEvent) {
    if (suppressedClick && event?.detail) {
      suppressedClick = false;
      return;
    }
    suppressedClick = false;
    live.pushEvent("comments_select_thread", { thread_id: thread.id, presentation: "canvas" });
  }
  function dragInitial(thread: FlowCommentThread | null): CommentMagneticInitial | null {
    if (!thread) return currentDraft();
    const position = threadPoint(thread);
    return position ? { position, context: thread.context ?? null } : null;
  }
  function beginDrag(
    target: HTMLElement,
    thread: FlowCommentThread | null,
    pointerId: number | null,
    pointer?: CommentPoint,
  ) {
    if (drag.value || !options.state().canComment) return false;
    if (thread ? isPending(thread.id) : pendingDraft.value) return false;
    const initial = dragInitial(thread);
    if (!initial) return false;
    const { position, context } = initial;
    const start = pointer ?? adapter.toScreen(position);
    drag.value = {
      thread,
      draftId: options.state().draftId ?? null,
      pointerId,
      target,
      start,
      pointer: start,
      session: new CommentMagneticDrag(adapter, { position, context }, start),
      moved: false,
    };
    dragPreview.value = null;
    suppressedClick = false;
    moveError.value = false;
    return true;
  }
  function startDrag(event: PointerEvent, thread: FlowCommentThread | null) {
    if (event.button !== 0) return;
    const target = event.currentTarget as HTMLElement;
    if (!beginDrag(target, thread, event.pointerId, { x: event.clientX, y: event.clientY })) return;
    event.preventDefault();
    altHeld = event.altKey;
    target.focus({ preventScroll: true });
    target.setPointerCapture?.(event.pointerId);
  }
  function updatePreview() {
    const current = drag.value;
    if (!current) return;
    dragPreview.value = current.session.update(current.pointer, !magnetism.value || altHeld);
    hoverId.value = null;
  }
  function onDragMove(event: PointerEvent) {
    const current = drag.value;
    if (!current || current.pointerId !== event.pointerId) return;
    const pointer = { x: event.clientX, y: event.clientY };
    if (!current.moved && Math.hypot(pointer.x - current.start.x, pointer.y - current.start.y) < 4)
      return;
    event.preventDefault();
    altHeld = event.altKey;
    drag.value = { ...current, pointer, moved: true };
    updatePreview();
  }
  function onPinKeyDown(event: KeyboardEvent, thread: FlowCommentThread | null) {
    const direction = keyboardDirections[event.key];
    if (!direction || ignorePinShortcut(event) || !options.state().canComment) return;
    const target = event.currentTarget as HTMLElement;
    if (!drag.value && !beginDrag(target, thread, null)) return;
    const current = drag.value;
    if (!current || current.pointerId != null || current.target !== target) return;
    event.preventDefault();
    event.stopPropagation();
    const step = event.shiftKey ? 1 : 10;
    altHeld = event.altKey;
    drag.value = {
      ...current,
      moved: true,
      pointer: {
        x: current.pointer.x + direction.x * step,
        y: current.pointer.y + direction.y * step,
      },
    };
    updatePreview();
  }
  function onPinBlur() {
    hoverId.value = null;
    if (drag.value?.pointerId === null) cancelDrag();
  }
  function endSession() {
    const current = drag.value;
    drag.value = null;
    dragPreview.value = null;
    if (current?.pointerId != null && current.target.hasPointerCapture?.(current.pointerId))
      current.target.releasePointerCapture(current.pointerId);
    hoverId.value = null;
    return current;
  }
  function cancelDrag() {
    if (drag.value?.moved && drag.value.pointerId != null) suppressedClick = true;
    drag.value?.session.cancel();
    endSession();
  }
  function onLostCapture(event: PointerEvent) {
    if (drag.value?.pointerId === event.pointerId) cancelDrag();
  }
  function onDragEnd(event: PointerEvent) {
    if (!drag.value || drag.value.pointerId !== event.pointerId) return;
    if (event.type === "pointercancel") cancelDrag();
    else {
      onDragMove(event);
      commitDrag();
    }
  }
  function commitDrag() {
    const current = drag.value;
    if (!current) return;
    // Re-read transforms and targets at commit, including a node deleted during this gesture.
    if (current.moved) updatePreview();
    const preview = dragPreview.value;
    endSession();
    if (current.thread) hoverId.value = current.thread.id;
    if (!current.moved || !preview || !options.state().canComment) return;
    suppressedClick = current.pointerId != null;
    if (current.thread) persistThread(current.thread, preview);
    else persistDraft(current.draftId, preview);
  }
  function persistDraft(draftId: string | null, preview: CommentMagneticInitial) {
    const pending = { ...preview, draftId, request: ++request };
    pendingDraft.value = pending;
    const rollback = () => {
      if (disposed || pendingDraft.value?.request !== pending.request) return;
      pendingDraft.value = null;
      moveError.value = true;
    };
    live.pushEvent(
      "comments_place",
      {
        node_id: null,
        ...preview.position,
        context: preview.context,
        moving_draft: true,
        draft_id: draftId,
      },
      (reply) => {
        if (reply.ok !== true) rollback();
        else if (pendingDraft.value?.request === pending.request) confirmDraft();
      },
      rollback,
    );
  }
  function persistThread(thread: FlowCommentThread, preview: CommentMagneticInitial) {
    const pending = { ...preview, request: ++request, revision: thread.revision };
    pendingMoves.value.set(thread.id, pending);
    const finish = (failed: boolean, returned?: FlowCommentThread) => {
      if (disposed || pendingMoves.value.get(thread.id)?.request !== pending.request) return;
      const latest = visibleThreads.value.find((item) => item.id === thread.id);
      const unchanged = acknowledgedUnchanged(returned, pending, latest);
      if (failed || !latest || latest.revision !== pending.revision || unchanged)
        pendingMoves.value.delete(thread.id);
      if (failed) moveError.value = true;
    };
    // Legacy payloads are readable during rollout; canonical threads always use absolute coordinates.
    const legacyNode =
      thread.source.type === "flow_node" ? area.nodeViews.get(`node-${thread.source.id}`) : null;
    const position = legacyNode
      ? {
          x: preview.position.x - legacyNode.position.x,
          y: preview.position.y - legacyNode.position.y,
        }
      : preview.position;
    live.pushEvent(
      "comments_move",
      {
        thread_id: thread.id,
        ...position,
        expected_revision: thread.revision,
        ...(thread.source.type === "flow_canvas" ? { context: preview.context } : {}),
      },
      (reply) => finish(reply.ok !== true, reply.thread as FlowCommentThread | undefined),
      () => finish(true),
    );
  }
  function toggleMagnetism() {
    magnetism.value = !magnetism.value;
    if (drag.value?.moved) updatePreview();
  }
  function cycleContext(direction: 1 | -1 = 1) {
    if (!drag.value?.moved || !magnetism.value || altHeld) return;
    dragPreview.value = drag.value.session.cycle(direction);
  }

  watch(
    () => [
      options.pins().map((thread) => [thread.id, thread.revision]),
      selectedThread.value?.revision,
    ],
    () => {
      for (const [id, pending] of pendingMoves.value) {
        const latest = visibleThreads.value.find((thread) => thread.id === id);
        if (!latest || latest.revision !== pending.revision) pendingMoves.value.delete(id);
      }
      const active = drag.value?.thread;
      if (
        active &&
        !visibleThreads.value.some(
          (thread) => thread.id === active.id && thread.revision === active.revision,
        )
      )
        cancelDrag();
      scheduleRefresh();
    },
  );
  function contextIdentity(context: CommentContextReference | null | undefined) {
    return context
      ? JSON.stringify([context.type, context.id, context.offset?.x, context.offset?.y])
      : null;
  }
  function samePlacement(thread: FlowCommentThread | undefined, placement: CommentMagneticInitial) {
    return (
      thread?.position?.x === placement.position.x &&
      thread.position.y === placement.position.y &&
      contextIdentity(thread.context) === contextIdentity(placement.context)
    );
  }
  function acknowledgedUnchanged(
    returned: FlowCommentThread | undefined,
    pending: PendingMove,
    latest: FlowCommentThread | undefined,
  ) {
    return (
      returned?.revision === pending.revision &&
      samePlacement(returned, pending) &&
      samePlacement(latest, pending)
    );
  }
  function confirmDraft() {
    const pending = pendingDraft.value;
    if (!pending) return;
    const state = options.state();
    const matches =
      state.draftId === pending.draftId &&
      state.selectedNodeId == null &&
      state.draftPosition?.x === pending.position.x &&
      state.draftPosition?.y === pending.position.y &&
      contextIdentity(state.draftContext) === contextIdentity(pending.context);
    if (matches) pendingDraft.value = null;
  }
  watch(() => [options.state().draftPosition, options.state().draftContext], confirmDraft);
  watch(
    () => [options.state().draftId, options.state().open, options.state().thread?.id],
    () => {
      if (
        pendingDraft.value &&
        (!options.state().open ||
          options.state().draftId !== pendingDraft.value.draftId ||
          options.state().thread)
      )
        pendingDraft.value = null;
      if (
        drag.value &&
        !drag.value.thread &&
        (!currentDraft() || options.state().draftId !== drag.value.draftId)
      )
        cancelDrag();
    },
  );
  watch(
    () => options.state().canComment,
    (allowed) => {
      if (!allowed) cancelDrag();
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
    document.addEventListener("keyup", onKeyUp, true);
    window.addEventListener("pointermove", onDragMove);
    window.addEventListener("pointerup", onDragEnd);
    window.addEventListener("pointercancel", onDragEnd);
    window.addEventListener("blur", cancelDrag);
    observer = new ResizeObserver(refresh);
    observer.observe(container);
    targetObserver = new MutationObserver(scheduleRefresh);
    targetObserver.observe(container, {
      childList: true,
      subtree: true,
      attributes: true,
      attributeFilter: [
        "hidden",
        "aria-hidden",
        "inert",
        "style",
        "class",
        "data-flow-comment-label",
      ],
    });
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
    restoreStoredDraft();
  });
  onUnmounted(() => {
    disposed = true;
    cancelDrag();
    if (frame != null) cancelAnimationFrame(frame);
    observer?.disconnect();
    targetObserver?.disconnect();
    surface?.removeEventListener("pointerdown", placeAt, true);
    surface?.removeEventListener("pointerup", finishPlacement, true);
    surface?.removeEventListener("pointercancel", finishPlacement, true);
    document.removeEventListener("keydown", onKeyDown, true);
    document.removeEventListener("keyup", onKeyUp, true);
    window.removeEventListener("pointermove", onDragMove);
    window.removeEventListener("pointerup", onDragEnd);
    window.removeEventListener("pointercancel", onDragEnd);
    window.removeEventListener("blur", cancelDrag);
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
    panelState,
    magnetism,
    moving,
    keyboardDragging,
    dragPreview,
    snapOutline,
    isPending,
    selectThread,
    startDrag,
    onPinKeyDown,
    onPinBlur,
    onLostCapture,
    toggleMagnetism,
    cycleContext,
  };
}
