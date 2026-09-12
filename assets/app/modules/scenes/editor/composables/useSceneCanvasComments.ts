import { computed, onMounted, onUnmounted, ref, shallowRef, watch } from "vue";
import type { useLive } from "@shared/composables/useLive";
import type { SceneCommentsPanelState, SceneCommentThread } from "../../types/comments";
import {
  sceneCommentCanvasPoint,
  sceneCommentPointFromClient,
  sceneCommentScreenPoint,
  type SceneCommentProjection,
  type SceneCommentStageTransform,
} from "../lib/comment-geometry";
import {
  CommentMagneticDrag,
  type CommentMagneticInitial,
  type CommentMagneticPreview,
} from "@components/comments/commentMagnetism";
import type { CommentContextReference } from "@components/comments/types";
import { commentContextCycleDirection } from "@components/comments/commentKeyboard";
import {
  sceneCommentSnapAdapter,
  resolveSceneCommentPosition,
  type SceneCommentTargets,
} from "../lib/comment-snap-adapter";
import { useSceneCommentDraftRecovery } from "./useSceneCommentDraftRecovery";
import type { SceneCommentPosition } from "../../types/comments";

interface SceneCanvasCommentsOptions {
  container: HTMLElement;
  stage: SceneCommentStageTransform;
  projection: SceneCommentProjection;
  backgroundSettled: () => boolean;
  state: () => SceneCommentsPanelState;
  pins: () => SceneCommentThread[];
  focusThreadId: () => number | null;
  targets: () => SceneCommentTargets;
  draftStorageKey: () => string | null;
  live: ReturnType<typeof useLive>;
}

