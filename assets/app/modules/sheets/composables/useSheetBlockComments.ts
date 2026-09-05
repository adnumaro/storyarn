import { computed, onMounted, onUnmounted, ref, shallowRef, watch } from "vue";
import type { useLive } from "@shared/composables/useLive";
import { highlightSheetLocation } from "./useSheetHighlight";
import {
  findSheetCommentBlock,
  sheetCommentPointFromClient,
  sheetCommentPositionForBlock,
  sheetCommentScreenPoint,
} from "../lib/comment-geometry";
import type {
  SheetCommentPosition,
  SheetCommentsPanelState,
  SheetCommentThread,
} from "../types/comments";

interface SheetBlockCommentsOptions {
  container: () => HTMLElement | null;
  state: () => SheetCommentsPanelState;
  pins: () => SheetCommentThread[];
  focusThreadId: () => number | null;
  live: ReturnType<typeof useLive>;
}

interface PinDrag {
  thread: SheetCommentThread | null;
  blockId: number;
  pointerId: number;
  start: SheetCommentPosition;
  moved: boolean;
}

interface BlockAnchor {
  block: HTMLElement;
  blockId: number;
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
        'button, a, input, textarea, select, [contenteditable="true"], [contenteditable=""], [role="button"], [role="textbox"], [data-sheet-comment-ui="true"]',
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
): SheetCommentPosition | null {
  const step = event.shiftKey ? 1 : 5;
  let offset: SheetCommentPosition;
  switch (event.key) {
    case "ArrowLeft":
      offset = { x: -step, y: 0 };
      break;
    case "ArrowRight":
      offset = { x: step, y: 0 };
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
  return {
    x: Math.max(0, Math.min(100, current.x + offset.x)),
    y: Math.max(0, Math.min(100, current.y + offset.y)),
  };
}

function samePosition(left: SheetCommentPosition, right: SheetCommentPosition): boolean {
  return left.x === right.x && left.y === right.y;
}

function targetAndContainer(
  target: EventTarget | null,
  container: HTMLElement | null,
): { target: Element; container: HTMLElement } | null {
  if (!(target instanceof Element) || !container?.contains(target)) return null;
  return { target, container };
}

export function useSheetBlockComments(options: SheetBlockCommentsOptions) {
  const { live } = options;
  let container: HTMLElement | null = null;
  const bounds = shallowRef({ width: 0, height: 0 });
  const layoutRevision = ref(0);
  const hoverId = ref<number | null>(null);
  const drag = shallowRef<PinDrag | null>(null);
  const movedPositions = ref(
    new Map<number, { position: SheetCommentPosition; revision: number }>(),
  );
  const draftPosition = ref<SheetCommentPosition | null>(null);
  const contextAnchor = shallowRef<{
    blockId: number;
    position: SheetCommentPosition;
  } | null>(null);
  const contextMenuPoint = ref<SheetCommentPosition | null>(null);
  const moveError = ref(false);
  let disposed = false;
  let suppressedClick = false;
  let placedPointer: number | null = null;
  let consumePlacedClick = false;
  let placedClickTimer: ReturnType<typeof setTimeout> | null = null;
  let focusedThreadId: number | null = null;
  let clearFocusHighlight: (() => void) | null = null;
  let resizeObserver: ResizeObserver | null = null;
  let mutationObserver: MutationObserver | null = null;
  let refreshFrame: number | null = null;

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
    void layoutRevision.value;
    const currentContainer = container;
    if (!currentContainer) return [];
    return visibleThreads.value.flatMap((thread) => {
      const position = movedPositions.value.get(thread.id)?.position ?? thread.position;
      const screen = sheetCommentScreenPoint(thread, currentContainer, position);
      return screen ? [{ thread, screen }] : [];
    });
  });
  const draftPoint = computed(() => {
    void layoutRevision.value;
    if (!container) return null;
    const state = options.state();
    const position = draftPosition.value ?? state.draftPosition;
    if (
      !state.open ||
      state.presentation !== "canvas" ||
      state.thread ||
      state.selectedBlockId == null ||
      !position
    )
      return null;
    return sheetCommentPositionForBlock(state.selectedBlockId, position, container);
  });
  const activePoint = computed(() =>
    selectedThread.value
      ? (pins.value.find((pin) => pin.thread.id === selectedThread.value?.id)?.screen ?? null)
      : draftPoint.value,
  );
  const hoveredPin = computed(() => pins.value.find((pin) => pin.thread.id === hoverId.value));
  const dragging = computed(() => drag.value != null);

  function anchorFromTarget(
    target: EventTarget | null,
    allowInteractive: boolean,
  ): BlockAnchor | null {
    const context = targetAndContainer(target, container);
    if (!context) return null;
    if (context.target.closest('[data-sheet-comment-ui="true"]')) return null;
    if (!allowInteractive && interactiveTarget(context.target)) return null;

    const block = context.target.closest<HTMLElement>("[data-sheet-block-id]");
    if (!block || !context.container.contains(block)) return null;
    const blockId = Number(block.dataset.sheetBlockId);
    return Number.isInteger(blockId) && blockId > 0 ? { block, blockId } : null;
  }

  function positionFromClient(
    block: HTMLElement,
    clientX: number,
    clientY: number,
  ): SheetCommentPosition {
    return sheetCommentPointFromClient({ x: clientX, y: clientY }, block.getBoundingClientRect());
  }

  function scheduleRefresh(): void {
    if (disposed || refreshFrame != null) return;
    refreshFrame = window.requestAnimationFrame(() => {
      refreshFrame = null;
      refreshLayout();
    });
  }

  function observeBlocks(): void {
    if (!resizeObserver || !container) return;
    for (const block of container.querySelectorAll<HTMLElement>("[data-sheet-block-id]"))
      resizeObserver.observe(block);
  }

  function focusThread(): void {
    const id = options.focusThreadId();
    if (id == null) {
      focusedThreadId = null;
      clearFocusHighlight?.();
      clearFocusHighlight = null;
      return;
    }
    if (id === focusedThreadId) return;

    const thread = visibleThreads.value.find((item) => item.id === id);
    if (!thread || thread.source.status !== "available") return;
    if (!container) return;
    const block = findSheetCommentBlock(container, thread.source.id);
    if (!block) return;

    focusedThreadId = id;
    clearFocusHighlight?.();
    clearFocusHighlight = highlightSheetLocation({ blockId: thread.source.id });
    scheduleRefresh();
    window.requestAnimationFrame(() => {
      document.getElementById(`sheet-comment-pin-${id}`)?.focus({ preventScroll: true });
    });
  }

  function refreshLayout(): void {
    if (disposed || !container) return;
    const rect = container.getBoundingClientRect();
    bounds.value = { width: rect.width, height: rect.height };
    layoutRevision.value += 1;
    focusThread();
  }

  function onSurfacePointerDown(event: PointerEvent): void {
    if (!placing.value || event.button !== 0 || event.altKey || event.ctrlKey || event.metaKey)
      return;
    const anchor = anchorFromTarget(event.target, false);
    if (!anchor) return;

    event.preventDefault();
    event.stopImmediatePropagation();
    placedPointer = event.pointerId;
    consumePlacedClick = true;
    const position = positionFromClient(anchor.block, event.clientX, event.clientY);
    live.pushEvent("comments_place", { block_id: anchor.blockId, ...position });
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
    if (!options.state().canComment) return;
    const anchor = anchorFromTarget(event.target, false);
    if (!anchor) return;

    event.preventDefault();
    event.stopImmediatePropagation();
    if (!container) return;
    const rect = container.getBoundingClientRect();
    contextAnchor.value = {
      blockId: anchor.blockId,
      position: positionFromClient(anchor.block, event.clientX, event.clientY),
    };
    contextMenuPoint.value = {
      x: event.clientX - rect.left,
      y: event.clientY - rect.top,
    };
  }

  function placeContextComment(): void {
    const anchor = contextAnchor.value;
    if (!options.state().canComment || !anchor) {
      closeContextMenu();
      return;
    }
    live.pushEvent("comments_place", { block_id: anchor.blockId, ...anchor.position });
    closeContextMenu();
  }

  function closeContextMenu(): void {
    contextAnchor.value = null;
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
    if (event.key === "Enter" && placing.value) {
      const anchor = anchorFromTarget(event.target, false);
      if (!anchor) return;
      event.preventDefault();
      event.stopImmediatePropagation();
      live.pushEvent("comments_place", { block_id: anchor.blockId, x: 50, y: 50 });
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

  function startDrag(event: PointerEvent, thread: SheetCommentThread | null): void {
    if (!options.state().canComment || event.button !== 0) return;
    if (thread && movedPositions.value.has(thread.id)) return;

    const blockId = dragBlockId(thread);
    if (blockId == null) return;

    suppressedClick = false;
    moveError.value = false;
    drag.value = {
      thread,
      blockId,
      pointerId: event.pointerId,
      start: { x: event.clientX, y: event.clientY },
      moved: false,
    };
    (event.currentTarget as HTMLElement).setPointerCapture?.(event.pointerId);
  }

  function dragBlockId(thread: SheetCommentThread | null): number | null {
    const blockId = thread?.source.id ?? options.state().selectedBlockId;
    if (!container || blockId == null) return null;
    return findSheetCommentBlock(container, blockId) ? blockId : null;
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
    state: SheetCommentsPanelState,
    position: SheetCommentPosition,
  ): void {
    if (thread) {
      movedPositions.value.set(thread.id, { position, revision: thread.revision });
      persistThreadPosition(thread);
      return;
    }
    if (state.selectedBlockId == null) return;
    draftPosition.value = position;
    persistDraftPosition(state.selectedBlockId);
  }

  function movePinWithKeyboard(event: KeyboardEvent, thread: SheetCommentThread | null): void {
    if (!options.state().canComment) return;
    const state = options.state();
    const current = positionForKeyboardMove(thread, state);
    if (!current) return;

    const position = keyboardPosition(event, current);
    if (!position) return;
    event.preventDefault();
    event.stopPropagation();
    if (samePosition(position, current)) return;

    moveError.value = false;
    persistKeyboardMove(thread, state, position);
  }

  function onDragMove(event: PointerEvent): void {
    const current = drag.value;
    if (!current || current.pointerId !== event.pointerId) return;
    if (!container) {
      cancelActiveDrag();
      return;
    }
    const block = findSheetCommentBlock(container, current.blockId);
    if (!block) {
      cancelActiveDrag();
      return;
    }
    if (
      !current.moved &&
      Math.hypot(event.clientX - current.start.x, event.clientY - current.start.y) < 4
    )
      return;

    const position = positionFromClient(block, event.clientX, event.clientY);
    drag.value = { ...current, moved: true };
    hoverId.value = null;
    if (current.thread)
      movedPositions.value.set(current.thread.id, {
        position,
        revision: current.thread.revision,
      });
    else draftPosition.value = position;
  }

  function onDragEnd(event: PointerEvent): void {
    const current = drag.value;
    if (!current || current.pointerId !== event.pointerId) return;
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
    } else persistDraftPosition(current.blockId);
  }

  function cancelActiveDrag(): void {
    const current = drag.value;
    if (!current) return;
    drag.value = null;
    suppressedClick = current.moved;
    if (current.thread) movedPositions.value.delete(current.thread.id);
    else draftPosition.value = null;
  }

  function persistDraftPosition(blockId: number): void {
    const position = draftPosition.value;
    if (!position) return;
    const rollback = () => {
      if (draftPosition.value !== position) return;
      draftPosition.value = null;
      moveError.value = true;
    };
    live.pushEvent(
      "comments_place",
      { block_id: blockId, ...position, moving_draft: true },
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
      scheduleRefresh();
    },
  );
  watch(
    () => [options.state().draftPosition, options.state().thread?.id],
    () => {
      draftPosition.value = null;
      scheduleRefresh();
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

    resizeObserver = new ResizeObserver(scheduleRefresh);
    resizeObserver.observe(container);
    observeBlocks();
    mutationObserver = new MutationObserver(() => {
      observeBlocks();
      scheduleRefresh();
    });
    mutationObserver.observe(container, { childList: true, subtree: true });
    refreshLayout();
  });

  function removeContainerListeners(currentContainer: HTMLElement): void {
    currentContainer.removeEventListener("pointerdown", onSurfacePointerDown, true);
    currentContainer.removeEventListener("pointerup", finishSurfacePointer, true);
    currentContainer.removeEventListener("pointercancel", finishSurfacePointer, true);
    currentContainer.removeEventListener("click", finishSurfaceClick, true);
    currentContainer.removeEventListener("contextmenu", onContextMenu, true);
    delete currentContainer.dataset.commentPlacing;
  }

  function removeGlobalListeners(): void {
    document.removeEventListener("pointerdown", closeContextMenuFromOutside, true);
    document.removeEventListener("keydown", onKeyDown, true);
    window.removeEventListener("pointermove", onDragMove);
    window.removeEventListener("pointerup", onDragEnd);
    window.removeEventListener("pointercancel", onDragEnd);
  }

  function dispose(): void {
    disposed = true;
    if (placedClickTimer) clearTimeout(placedClickTimer);
    if (refreshFrame != null) window.cancelAnimationFrame(refreshFrame);
    clearFocusHighlight?.();
    resizeObserver?.disconnect();
    mutationObserver?.disconnect();
    if (container) removeContainerListeners(container);
    removeGlobalListeners();
  }

  onUnmounted(dispose);

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
    dragging,
    selectThread,
    startDrag,
    movePinWithKeyboard,
    placeContextComment,
    closeContextMenu,
  };
}
