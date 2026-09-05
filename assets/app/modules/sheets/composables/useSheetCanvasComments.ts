import { computed, nextTick, onMounted, onUnmounted, ref, shallowRef, watch } from "vue";
import {
  clearCommentDraft,
  readCommentDraft,
  updateCommentDraft,
} from "@components/comments/commentDraftStorage";
import type { useLive } from "@shared/composables/useLive";
import {
  constrainSheetCommentPositionToSurface,
  sheetCommentCanvasPoint,
  sheetCommentPointFromClient,
  sheetCommentPositionForSurface,
  sheetCommentScreenPoint,
} from "../lib/comment-geometry";
import type {
  SheetCommentPosition,
  SheetCommentsPanelState,
  SheetCommentThread,
} from "../types/comments";

interface SheetCanvasCommentsOptions {
  container: () => HTMLElement | null;
  state: () => SheetCommentsPanelState;
  pins: () => SheetCommentThread[];
  focusThreadId: () => number | null;
  draftStorageKey: () => string | null;
  live: ReturnType<typeof useLive>;
}

interface PinDrag {
  thread: SheetCommentThread | null;
  pointerId: number;
  start: SheetCommentPosition;
  grabOffset: SheetCommentPosition;
  lastClient: SheetCommentPosition;
  moved: boolean;
}

const AUTO_SCROLL_EDGE = 64;
const AUTO_SCROLL_MAX_STEP = 20;

interface ScrollViewport {
  owner: HTMLElement;
  top: number;
  bottom: number;
}