interface PinDrag {
  thread: SceneCommentThread | null;
  draftId: string | null;
  pointerId: number | null;
  target: HTMLElement;
  start: SceneCommentPosition;
  pointer: SceneCommentPosition;
  session: CommentMagneticDrag;
  moved: boolean;
}
interface PendingMove extends CommentMagneticInitial {
  request: number;
  revision: number;
}
interface DraftAcknowledgement extends CommentMagneticInitial {
  id: string | null;
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
    !target.closest("#scene-comment-popover")
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

function interactiveTarget(target: EventTarget | null): boolean {
  return (
    target instanceof Element &&
    Boolean(
      target.closest(
        'button, a, input, textarea, select, [contenteditable="true"], [data-scene-comment-ui="true"]',
      ),
    )
  );
}

const keyboardDirections: Partial<Record<string, SceneCommentPosition>> = {
  ArrowLeft: { x: -1, y: 0 },
  ArrowRight: { x: 1, y: 0 },
  ArrowUp: { x: 0, y: -1 },
  ArrowDown: { x: 0, y: 1 },
};
function ignorePinShortcut(event: KeyboardEvent): boolean {
  return editableTarget(event.target) || event.ctrlKey || event.metaKey;
}

export function useSceneCanvasComments(options: SceneCanvasCommentsOptions) {
  const { container, stage, projection, live } = options;
  const adapter = sceneCommentSnapAdapter({
    container: () => container,
    stage: () => stage,
    projection: () => projection,
    targets: options.targets,
  });
  const bounds = shallowRef({ width: 0, height: 0 });
  const hoverId = ref<number | null>(null);
  const drag = shallowRef<PinDrag | null>(null);
  const dragPreview = shallowRef<CommentMagneticPreview | null>(null);
  const pendingMoves = ref(new Map<number, PendingMove>());
  const pendingDraft = shallowRef<PendingDraft | null>(null);
  const magnetism = ref(true);
  const contextPosition = ref<SceneCommentPosition | null>(null);
  const contextMenuPoint = ref<SceneCommentPosition | null>(null);
  const moveError = ref(false);
  let request = 0;
  let altHeld = false;
  let disposed = false;
  let suppressedClick = false;
  let placedPointer: number | null = null;
  let placedClickTimer: ReturnType<typeof setTimeout> | null = null;
  let consumePlacedClick = false;
  let contextPointer: number | null = null;
  let contextClickTimer: ReturnType<typeof setTimeout> | null = null;
  let consumeContextClick = false;
  let focusedThreadId: number | null = null;
  let observer: ResizeObserver | null = null;

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
      const pending = pendingMoves.value.get(thread.id);
      const moving = drag.value?.thread?.id === thread.id ? dragPreview.value : null;
      const point = moving?.position ?? pending?.position ?? threadPoint(thread);
      return point && thread.source.status === "available"
        ? [{ thread, point, screen: sceneCommentScreenPoint(point, stage, projection) }]
        : [];
    }),
  );
  function threadPoint(thread: SceneCommentThread) {
    const position = sceneCommentCanvasPoint(thread);
    return resolveSceneCommentPosition(position, thread.context, options.targets(), projection);
  }
  function currentDraft(): CommentMagneticInitial | null {
    const state = options.state();
    if (!state.open || state.presentation !== "canvas" || state.thread || !state.draftPosition)
      return null;
    const context = state.draftContext ?? null;
    const position = resolveSceneCommentPosition(
      state.draftPosition,
      context,
      options.targets(),
      projection,
    );
    return position ? { position, context } : null;
  }
  const { restoreStoredDraft, discardStoredDraft } = useSceneCommentDraftRecovery({
    state: options.state,
    storageKey: options.draftStorageKey,
    placement: currentDraft,
    ready: () =>
      bounds.value.width > 0 &&
      bounds.value.height > 0 &&
      options.backgroundSettled() &&
      options.focusThreadId() == null,
    live,
  });
  const draftPoint = computed(() => {
    const confirmed = currentDraft();
    if (!confirmed) return null;
    const moving = drag.value && !drag.value.thread ? dragPreview.value : null;
    return sceneCommentScreenPoint(
      (moving ?? pendingDraft.value ?? confirmed).position,
      stage,
      projection,
    );
  });
  const panelState = computed<SceneCommentsPanelState>(() => {
    const moving = drag.value && !drag.value.thread ? dragPreview.value : null;
    const draft = moving ?? pendingDraft.value ?? currentDraft();
    return {
      ...options.state(),
      ...(draft ? { draftPosition: draft.position, draftContext: draft.context } : {}),
      draftPending: Boolean(moving || pendingDraft.value),
    };
  });
  const activePoint = computed(() =>
    selectedThread.value
      ? (pins.value.find((pin) => pin.thread.id === selectedThread.value?.id)?.screen ?? null)
      : draftPoint.value,
  );
  const hoveredPin = computed(() =>
    drag.value ? null : pins.value.find((pin) => pin.thread.id === hoverId.value),
  );
  const moving = computed(() => Boolean(drag.value?.moved));
  const keyboardDragging = computed(() => drag.value?.pointerId === null);
  const isPending = (id: number) => pendingMoves.value.has(id);
  const snapOutline = computed(() => {
    const geometry = dragPreview.value?.candidate?.geometry;
    if (!geometry) return null;
    const rect = container.getBoundingClientRect();
    if (geometry.kind === "rect")
      return { ...geometry, left: geometry.left - rect.left, top: geometry.top - rect.top };
    if (geometry.kind === "point")
      return { ...geometry, x: geometry.x - rect.left, y: geometry.y - rect.top };
    return {
      ...geometry,
      points: geometry.points.map((p) => ({ x: p.x - rect.left, y: p.y - rect.top })),
    };
  });
  function pointFromClient(clientX: number, clientY: number): SceneCommentPosition {
    return sceneCommentPointFromClient(
      { x: clientX, y: clientY },
      container.getBoundingClientRect(),
      stage,
      projection,
    );
  }

  function focusThread(): void {
    const id = options.focusThreadId();
    if (id == null) {
      focusedThreadId = null;
      return;
    }
    if (
      id === focusedThreadId ||
      bounds.value.width === 0 ||
      bounds.value.height === 0 ||
      !options.backgroundSettled()
    )
      return;

    const thread = visibleThreads.value.find((item) => item.id === id);
    const point = thread && threadPoint(thread);
    if (!point) return;

    const world = projection.percentToPixel(point.x, point.y);
    focusedThreadId = id;
    stage.x = bounds.value.width * 0.4 - world.x * (stage.scaleX || 1);
    stage.y = bounds.value.height / 2 - world.y * (stage.scaleY || 1);
  }

  function refreshBounds(): void {
    if (disposed) return;
    const rect = container.getBoundingClientRect();
    bounds.value = { width: rect.width, height: rect.height };
    focusThread();
    restoreStoredDraft();
  }

  function canvasTarget(event: MouseEvent): event is MouseEvent & { target: Element } {
    if (!(event.target instanceof Element) || !container.contains(event.target)) return false;
    return (
      !interactiveTarget(event.target) &&
      Boolean(event.target.closest("canvas, [data-scene-element]"))
    );
  }

  function contextButtonGesture(event: MouseEvent): boolean {
    return event.button === 2 || (event.button === 0 && event.ctrlKey);
  }

  function commentGeometryReady(): boolean {
    return options.state().canComment && options.backgroundSettled();
  }

  function onCanvasPointerDown(event: PointerEvent): void {
    if (!canvasTarget(event)) return;
    if (options.state().canComment && contextButtonGesture(event)) {
      event.preventDefault();
      event.stopImmediatePropagation();
      contextPointer = event.pointerId;
      consumeContextClick = true;
      return;
    }
    if (!placing.value || event.button !== 0 || event.ctrlKey || event.metaKey) return;

    event.preventDefault();
    event.stopImmediatePropagation();
    placedPointer = event.pointerId;
    consumePlacedClick = true;
    if (!options.backgroundSettled()) return;
    const position = pointFromClient(event.clientX, event.clientY);
    placeAt(position, { x: event.clientX, y: event.clientY }, event.altKey);
  }

  function blockContextMouseCompatibility(event: MouseEvent): void {
    if (!options.state().canComment || !contextButtonGesture(event) || !canvasTarget(event)) return;
    event.preventDefault();
    event.stopImmediatePropagation();
    consumeContextClick = true;
  }

  function finishCanvasPointer(event: PointerEvent): void {
    if (contextPointer != null && event.pointerId === contextPointer) {
      event.stopImmediatePropagation();
      contextPointer = null;
      if (contextClickTimer) clearTimeout(contextClickTimer);
      contextClickTimer = setTimeout(() => {
        consumeContextClick = false;
        contextClickTimer = null;
      }, 0);
      return;
    }
    if (placedPointer != null && event.pointerId === placedPointer) {
      event.preventDefault();
      event.stopImmediatePropagation();
      placedPointer = null;
      if (placedClickTimer) clearTimeout(placedClickTimer);
      placedClickTimer = setTimeout(() => {
        consumePlacedClick = false;
        placedClickTimer = null;
      }, 0);
    }
  }

  function finishCanvasClick(event: MouseEvent): void {
    const placedClick = consumePlacedClick && event.button === 0 && !event.ctrlKey;
    const contextClick = consumeContextClick && (event.button === 2 || event.ctrlKey);
    if ((!placedClick && !contextClick) || !canvasTarget(event)) return;
    event.preventDefault();
    event.stopImmediatePropagation();
  }

  function onContextMenu(event: MouseEvent): void {
    if (!options.state().canComment || !canvasTarget(event)) return;
    event.preventDefault();
    event.stopImmediatePropagation();
    if (!options.backgroundSettled()) return;
    const rect = container.getBoundingClientRect();
    contextPosition.value = pointFromClient(event.clientX, event.clientY);
    contextMenuPoint.value = {
      x: event.clientX - rect.left,
      y: event.clientY - rect.top,
    };
  }

  function placeContextComment(): void {
    if (!commentGeometryReady() || !contextPosition.value) {
      closeContextMenu();
      return;
    }
    placeAt(contextPosition.value, adapter.toScreen(contextPosition.value));
    contextPosition.value = null;
    contextMenuPoint.value = null;
  }

  function closeContextMenu(): void {
    contextPosition.value = null;
    contextMenuPoint.value = null;
  }

  function closeContextMenuFromOutside(event: PointerEvent): void {
    if (!contextMenuPoint.value) return;
    if (event.target instanceof Element && event.target.closest("#scene-comment-context-menu"))
      return;
    closeContextMenu();
  }

  function closeActiveComments(event: KeyboardEvent): void {
    if (!placing.value && (!options.state().open || options.state().presentation !== "canvas"))
      return;
    event.preventDefault();
    event.stopImmediatePropagation();
    hoverId.value = null;
    if (!placing.value) discardStoredDraft();
    live.pushEvent(
      placing.value ? "comments_mode" : "comments_close",
      placing.value ? { active: false } : {},
    );
  }

  function onKeyDown(event: KeyboardEvent): void {
    if (handleDragKey(event)) {
      event.preventDefault();
      event.stopImmediatePropagation();
      return;
    }
    if (ignoreCommentShortcut(event)) return;
    if (event.key === "Escape") {
      if (contextMenuPoint.value) {
        event.preventDefault();
        event.stopImmediatePropagation();
        closeContextMenu();
      } else closeActiveComments(event);
      return;
    }
    if (event.key.toLowerCase() === "c" && options.state().canComment) {
      event.preventDefault();
      event.stopImmediatePropagation();
      live.pushEvent("comments_mode", { active: !placing.value });
    }
  }

  function placeAt(position: SceneCommentPosition, pointer: SceneCommentPosition, free = false) {
    const session = new CommentMagneticDrag(adapter, { position, context: null }, pointer);
    const preview = session.update(pointer, !magnetism.value || free);
    live.pushEvent("comments_place", { ...preview.position, context: preview.context });
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
  function onKeyUp(event: KeyboardEvent) {
    if (event.key === "Alt") {
      altHeld = false;
      if (drag.value?.moved) updatePreview();
    }
  }
  function selectThread(thread: SceneCommentThread, event: MouseEvent): void {
    if (suppressedClick && event.detail !== 0) {
      suppressedClick = false;
      return;
    }
    suppressedClick = false;
    hoverId.value = null;
    discardStoredDraft();
    live.pushEvent("comments_select_thread", { thread_id: thread.id, presentation: "canvas" });
  }

  function dragInitial(thread: SceneCommentThread | null): CommentMagneticInitial | null {
    if (!thread) return currentDraft();
    const position = threadPoint(thread);
    return position ? { position, context: thread.context ?? null } : null;
  }
  function beginDrag(
    target: HTMLElement,
    thread: SceneCommentThread | null,
    pointerId: number | null,
    pointer?: SceneCommentPosition,
  ) {
    if (drag.value || !commentGeometryReady()) return false;
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
  function startDrag(event: PointerEvent, thread: SceneCommentThread | null) {
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
    if (!options.backgroundSettled()) {
      cancelDrag();
      return;
    }
    const pointer = { x: event.clientX, y: event.clientY };
    if (!current.moved && Math.hypot(pointer.x - current.start.x, pointer.y - current.start.y) < 4)
      return;
    event.preventDefault();
    altHeld = event.altKey;
    drag.value = { ...current, pointer, moved: true };
    updatePreview();
  }
  function onPinKeyDown(event: KeyboardEvent, thread: SceneCommentThread | null) {
    const direction = keyboardDirections[event.key];
    if (!direction || ignorePinShortcut(event) || !commentGeometryReady()) return;
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
    if (event.type === "pointercancel" || !options.backgroundSettled()) cancelDrag();
    else {
      onDragMove(event);
      commitDrag();
    }
  }
  function commitDrag() {
    const current = drag.value;
    if (!current) return;
    // Re-read transforms and targets at commit, including an element deleted during this gesture.
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
        ...preview.position,
        context: preview.context,
        moving_draft: true,
        draft_id: draftId,
      },
      (reply) => {
        if (reply.ok !== true) rollback();
        else if (pendingDraft.value?.request === pending.request) {
          const returned = reply.draft as DraftAcknowledgement | undefined;
          if (returned?.id === pending.draftId && returned.position) {
            // Refresh can detach a deleted context between validation and acknowledgement.
            pendingDraft.value = {
              ...pending,
              position: returned.position,
              context: returned.context,
            };
          }
          confirmDraft();
        }
      },
      rollback,
    );
  }
  function persistThread(thread: SceneCommentThread, preview: CommentMagneticInitial) {
    const pending = { ...preview, request: ++request, revision: thread.revision };
    pendingMoves.value.set(thread.id, pending);
    const finish = (failed: boolean, returned?: SceneCommentThread) => {
      if (disposed || pendingMoves.value.get(thread.id)?.request !== pending.request) return;
      const latest = visibleThreads.value.find((item) => item.id === thread.id);
      const unchanged = acknowledgedUnchanged(returned, pending, latest);
      if (failed || !latest || latest.revision !== pending.revision || unchanged)
        pendingMoves.value.delete(thread.id);
      if (failed) moveError.value = true;
    };
    live.pushEvent(
      "comments_move",
      {
        thread_id: thread.id,
        ...preview.position,
        expected_revision: thread.revision,
        context: preview.context,
      },
      (reply) => finish(reply.ok !== true, reply.thread as SceneCommentThread | undefined),
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
      focusThread();
    },
  );
  function contextIdentity(context: CommentContextReference | null | undefined) {
    return context
      ? JSON.stringify([context.type, context.id, context.offset?.x, context.offset?.y])
      : null;
  }
  function samePlacement(
    thread: SceneCommentThread | undefined,
    placement: CommentMagneticInitial,
  ) {
    return (
      thread?.position?.x === placement.position.x &&
      thread.position.y === placement.position.y &&
      contextIdentity(thread.context) === contextIdentity(placement.context)
    );
  }
  function acknowledgedUnchanged(
    returned: SceneCommentThread | undefined,
    pending: PendingMove,
    latest: SceneCommentThread | undefined,
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
      (state.draftId ?? null) === pending.draftId &&
      state.draftPosition?.x === pending.position.x &&
      state.draftPosition?.y === pending.position.y &&
      contextIdentity(state.draftContext) === contextIdentity(pending.context);
    if (matches) pendingDraft.value = null;
  }
  // Drafts have no database row for the deletion trigger to preserve. Keep their
  // last rendered position when a collaborator removes a context that has moved.
  interface DraftLocation {
    id: string | null;
    saved: SceneCommentPosition;
    position: SceneCommentPosition;
  }
  let lastContextualDraft: DraftLocation | null = null;
  function contextExists(context: CommentContextReference) {
    const targets = options.targets();
    const lists: { [type: string]: readonly { id: string | number }[] } = {
      scene_pin: targets.pins,
      scene_zone: targets.zones,
      scene_connection: targets.connections,
      scene_annotation: targets.annotations,
    };
    return (
      (lists[context.type] ?? []).some((item) => String(item.id) === context.id) ||
      targets.origins?.some((item) => item.type === context.type && String(item.id) === context.id)
    );
  }
  function needsDraftPositionRecovery(current: DraftLocation, previous: DraftLocation | null) {
    if (!previous || previous.id !== current.id || drag.value || pendingDraft.value) return false;
    return (
      options.state().canComment &&
      current.saved.x === previous.saved.x &&
      current.saved.y === previous.saved.y &&
      (current.position.x !== previous.position.x || current.position.y !== previous.position.y)
    );
  }
  watch(
    () => [
      options.state().draftId,
      options.state().draftPosition,
      options.state().draftContext,
      options.state().open,
      options.state().thread?.id,
      options.targets(),
    ],
    () => {
      const state = options.state();
      const current = currentDraft();
      if (!current || !state.draftPosition) {
        lastContextualDraft = null;
        return;
      }
      const location = {
        id: state.draftId ?? null,
        saved: { ...state.draftPosition },
        position: current.position,
      };
      if (current.context) {
        if (contextExists(current.context)) lastContextualDraft = location;
        return;
      }
      const previous = lastContextualDraft;
      lastContextualDraft = null;
      if (previous && needsDraftPositionRecovery(location, previous))
        persistDraft(location.id, { position: previous.position, context: null });
    },
    { immediate: true },
  );
  watch(() => [options.state().draftPosition, options.state().draftContext], confirmDraft);
  function draftIsCurrent(id: string | null) {
    return Boolean(currentDraft()) && (options.state().draftId ?? null) === id;
  }
  watch(
    () => [options.state().draftId, options.state().open, options.state().thread?.id],
    () => {
      if (pendingDraft.value && !draftIsCurrent(pendingDraft.value.draftId))
        pendingDraft.value = null;
      if (drag.value && !drag.value.thread && !draftIsCurrent(drag.value.draftId)) cancelDrag();
    },
  );
  watch(
    () => options.state().canComment,
    (allowed) => {
      if (!allowed) cancelDrag();
    },
  );
  watch(
    () => [stage.x, stage.y, stage.scaleX, stage.scaleY, options.targets()],
    () => {
      if (drag.value?.moved) updatePreview();
    },
  );
  watch(() => options.focusThreadId(), focusThread);
  watch(
    () => options.backgroundSettled(),
    (settled) => {
      if (!settled) {
        closeContextMenu();
        cancelDrag();
        return;
      }
      focusThread();
      restoreStoredDraft();
    },
  );
  watch(
    placing,
    (active) => {
      container.dataset.commentPlacing = active ? "true" : "false";
    },
    { immediate: true },
  );

  onMounted(() => {
    container.addEventListener("pointerdown", onCanvasPointerDown, true);
    container.addEventListener("pointerup", finishCanvasPointer, true);
    container.addEventListener("pointercancel", finishCanvasPointer, true);
    container.addEventListener("mousedown", blockContextMouseCompatibility, true);
    container.addEventListener("mouseup", blockContextMouseCompatibility, true);
    container.addEventListener("click", finishCanvasClick, true);
    container.addEventListener("auxclick", finishCanvasClick, true);
    container.addEventListener("contextmenu", onContextMenu, true);
    document.addEventListener("pointerdown", closeContextMenuFromOutside, true);
    document.addEventListener("keydown", onKeyDown, true);
    document.addEventListener("keyup", onKeyUp, true);
    window.addEventListener("blur", cancelDrag);
    window.addEventListener("pointermove", onDragMove);
    window.addEventListener("pointerup", onDragEnd);
    window.addEventListener("pointercancel", onDragEnd);
    observer = new ResizeObserver(refreshBounds);
    observer.observe(container);
    refreshBounds();
  });

  onUnmounted(() => {
    disposed = true;
    cancelDrag();
    if (placedClickTimer) clearTimeout(placedClickTimer);
    if (contextClickTimer) clearTimeout(contextClickTimer);
    observer?.disconnect();
    container.removeEventListener("pointerdown", onCanvasPointerDown, true);
    container.removeEventListener("pointerup", finishCanvasPointer, true);
    container.removeEventListener("pointercancel", finishCanvasPointer, true);
    container.removeEventListener("mousedown", blockContextMouseCompatibility, true);
    container.removeEventListener("mouseup", blockContextMouseCompatibility, true);
    container.removeEventListener("click", finishCanvasClick, true);
    container.removeEventListener("auxclick", finishCanvasClick, true);
    container.removeEventListener("contextmenu", onContextMenu, true);
    document.removeEventListener("pointerdown", closeContextMenuFromOutside, true);
    document.removeEventListener("keydown", onKeyDown, true);
    document.removeEventListener("keyup", onKeyUp, true);
    window.removeEventListener("blur", cancelDrag);
    window.removeEventListener("pointermove", onDragMove);
    window.removeEventListener("pointerup", onDragEnd);
    window.removeEventListener("pointercancel", onDragEnd);
    delete container.dataset.commentPlacing;
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
    onPinKeyDown,
    onPinBlur,
    onLostCapture,
    toggleMagnetism,
    cycleContext,
    discardStoredDraft,
    contextMenuPoint,
    selectThread,
    startDrag,
    placeContextComment,
    closeContextMenu,
  };
}
