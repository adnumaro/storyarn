import { computed, onMounted, onUnmounted, ref, shallowRef, watch } from "vue";
import type { useLive } from "@shared/composables/useLive";
import type { SceneCommentsPanelState, SceneCommentThread } from "../../types/comments";
import {
  sceneCommentCanvasPoint,
  sceneCommentDragPosition,
  sceneCommentPointFromClient,
  sceneCommentScreenPoint,
  type SceneCommentProjection,
  type SceneCommentStageTransform,
} from "../lib/comment-geometry";
import type { SceneCommentPosition } from "../../types/comments";

interface SceneCanvasCommentsOptions {
  container: HTMLElement;
  stage: SceneCommentStageTransform;
  projection: SceneCommentProjection;
  backgroundSettled: () => boolean;
  state: () => SceneCommentsPanelState;
  pins: () => SceneCommentThread[];
  focusThreadId: () => number | null;
  live: ReturnType<typeof useLive>;
}

interface PinDrag {
  thread: SceneCommentThread | null;
  pointerId: number;
  start: SceneCommentPosition;
  position: SceneCommentPosition;
  stage: SceneCommentStageTransform;
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

export function useSceneCanvasComments(options: SceneCanvasCommentsOptions) {
  const { container, stage, projection, live } = options;
  const bounds = shallowRef({ width: 0, height: 0 });
  const hoverId = ref<number | null>(null);
  const drag = shallowRef<PinDrag | null>(null);
  const movedPositions = ref(
    new Map<number, { position: SceneCommentPosition; revision: number }>(),
  );
  const draftPosition = ref<SceneCommentPosition | null>(null);
  const contextPosition = ref<SceneCommentPosition | null>(null);
  const contextMenuPoint = ref<SceneCommentPosition | null>(null);
  const moveError = ref(false);
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
      const position = movedPositions.value.get(thread.id)?.position ?? thread.position;
      const point = sceneCommentCanvasPoint(thread, position);
      return point
        ? [{ thread, point, screen: sceneCommentScreenPoint(point, stage, projection) }]
        : [];
    }),
  );
  const draftPoint = computed(() => {
    const state = options.state();
    const position = draftPosition.value ?? state.draftPosition;
    if (!state.open || state.presentation !== "canvas" || state.thread || !position) return null;
    return sceneCommentScreenPoint(position, stage, projection);
  });
  const activePoint = computed(() =>
    selectedThread.value
      ? (pins.value.find((pin) => pin.thread.id === selectedThread.value?.id)?.screen ?? null)
      : draftPoint.value,
  );
  const hoveredPin = computed(() => pins.value.find((pin) => pin.thread.id === hoverId.value));

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
    const point = thread && sceneCommentCanvasPoint(thread);
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
  }

  function canvasTarget(event: MouseEvent): event is MouseEvent & { target: Element } {
    if (!(event.target instanceof Element) || !container.contains(event.target)) return false;
    return !interactiveTarget(event.target);
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
    if (!placing.value || event.button !== 0 || event.altKey || event.ctrlKey || event.metaKey)
      return;

    event.preventDefault();
    event.stopImmediatePropagation();
    placedPointer = event.pointerId;
    consumePlacedClick = true;
    if (!options.backgroundSettled()) return;
    const position = pointFromClient(event.clientX, event.clientY);
    live.pushEvent("comments_place", { x: position.x, y: position.y });
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
    if (!options.state().canComment || interactiveTarget(event.target)) return;
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
    live.pushEvent("comments_place", contextPosition.value);
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
    live.pushEvent(
      placing.value ? "comments_mode" : "comments_close",
      placing.value ? { active: false } : {},
    );
  }

  function onKeyDown(event: KeyboardEvent): void {
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

  function selectThread(thread: SceneCommentThread, event: MouseEvent): void {
    if (suppressedClick && event.detail !== 0) {
      suppressedClick = false;
      return;
    }
    suppressedClick = false;
    hoverId.value = null;
    live.pushEvent("comments_select_thread", { thread_id: thread.id, presentation: "canvas" });
  }

  function startDrag(event: PointerEvent, thread: SceneCommentThread | null): void {
    if (!commentGeometryReady() || event.button !== 0) return;
    if (thread && movedPositions.value.has(thread.id)) return;
    const position = thread
      ? (thread.position ?? null)
      : (draftPosition.value ?? options.state().draftPosition);
    if (!position) return;

    suppressedClick = false;
    moveError.value = false;
    drag.value = {
      thread,
      pointerId: event.pointerId,
      start: { x: event.clientX, y: event.clientY },
      position: { ...position },
      stage: { x: stage.x, y: stage.y, scaleX: stage.scaleX, scaleY: stage.scaleY },
      moved: false,
    };
    (event.currentTarget as HTMLElement).setPointerCapture?.(event.pointerId);
  }

  function onDragMove(event: PointerEvent): void {
    const current = drag.value;
    if (!current || current.pointerId !== event.pointerId) return;
    if (!options.backgroundSettled()) {
      cancelActiveDrag();
      return;
    }
    const delta = { x: event.clientX - current.start.x, y: event.clientY - current.start.y };
    if (!current.moved && Math.hypot(delta.x, delta.y) < 4) return;

    const position = sceneCommentDragPosition(current.position, delta, current.stage, projection);
    drag.value = { ...current, moved: true };
    hoverId.value = null;
    if (current.thread)
      movedPositions.value.set(current.thread.id, { position, revision: current.thread.revision });
    else draftPosition.value = position;
  }

  function onDragEnd(event: PointerEvent): void {
    const current = drag.value;
    if (!current || current.pointerId !== event.pointerId) return;
    if (!options.backgroundSettled()) {
      cancelActiveDrag();
      return;
    }
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

  function cancelActiveDrag(): void {
    const current = drag.value;
    if (!current) return;
    drag.value = null;
    suppressedClick = current.moved;
    if (current.thread) movedPositions.value.delete(current.thread.id);
    else draftPosition.value = null;
  }

  function persistDraftPosition(): void {
    const position = draftPosition.value;
    if (!position) return;
    const rollbackDraft = () => {
      if (draftPosition.value !== position) return;
      draftPosition.value = null;
      moveError.value = true;
    };
    live.pushEvent(
      "comments_place",
      { ...position, moving_draft: true },
      (reply) => {
        if (reply.ok !== true) rollbackDraft();
      },
      rollbackDraft,
    );
  }

  function persistThreadPosition({ id, revision }: SceneCommentThread): void {
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
        if (reply.ok !== true) {
          rollback();
          return;
        }

        const returnedThread = reply.thread;
        if (!returnedThread || typeof returnedThread !== "object") return;
        const returned = returnedThread as {
          position?: { x?: unknown; y?: unknown } | null;
          revision?: unknown;
        };
        if (
          returned.revision === revision &&
          returned.position?.x === position.x &&
          returned.position.y === position.y &&
          movedPositions.value.get(id)?.revision === revision
        )
          movedPositions.value.delete(id);
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
      focusThread();
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
    () => options.backgroundSettled(),
    (settled) => {
      if (!settled) {
        closeContextMenu();
        cancelActiveDrag();
        return;
      }
      focusThread();
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
    window.addEventListener("pointermove", onDragMove);
    window.addEventListener("pointerup", onDragEnd);
    window.addEventListener("pointercancel", onDragEnd);
    observer = new ResizeObserver(refreshBounds);
    observer.observe(container);
    refreshBounds();
  });

  onUnmounted(() => {
    disposed = true;
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
    contextMenuPoint,
    selectThread,
    startDrag,
    placeContextComment,
    closeContextMenu,
  };
}