interface VisibleSurfaceBounds {
  width: number;
  height: number;
  top: number;
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

function interactiveTarget(target: EventTarget | null): boolean {
  return (
    target instanceof Element &&
    Boolean(
      target.closest(
        'button, a, label, input, textarea, select, [contenteditable="true"], [contenteditable=""], [role="button"], [role="textbox"], [role="dialog"], .block-drag-handle, .surface-panel, [data-radix-popper-content-wrapper], [data-reka-popper-content-wrapper], [data-sheet-comment-ui="true"]',
      ),
    )
  );
}

function outsideCommentDialog(target: EventTarget | null): boolean {
  return (
    target instanceof Element &&
    Boolean(target.closest('[role="dialog"]')) &&
    !target.closest("#sheet-comment-popover")
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

function keyboardPosition(
  event: KeyboardEvent,
  current: SheetCommentPosition,
  surface: { width: number; height: number },
): SheetCommentPosition | null {
  const step = event.shiftKey ? 1 : 8;
  const xStep = surface.width > 0 ? (step / surface.width) * 100 : 0;
  let offset: SheetCommentPosition;
  switch (event.key) {
    case "ArrowLeft":
      offset = { x: -xStep, y: 0 };
      break;
    case "ArrowRight":
      offset = { x: xStep, y: 0 };
      break;
    case "ArrowUp":
      offset = { x: 0, y: -step };
      break;
    case "ArrowDown":
      offset = { x: 0, y: step };
      break;
    default:
      return null;
  }
  return constrainSheetCommentPositionToSurface(
    { x: current.x + offset.x, y: current.y + offset.y },
    surface,
  );
}

function samePosition(left: SheetCommentPosition, right: SheetCommentPosition): boolean {
  return left.x === right.x && left.y === right.y;
}

function verticalScrollOwner(element: HTMLElement): HTMLElement | null {
  let current = element.parentElement;

  while (current) {
    const overflowY = window.getComputedStyle(current).overflowY;
    if (overflowY === "auto" || overflowY === "scroll" || overflowY === "overlay") return current;
    current = current.parentElement;
  }

  return document.scrollingElement instanceof HTMLElement ? document.scrollingElement : null;
}

function scrollViewport(element: HTMLElement): ScrollViewport | null {
  const owner = verticalScrollOwner(element);
  if (!owner) return null;

  const rect = owner.getBoundingClientRect();
  const windowHeight = document.documentElement.clientHeight || window.innerHeight;
  const top = Math.max(0, rect.top);
  const bottom = Math.min(windowHeight, rect.bottom);
  return bottom > top ? { owner, top, bottom } : null;
}

function visibleCenterPosition(element: HTMLElement): SheetCommentPosition {
  const surface = element.getBoundingClientRect();
  const viewport = scrollViewport(element);
  const visibleTop = viewport ? Math.max(surface.top, viewport.top) : surface.top;
  const visibleBottom = viewport ? Math.min(surface.bottom, viewport.bottom) : surface.bottom;
  const clientY =
    visibleBottom >= visibleTop
      ? (visibleTop + visibleBottom) / 2
      : surface.top + surface.height / 2;

  return sheetCommentPointFromClient({ x: surface.left + surface.width / 2, y: clientY }, surface);
}

function canRestoreDraft(
  state: SheetCommentsPanelState,
  bounds: { width: number; height: number },
): boolean {
  return (
    state.canComment &&
    !state.open &&
    !state.thread &&
    !state.draftPosition &&
    bounds.width > 0 &&
    bounds.height > 0
  );
}

export function useSheetCanvasComments(options: SheetCanvasCommentsOptions) {
  const { live } = options;
  let container: HTMLElement | null = null;
  const bounds = shallowRef({ width: 0, height: 0 });
  const visibleBounds = shallowRef<VisibleSurfaceBounds>({ width: 0, height: 0, top: 0 });
  const hoverId = ref<number | null>(null);
  const drag = shallowRef<PinDrag | null>(null);
  const movedPositions = ref(
    new Map<number, { position: SheetCommentPosition; revision: number }>(),
  );
  const draftPosition = ref<SheetCommentPosition | null>(null);
  const contextPosition = ref<SheetCommentPosition | null>(null);
  const contextMenuPoint = ref<SheetCommentPosition | null>(null);
  const moveError = ref(false);
  let disposed = false;
  let suppressedClick = false;
  let placedPointer: number | null = null;
  let consumePlacedClick = false;
  let placedClickTimer: ReturnType<typeof setTimeout> | null = null;
  let focusedThreadId: number | null = null;
  let resizeObserver: ResizeObserver | null = null;
  let scrollOwnerElement: HTMLElement | null = null;
  let autoScrollFrame: number | null = null;
  let restoringDraftKey: string | null = null;

  const placing = computed(() => options.state().canComment && Boolean(options.state().placing));
  const selectedThread = computed(() => options.state().thread);
  const visibleThreads = computed(() => {
    const threads = options.pins().filter((thread) => thread.status === "open");
    const selected = selectedThread.value;
    if (options.state().open && selected && !threads.some((thread) => thread.id === selected.id))
      return [...threads, selected];
    return threads;
  });
  const pins = computed(() => {
    void bounds.value;
    const currentContainer = container;
    if (!currentContainer) return [];
    return visibleThreads.value.flatMap((thread) => {
      const position = movedPositions.value.get(thread.id)?.position ?? thread.position;
      const screen = sheetCommentScreenPoint(thread, currentContainer, position);
      return screen ? [{ thread, screen }] : [];
    });
  });
  const draftPoint = computed(() => {
    void bounds.value;
    const currentContainer = container;
    if (!currentContainer) return null;
    const state = options.state();
    const position = draftPosition.value ?? state.draftPosition;
    if (!state.open || state.presentation !== "canvas" || state.thread || !position) return null;
    return sheetCommentPositionForSurface(position, currentContainer);
  });
  const activePoint = computed(() =>
    selectedThread.value
      ? (pins.value.find((pin) => pin.thread.id === selectedThread.value?.id)?.screen ?? null)
      : draftPoint.value,
  );
  const hoveredPin = computed(() => pins.value.find((pin) => pin.thread.id === hoverId.value));
  const dragging = computed(() => drag.value != null);

  function surfaceTarget(event: MouseEvent): boolean {
    if (!(event.target instanceof Element) || !container?.contains(event.target)) return false;
    if (interactiveTarget(event.target)) return false;

    const rect = container.getBoundingClientRect();
    return (
      event.clientX >= rect.left &&
      event.clientX <= rect.right &&
      event.clientY >= rect.top &&
      event.clientY <= rect.bottom
    );
  }

  function pointFromClient(clientX: number, clientY: number): SheetCommentPosition {
    if (!container) return { x: 0, y: 0 };
    return sheetCommentPointFromClient(
      { x: clientX, y: clientY },
      container.getBoundingClientRect(),
    );
  }

  function storeDraftPosition(position: SheetCommentPosition): void {
    updateCommentDraft(options.draftStorageKey(), { position });
  }

  function restoreStoredDraft(): void {
    const state = options.state();
    const storageKey = options.draftStorageKey();
    if (!storageKey || restoringDraftKey === storageKey) return;
    if (!canRestoreDraft(state, bounds.value)) return;

    const stored = readCommentDraft(storageKey);
    if (!stored?.position) return;
    const position = constrainSheetCommentPositionToSurface(stored.position, bounds.value);
    restoringDraftKey = storageKey;
    const finishRestore = () => {
      if (restoringDraftKey === storageKey) restoringDraftKey = null;
    };
    live.pushEvent("comments_place", { ...position }, finishRestore, finishRestore);
  }

  function focusThread(): void {
    const id = options.focusThreadId();
    if (id == null) {
      focusedThreadId = null;
      return;
    }
    if (id === focusedThreadId || bounds.value.width === 0 || bounds.value.height === 0) return;

    const thread = visibleThreads.value.find((item) => item.id === id);
    if (!thread || !sheetCommentCanvasPoint(thread)) return;

    focusedThreadId = id;
    window.requestAnimationFrame(() => {
      const pin = document.getElementById(`sheet-comment-pin-${id}`);
      pin?.scrollIntoView({ behavior: "smooth", block: "center", inline: "center" });
    });
  }

  function refreshBounds(): void {
    if (disposed || !container) return;
    const rect = container.getBoundingClientRect();
    bounds.value = { width: rect.width, height: rect.height };
    const viewport = scrollViewport(container);
    const top = viewport ? Math.max(0, viewport.top - rect.top) : 0;
    const bottom = viewport ? Math.min(rect.height, viewport.bottom - rect.top) : rect.height;
    visibleBounds.value = {
      width: rect.width,
      height: Math.max(0, bottom - top),
      top,
    };
    focusThread();
  }

  function onSurfacePointerDown(event: PointerEvent): void {
    if (
      !placing.value ||
      event.button !== 0 ||
      event.altKey ||
      event.ctrlKey ||
      event.metaKey ||
      !surfaceTarget(event)
    )
      return;

    event.preventDefault();
    event.stopImmediatePropagation();
    placedPointer = event.pointerId;
    consumePlacedClick = true;
    const position = pointFromClient(event.clientX, event.clientY);
    storeDraftPosition(position);
    live.pushEvent("comments_place", { ...position });
  }

  function finishSurfacePointer(event: PointerEvent): void {
    if (placedPointer == null || event.pointerId !== placedPointer) return;
    event.preventDefault();
    event.stopImmediatePropagation();
    placedPointer = null;
    if (placedClickTimer) clearTimeout(placedClickTimer);
    placedClickTimer = setTimeout(() => {
      consumePlacedClick = false;
      placedClickTimer = null;
    }, 0);
  }

  function finishSurfaceClick(event: MouseEvent): void {
    if (!consumePlacedClick || event.button !== 0) return;
    event.preventDefault();
    event.stopImmediatePropagation();
  }

  function onContextMenu(event: MouseEvent): void {
    if (!options.state().canComment || !surfaceTarget(event) || !container) return;

    event.preventDefault();
    event.stopImmediatePropagation();
    const rect = container.getBoundingClientRect();
    contextPosition.value = pointFromClient(event.clientX, event.clientY);
    contextMenuPoint.value = {
      x: event.clientX - rect.left,
      y: event.clientY - rect.top,
    };
  }

  function placeContextComment(): void {
    if (!options.state().canComment || !contextPosition.value) {
      closeContextMenu();
      return;
    }
    storeDraftPosition(contextPosition.value);
    live.pushEvent("comments_place", contextPosition.value);
    closeContextMenu();
  }

  function closeContextMenu(): void {
    contextPosition.value = null;
    contextMenuPoint.value = null;
  }

  function closeContextMenuFromOutside(event: PointerEvent): void {
    if (!contextMenuPoint.value) return;
    if (event.target instanceof Element && event.target.closest("#sheet-comment-context-menu"))
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
    if (event.key === "Enter" && placing.value && container && event.target === container) {
      event.preventDefault();
      event.stopImmediatePropagation();
      const position = visibleCenterPosition(container);
      storeDraftPosition(position);
      live.pushEvent("comments_place", { ...position });
      return;
    }
    if (event.key.toLowerCase() === "c" && options.state().canComment) {
      event.preventDefault();
      event.stopImmediatePropagation();
      live.pushEvent("comments_mode", { active: !placing.value });
    }
  }

  function selectThread(thread: SheetCommentThread, event: MouseEvent): void {
    if (suppressedClick && event.detail !== 0) {
      suppressedClick = false;
      return;
    }
    suppressedClick = false;
    hoverId.value = null;
    live.pushEvent("comments_select_thread", { thread_id: thread.id, presentation: "canvas" });
  }

  function initialDragPosition(thread: SheetCommentThread | null): SheetCommentPosition | null {
    if (thread) return thread.position ?? null;
    return draftPosition.value ?? options.state().draftPosition ?? null;
  }

  function startDrag(event: PointerEvent, thread: SheetCommentThread | null): void {
    if (!options.state().canComment || event.button !== 0) return;
    if (thread && movedPositions.value.has(thread.id)) return;
    const position = initialDragPosition(thread);
    if (!position) return;

    if (!container) return;
    const surfaceRect = container.getBoundingClientRect();
    const screen = sheetCommentPositionForSurface(position, container);

    suppressedClick = false;
    moveError.value = false;
    drag.value = {
      thread,
      pointerId: event.pointerId,
      start: { x: event.clientX, y: event.clientY },
      grabOffset: {
        x: event.clientX - surfaceRect.left - screen.x,
        y: event.clientY - surfaceRect.top - screen.y,
      },
      lastClient: { x: event.clientX, y: event.clientY },
      moved: false,
    };
    (event.currentTarget as HTMLElement).setPointerCapture?.(event.pointerId);
  }

  function positionForKeyboardMove(
    thread: SheetCommentThread | null,
    state: SheetCommentsPanelState,
  ): SheetCommentPosition | null {
    if (!thread) return draftPosition.value ?? state.draftPosition ?? null;
    if (movedPositions.value.has(thread.id)) return null;
    return thread.position ?? null;
  }

  function persistKeyboardMove(
    thread: SheetCommentThread | null,
    position: SheetCommentPosition,
  ): void {
    if (thread) {
      movedPositions.value.set(thread.id, { position, revision: thread.revision });
      persistThreadPosition(thread);
      return;
    }
    draftPosition.value = position;
    persistDraftPosition();
  }

  function movePinWithKeyboard(event: KeyboardEvent, thread: SheetCommentThread | null): void {
    if (!options.state().canComment) return;
    const current = positionForKeyboardMove(thread, options.state());
    if (!current) return;

    const position = keyboardPosition(event, current, bounds.value);
    if (!position) return;
    event.preventDefault();
    event.stopPropagation();
    if (samePosition(position, current)) return;

    moveError.value = false;
    persistKeyboardMove(thread, position);
  }

  function updateDraggedPosition(client: SheetCommentPosition): void {
    const current = drag.value;
    if (!current || !container) return;

    const delta = { x: client.x - current.start.x, y: client.y - current.start.y };
    if (!current.moved && Math.hypot(delta.x, delta.y) < 4) return;

    const rect = container.getBoundingClientRect();
    const position = sheetCommentPointFromClient(
      {
        x: client.x - current.grabOffset.x,
        y: client.y - current.grabOffset.y,
      },
      rect,
    );
    drag.value = { ...current, lastClient: client, moved: true };
    hoverId.value = null;
    if (current.thread)
      movedPositions.value.set(current.thread.id, {
        position,
        revision: current.thread.revision,
      });
    else draftPosition.value = position;
  }

  function autoScrollStep(clientY: number, viewport: ScrollViewport): number {
    const height = viewport.bottom - viewport.top;
    if (height <= 0) return 0;
    const edge = Math.min(AUTO_SCROLL_EDGE, height / 2);
    if (clientY < viewport.top + edge)
      return -AUTO_SCROLL_MAX_STEP * (1 - Math.max(0, clientY - viewport.top) / edge);
    if (clientY > viewport.bottom - edge)
      return AUTO_SCROLL_MAX_STEP * (1 - Math.max(0, viewport.bottom - clientY) / edge);
    return 0;
  }

  function canAutoScroll(viewport: ScrollViewport, step: number): boolean {
    if (!container || step === 0) return false;
    const surface = container.getBoundingClientRect();
    const { owner } = viewport;

    if (step < 0) return owner.scrollTop > 0 && surface.top < viewport.top;

    return (
      owner.scrollTop + owner.clientHeight < owner.scrollHeight && surface.bottom > viewport.bottom
    );
  }

  function stopAutoScroll(): void {
    if (autoScrollFrame == null) return;
    window.cancelAnimationFrame(autoScrollFrame);
    autoScrollFrame = null;
  }

  function scheduleAutoScroll(): void {
    const current = drag.value;
    if (!current || autoScrollFrame != null || !container) return;
    const viewport = scrollViewport(container);
    if (!viewport) return;
    const step = autoScrollStep(current.lastClient.y, viewport);
    if (!canAutoScroll(viewport, step)) return;

    autoScrollFrame = window.requestAnimationFrame(() => {
      autoScrollFrame = null;
      const active = drag.value;
      if (!active || !container) return;
      const currentViewport = scrollViewport(container);
      if (!currentViewport) return;
      const currentStep = autoScrollStep(active.lastClient.y, currentViewport);
      if (!canAutoScroll(currentViewport, currentStep)) return;
      currentViewport.owner.scrollBy({ top: currentStep, behavior: "auto" });
      refreshBounds();
      updateDraggedPosition(active.lastClient);
      scheduleAutoScroll();
    });
  }

  function onDragMove(event: PointerEvent): void {
    const current = drag.value;
    if (!current || current.pointerId !== event.pointerId) return;
    const client = { x: event.clientX, y: event.clientY };
    drag.value = { ...current, lastClient: client };
    updateDraggedPosition(client);
    scheduleAutoScroll();
  }

  function onDragEnd(event: PointerEvent): void {
    const current = drag.value;
    if (!current || current.pointerId !== event.pointerId) return;
    stopAutoScroll();
    drag.value = null;
    if (!current.moved) return;
    suppressedClick = event.type !== "pointercancel";
    if (event.type === "pointercancel" || !options.state().canComment) {
      if (current.thread) movedPositions.value.delete(current.thread.id);
      else draftPosition.value = null;
      return;
    }
    if (current.thread) {
      hoverId.value = current.thread.id;
      persistThreadPosition(current.thread);
    } else persistDraftPosition();
  }

  function cancelActiveDrag(): void {
    const current = drag.value;
    if (!current) return;
    stopAutoScroll();
    drag.value = null;
    suppressedClick = current.moved;
    if (current.thread) movedPositions.value.delete(current.thread.id);
    else draftPosition.value = null;
  }

  function persistDraftPosition(): void {
    const position = draftPosition.value;
    if (!position) return;
    storeDraftPosition(position);
    const rollback = () => {
      if (draftPosition.value !== position) return;
      draftPosition.value = null;
      moveError.value = true;
    };
    live.pushEvent(
      "comments_place",
      { ...position, moving_draft: true },
      (reply) => {
        if (reply.ok !== true) rollback();
      },
      rollback,
    );
  }

  function persistThreadPosition({ id, revision }: SheetCommentThread): void {
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
    () => ({
      storageKey: options.draftStorageKey(),
      open: options.state().open,
      draftPosition: options.state().draftPosition,
      threadId: options.state().thread?.id ?? null,
    }),
    (current, previous) => {
      if (current.draftPosition)
        updateCommentDraft(current.storageKey, { position: current.draftPosition });
      if (previous && current.storageKey !== previous.storageKey) {
        draftPosition.value = null;
        return;
      }
      if (
        current.threadId != null ||
        (previous?.draftPosition != null && current.draftPosition == null)
      )
        clearCommentDraft(current.storageKey);
      draftPosition.value = null;
    },
  );
  watch(
    () => options.draftStorageKey(),
    async () => {
      restoringDraftKey = null;
      draftPosition.value = null;
      await nextTick();
      refreshBounds();
      restoreStoredDraft();
    },
  );
  watch(
    () => options.focusThreadId(),
    () => {
      focusedThreadId = null;
      focusThread();
    },
  );
  watch(
    placing,
    (active) => {
      if (container) container.dataset.commentPlacing = active ? "true" : "false";
    },
    { immediate: true },
  );

  onMounted(() => {
    container = options.container();
    if (!container) return;
    container.dataset.commentPlacing = placing.value ? "true" : "false";
    container.addEventListener("pointerdown", onSurfacePointerDown, true);
    container.addEventListener("pointerup", finishSurfacePointer, true);
    container.addEventListener("pointercancel", finishSurfacePointer, true);
    container.addEventListener("click", finishSurfaceClick, true);
    container.addEventListener("contextmenu", onContextMenu, true);
    document.addEventListener("pointerdown", closeContextMenuFromOutside, true);
    document.addEventListener("keydown", onKeyDown, true);
    window.addEventListener("pointermove", onDragMove);
    window.addEventListener("pointerup", onDragEnd);
    window.addEventListener("pointercancel", onDragEnd);

    resizeObserver = new ResizeObserver(refreshBounds);
    resizeObserver.observe(container);
    scrollOwnerElement = verticalScrollOwner(container);
    if (scrollOwnerElement && scrollOwnerElement !== container) {
      scrollOwnerElement.addEventListener("scroll", refreshBounds, { passive: true });
      resizeObserver.observe(scrollOwnerElement);
    }
    window.addEventListener("resize", refreshBounds);
    refreshBounds();
    restoreStoredDraft();
  });

  function dispose(): void {
    disposed = true;
    if (placedClickTimer) clearTimeout(placedClickTimer);
    stopAutoScroll();
    cancelActiveDrag();
    resizeObserver?.disconnect();
    scrollOwnerElement?.removeEventListener("scroll", refreshBounds);
    window.removeEventListener("resize", refreshBounds);
    if (container) {
      container.removeEventListener("pointerdown", onSurfacePointerDown, true);
      container.removeEventListener("pointerup", finishSurfacePointer, true);
      container.removeEventListener("pointercancel", finishSurfacePointer, true);
      container.removeEventListener("click", finishSurfaceClick, true);
      container.removeEventListener("contextmenu", onContextMenu, true);
      delete container.dataset.commentPlacing;
    }
    document.removeEventListener("pointerdown", closeContextMenuFromOutside, true);
    document.removeEventListener("keydown", onKeyDown, true);
    window.removeEventListener("pointermove", onDragMove);
    window.removeEventListener("pointerup", onDragEnd);
    window.removeEventListener("pointercancel", onDragEnd);
  }

  onUnmounted(dispose);

  return {
    pins,
    placing,
    bounds,
    visibleBounds,
    hoverId,
    hoveredPin,
    activePoint,
    draftPoint,
    moveError,
    contextMenuPoint,
    dragging,
    selectThread,
    startDrag,
    movePinWithKeyboard,
    placeContextComment,
    closeContextMenu,
  };
}
