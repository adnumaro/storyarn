import { computed, nextTick, onMounted, onUnmounted, ref, shallowRef, watch } from "vue";
import {
  clearCommentDraft,
  readCommentDraft,
  updateCommentDraft,
} from "@components/comments/commentDraftStorage";
import {
  CommentMagneticDrag,
  type CommentMagneticInitial,
  type CommentMagneticPreview,
} from "@components/comments/commentMagnetism";
import type { CommentContextReference } from "@components/comments/types";
import {
  resolveSheetCommentPosition,
  sheetCommentSnapAdapter,
  SHEET_COMMENT_TARGET_SELECTOR,
} from "../lib/comment-snap-adapter";
import type { useLive } from "@shared/composables/useLive";
import {
  constrainSheetCommentPositionToSurface,
  sheetCommentCanvasPoint,
  sheetCommentSurfaceSize,
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
  draftId: string | null;
  pointerId: number | null;
  target: HTMLElement;
  start: SheetCommentPosition;
  lastClient: SheetCommentPosition;
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
const keyboardDirections: Partial<Record<string, SheetCommentPosition>> = {
  ArrowLeft: { x: -1, y: 0 },
  ArrowRight: { x: 1, y: 0 },
  ArrowUp: { x: 0, y: -1 },
  ArrowDown: { x: 0, y: 1 },
};

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

interface DraftConversationSnapshot {
  open: boolean;
  draftPosition: SheetCommentPosition | null;
  threadId: number | null;
}

function draftConversationClosed(
  current: DraftConversationSnapshot,
  previous?: DraftConversationSnapshot,
): boolean {
  return (
    previous?.open === true &&
    previous.threadId == null &&
    previous.draftPosition != null &&
    current.open === false &&
    current.threadId == null &&
    current.draftPosition == null
  );
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

function samePosition(left: SheetCommentPosition | null | undefined, right: SheetCommentPosition) {
  return left?.x === right.x && left.y === right.y;
}
function contextIdentity(context: CommentContextReference | null | undefined) {
  return context
    ? JSON.stringify([context.type, context.id, context.offset?.x, context.offset?.y])
    : null;
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

  const adapter = sheetCommentSnapAdapter(element);
  return adapter.clamp(adapter.fromScreen({ x: surface.left + surface.width / 2, y: clientY }));
}

function canRestoreDraft(
  state: SheetCommentsPanelState,
  bounds: { width: number; height: number },
): boolean {
  return (
    state.canComment &&
    !state.placing &&
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
  const movedPositions = ref(new Map<number, PendingMove>());
  const pendingDraft = shallowRef<PendingDraft | null>(null);
  const dragPreview = shallowRef<CommentMagneticPreview | null>(null);
  const magnetism = ref(true);
  let request = 0;
  let altHeld = false;
  let geometryObserver: MutationObserver | null = null;
  let geometryFrame: number | null = null;
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
  let restoreRequest = 0;

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
      const moving = drag.value?.thread?.id === thread.id ? dragPreview.value : null;
      const position =
        moving?.position ??
        movedPositions.value.get(thread.id)?.position ??
        (thread.position
          ? resolveSheetCommentPosition(thread.position, thread.context, currentContainer)
          : null);
      const screen = sheetCommentScreenPoint(thread, currentContainer, position);
      return screen ? [{ thread, screen }] : [];
    });
  });
  function currentDraft(): CommentMagneticInitial | null {
    const state = options.state();
    if (
      !container ||
      !state.open ||
      state.presentation !== "canvas" ||
      state.thread ||
      !state.draftPosition
    )
      return null;
    return {
      position: resolveSheetCommentPosition(state.draftPosition, state.draftContext, container),
      context: state.draftContext ?? null,
    };
  }
  const draftPlacement = computed(() => {
    void bounds.value;
    const confirmed = currentDraft();
    if (!confirmed) return null;
    const moving = drag.value && !drag.value.thread ? dragPreview.value : null;
    return moving ?? pendingDraft.value ?? confirmed;
  });
  const draftPoint = computed(() => {
    const draft = draftPlacement.value;
    return draft && container ? sheetCommentPositionForSurface(draft.position, container) : null;
  });
  const panelState = computed<SheetCommentsPanelState>(() => ({
    ...options.state(),
    ...(draftPlacement.value
      ? { draftPosition: draftPlacement.value.position, draftContext: draftPlacement.value.context }
      : {}),
    draftPending: Boolean((drag.value && !drag.value.thread) || pendingDraft.value),
  }));
  const moving = computed(() => Boolean(drag.value?.moved));
  const snapOutline = computed(() => {
    const geometry = dragPreview.value?.candidate?.geometry;
    if (geometry?.kind !== "rect" || !container) return null;
    const rect = container.getBoundingClientRect();
    const size = sheetCommentSurfaceSize(container);
    const sx = rect.width / size.width || 1;
    const sy = rect.height / size.height || 1;
    return {
      left: (geometry.left - rect.left) / sx,
      top: (geometry.top - rect.top) / sy,
      width: geometry.width / sx,
      height: geometry.height / sy,
    };
  });
  const isPending = (id: number) => movedPositions.value.has(id);
  const activePoint = computed(() =>
    selectedThread.value
      ? (pins.value.find((pin) => pin.thread.id === selectedThread.value?.id)?.screen ?? null)
      : draftPoint.value,
  );
  const hoveredPin = computed(() =>
    drag.value ? null : pins.value.find((pin) => pin.thread.id === hoverId.value),
  );
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
    const adapter = sheetCommentSnapAdapter(container);
    return adapter.clamp(adapter.fromScreen({ x: clientX, y: clientY }));
  }

  function storeDraft(preview: CommentMagneticInitial): void {
    updateCommentDraft(options.draftStorageKey(), preview);
  }

  function placeAt(position: SheetCommentPosition, suppress = false): void {
    if (!container) return;
    const adapter = sheetCommentSnapAdapter(container);
    const pointer = adapter.toScreen(position);
    const preview = new CommentMagneticDrag(adapter, { position, context: null }, pointer).update(
      pointer,
      !magnetism.value || suppress,
    );
    storeDraft(preview);
    live.pushEvent("comments_place", { ...preview.position, context: preview.context });
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
    const restoreId = ++restoreRequest;
    const activeRestore = () =>
      !disposed && restoreId === restoreRequest && options.draftStorageKey() === storageKey;
    const finishRestore = () => {
      if (activeRestore()) restoringDraftKey = null;
    };
    const restoreFree = () => {
      if (!activeRestore() || !canRestoreDraft(options.state(), bounds.value)) {
        finishRestore();
        return;
      }
      live.pushEvent(
        "comments_place",
        { ...position, context: null },
        finishRestore,
        finishRestore,
      );
    };
    live.pushEvent(
      "comments_place",
      { ...position, context: stored.context ?? null },
      (reply) => {
        if (reply.ok !== true && reply.context_unavailable === true && stored.context)
          restoreFree();
        else finishRestore();
      },
      finishRestore,
    );
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
    bounds.value = sheetCommentSurfaceSize(container);
    const viewport = scrollViewport(container);
    const top = viewport ? Math.max(0, viewport.top - rect.top) : 0;
    const bottom = viewport ? Math.min(rect.height, viewport.bottom - rect.top) : rect.height;
    visibleBounds.value = {
      width: bounds.value.width,
      height: Math.max(0, bottom - top) / (rect.height / bounds.value.height || 1),
      top: top / (rect.height / bounds.value.height || 1),
    };
    if (drag.value?.moved) updatePreview();
    focusThread();
  }

  function onSurfacePointerDown(event: PointerEvent): void {
    if (
      !placing.value ||
      event.button !== 0 ||
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
    placeAt(position, event.altKey);
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
      x: ((event.clientX - rect.left) * bounds.value.width) / rect.width,
      y: ((event.clientY - rect.top) * bounds.value.height) / rect.height,
    };
  }

  function placeContextComment(): void {
    if (!options.state().canComment || !contextPosition.value) {
      closeContextMenu();
      return;
    }
    placeAt(contextPosition.value);
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

  function handleDragKey(event: KeyboardEvent): boolean {
    if (!drag.value) return false;
    if (event.key === "Escape") {
      cancelActiveDrag();
      return true;
    }
    if (editableTarget(event.target)) return false;
    if (event.key === "Alt") {
      altHeld = true;
      updatePreview();
    }
    if (event.key === "[" || event.key === "]") {
      cycleContext(event.key === "]" ? 1 : -1);
      return true;
    }
    if (event.key === "Enter" && drag.value.pointerId == null) {
      commitDrag();
      return true;
    }
    return false;
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
    if (event.key === "Enter" && container && keyboardPlacementTarget(event)) {
      event.preventDefault();
      event.stopImmediatePropagation();
      const position = visibleCenterPosition(container);
      placeAt(position);
      return;
    }
    if (event.key.toLowerCase() === "c" && options.state().canComment) {
      event.preventDefault();
      event.stopImmediatePropagation();
      live.pushEvent("comments_mode", { active: !placing.value });
    }
  }

  function keyboardPlacementTarget(event: KeyboardEvent): boolean {
    return placing.value && event.target === container;
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

  function dragInitial(thread: SheetCommentThread | null): CommentMagneticInitial | null {
    if (!container) return null;
    if (!thread) return currentDraft();
    return thread.position && thread.source.status === "available"
      ? {
          position: resolveSheetCommentPosition(thread.position, thread.context, container),
          context: thread.context ?? null,
        }
      : null;
  }
  function beginDrag(
    target: HTMLElement,
    thread: SheetCommentThread | null,
    pointerId: number | null,
    pointer?: SheetCommentPosition,
  ): boolean {
    if (!container || drag.value || !options.state().canComment) return false;
    if (thread ? isPending(thread.id) : pendingDraft.value) return false;
    const initial = dragInitial(thread);
    if (!initial) return false;
    const adapter = sheetCommentSnapAdapter(container);
    const start = pointer ?? adapter.toScreen(initial.position);
    drag.value = {
      thread,
      draftId: options.state().draftId ?? null,
      pointerId,
      target,
      start,
      lastClient: start,
      session: new CommentMagneticDrag(adapter, initial, start),
      moved: false,
    };
    dragPreview.value = null;
    suppressedClick = false;
    moveError.value = false;
    return true;
  }
  function startDrag(event: PointerEvent, thread: SheetCommentThread | null): void {
    if (event.button !== 0) return;
    const target = event.currentTarget as HTMLElement;
    if (!beginDrag(target, thread, event.pointerId, { x: event.clientX, y: event.clientY })) return;
    event.preventDefault();
    altHeld = event.altKey;
    target.focus({ preventScroll: true });
    target.setPointerCapture?.(event.pointerId);
  }
  function ignorePinShortcut(event: KeyboardEvent): boolean {
    return editableTarget(event.target) || event.ctrlKey || event.metaKey;
  }
  function movePinWithKeyboard(event: KeyboardEvent, thread: SheetCommentThread | null): void {
    const direction = keyboardDirections[event.key];
    if (!direction || ignorePinShortcut(event) || !options.state().canComment) return;
    const target = event.currentTarget as HTMLElement;
    if (!drag.value && !beginDrag(target, thread, null)) return;
    const current = drag.value;
    if (!current || current.pointerId != null || current.target !== target) return;
    event.preventDefault();
    event.stopPropagation();
    const step = event.shiftKey ? 1 : 8;
    altHeld = event.altKey;
    drag.value = {
      ...current,
      moved: true,
      lastClient: {
        x: current.lastClient.x + direction.x * step,
        y: current.lastClient.y + direction.y * step,
      },
    };
    updatePreview();
  }
  function updatePreview(): void {
    const current = drag.value;
    if (!current) return;
    dragPreview.value = current.session.update(current.lastClient, !magnetism.value || altHeld);
    hoverId.value = null;
  }
  function updateDraggedPosition(client: SheetCommentPosition): void {
    const current = drag.value;
    if (!current) return;
    if (!current.moved && Math.hypot(client.x - current.start.x, client.y - current.start.y) < 4)
      return;
    drag.value = { ...current, lastClient: client, moved: true };
    updatePreview();
  }
  function toggleMagnetism(): void {
    magnetism.value = !magnetism.value;
    if (drag.value?.moved) updatePreview();
  }
  function cycleContext(direction: 1 | -1 = 1): void {
    if (!drag.value?.moved || !magnetism.value || altHeld) return;
    dragPreview.value = drag.value.session.cycle(direction);
  }
  function onKeyUp(event: KeyboardEvent): void {
    if (event.key === "Alt") {
      altHeld = false;
      if (drag.value?.moved) updatePreview();
    }
  }
  function onPinBlur(): void {
    hoverId.value = null;
    if (drag.value?.pointerId === null) cancelActiveDrag();
  }
  function onLostCapture(event: PointerEvent): void {
    if (drag.value?.pointerId === event.pointerId) cancelActiveDrag();
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
    if (
      !current ||
      current.pointerId == null ||
      !current.moved ||
      autoScrollFrame != null ||
      !container
    )
      return;
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
    altHeld = event.altKey;
    drag.value = { ...current, lastClient: client };
    updateDraggedPosition(client);
    scheduleAutoScroll();
  }

  function endSession(): PinDrag | null {
    const current = drag.value;
    stopAutoScroll();
    drag.value = null;
    dragPreview.value = null;
    if (current?.pointerId != null && current.target.hasPointerCapture?.(current.pointerId))
      current.target.releasePointerCapture(current.pointerId);
    return current;
  }
  function onDragEnd(event: PointerEvent): void {
    if (!drag.value || drag.value.pointerId !== event.pointerId) return;
    if (event.type === "pointercancel") cancelActiveDrag();
    else {
      onDragMove(event);
      commitDrag();
    }
  }
  function commitDrag(): void {
    const current = drag.value;
    if (!current) return;
    if (current.moved) updatePreview();
    const preview = dragPreview.value;
    endSession();
    if (!current.moved || !preview || !options.state().canComment) return;
    suppressedClick = current.pointerId != null;
    if (current.thread) {
      if (current.pointerId != null) hoverId.value = current.thread.id;
      persistThreadPosition(current.thread, preview);
    } else persistDraftPosition(current.draftId, preview);
  }
  function cancelActiveDrag(): void {
    if (drag.value?.moved && drag.value.pointerId != null) suppressedClick = true;
    drag.value?.session.cancel();
    endSession();
  }
  function persistDraftPosition(draftId: string | null, preview: CommentMagneticInitial): void {
    const pending = { ...preview, draftId, request: ++request };
    pendingDraft.value = pending;
    const rollback = () => {
      if (disposed || pendingDraft.value?.request !== pending.request) return;
      pendingDraft.value = null;
      moveError.value = true;
    };
    live.pushEvent(
      "comments_place",
      { ...preview.position, context: preview.context, moving_draft: true, draft_id: draftId },
      (reply) => {
        if (reply.ok !== true) rollback();
        else if (pendingDraft.value?.request === pending.request) confirmDraft();
      },
      rollback,
    );
  }
  function samePlacement(
    thread: SheetCommentThread | undefined,
    placement: CommentMagneticInitial,
  ): boolean {
    return Boolean(
      thread &&
      samePosition(thread.position, placement.position) &&
      contextIdentity(thread.context) === contextIdentity(placement.context),
    );
  }
  function acknowledgedUnchanged(
    returned: SheetCommentThread | undefined,
    pending: PendingMove,
    latest: SheetCommentThread | undefined,
  ): boolean {
    return (
      returned?.revision === pending.revision &&
      samePlacement(returned, pending) &&
      samePlacement(latest, pending)
    );
  }
  function persistThreadPosition(
    thread: SheetCommentThread,
    preview: CommentMagneticInitial,
  ): void {
    const pending = { ...preview, request: ++request, revision: thread.revision };
    movedPositions.value.set(thread.id, pending);
    const finish = (failed: boolean, returned?: SheetCommentThread) => {
      if (disposed || movedPositions.value.get(thread.id)?.request !== pending.request) return;
      const latest = visibleThreads.value.find((item) => item.id === thread.id);
      const unchanged = acknowledgedUnchanged(returned, pending, latest);
      if (failed || !latest || latest.revision !== pending.revision || unchanged)
        movedPositions.value.delete(thread.id);
      if (failed) moveError.value = true;
    };
    live.pushEvent(
      "comments_move",
      {
        thread_id: thread.id,
        ...preview.position,
        context: preview.context,
        expected_revision: thread.revision,
      },
      (reply) => finish(reply.ok !== true, reply.thread as SheetCommentThread | undefined),
      () => finish(true),
    );
  }
  function confirmDraft(): void {
    const pending = pendingDraft.value;
    if (!pending) return;
    const state = options.state();
    if (
      state.draftId === pending.draftId &&
      samePosition(state.draftPosition, pending.position) &&
      contextIdentity(state.draftContext) === contextIdentity(pending.context)
    ) {
      storeDraft(pending);
      pendingDraft.value = null;
    }
  }
  watch(
    () => [
      options.pins().map((thread) => [thread.id, thread.revision]),
      selectedThread.value?.revision,
    ],
    () => {
      for (const [id, pending] of movedPositions.value) {
        const latest = visibleThreads.value.find((thread) => thread.id === id);
        if (!latest || latest.revision !== pending.revision) movedPositions.value.delete(id);
      }
      const active = drag.value?.thread;
      if (
        active &&
        !visibleThreads.value.some(
          (thread) => thread.id === active.id && thread.revision === active.revision,
        )
      )
        cancelActiveDrag();
      scheduleGeometryRefresh();
      focusThread();
    },
  );
  function cancelInvalidDraft(): void {
    const state = options.state();
    const pending = pendingDraft.value;
    if (pending && (!currentDraft() || state.draftId !== pending.draftId))
      pendingDraft.value = null;
    const current = drag.value;
    if (current && !current.thread && (!currentDraft() || state.draftId !== current.draftId))
      cancelActiveDrag();
  }
  watch(() => [options.state().draftPosition, options.state().draftContext], confirmDraft);
  watch(
    () => ({
      storageKey: options.draftStorageKey(),
      open: options.state().open,
      draftPosition: options.state().draftPosition ?? null,
      draftContext: options.state().draftContext ?? null,
      draftId: options.state().draftId ?? null,
      threadId: options.state().thread?.id ?? null,
    }),
    (current, previous) => {
      if (current.draftPosition)
        updateCommentDraft(current.storageKey, {
          position: current.draftPosition,
          context: current.draftContext,
        });
      if (previous && current.storageKey !== previous.storageKey) {
        pendingDraft.value = null;
        cancelActiveDrag();
        return;
      }
      if (draftConversationClosed(current, previous)) clearCommentDraft(current.storageKey);
      cancelInvalidDraft();
    },
  );
  watch(
    () => options.draftStorageKey(),
    async () => {
      restoringDraftKey = null;
      restoreRequest++;
      pendingDraft.value = null;
      cancelActiveDrag();
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

  watch(
    () => options.state().canComment,
    (allowed) => {
      if (!allowed) cancelActiveDrag();
    },
  );
  function scheduleGeometryRefresh(): void {
    if (disposed || geometryFrame != null) return;
    geometryFrame = requestAnimationFrame(() => {
      geometryFrame = null;
      refreshBounds();
    });
  }
  function observeTargets(): void {
    resizeObserver?.disconnect();
    if (!container) return;
    resizeObserver?.observe(container);
    if (scrollOwnerElement) resizeObserver?.observe(scrollOwnerElement);
    for (const target of container.querySelectorAll(SHEET_COMMENT_TARGET_SELECTOR))
      resizeObserver?.observe(target);
  }
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
    document.addEventListener("keyup", onKeyUp, true);
    window.addEventListener("blur", cancelActiveDrag);
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
    observeTargets();
    geometryObserver = new MutationObserver((mutations) => {
      if (
        !mutations.some(
          (mutation) =>
            mutation.target instanceof Element &&
            !mutation.target.closest('[data-sheet-comment-ui="true"]'),
        )
      )
        return;
      observeTargets();
      scheduleGeometryRefresh();
    });
    geometryObserver.observe(container, {
      childList: true,
      subtree: true,
      attributes: true,
      characterData: true,
    });
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
    geometryObserver?.disconnect();
    if (geometryFrame != null) cancelAnimationFrame(geometryFrame);
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
    document.removeEventListener("keyup", onKeyUp, true);
    window.removeEventListener("blur", cancelActiveDrag);
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
    panelState,
    dragPreview,
    snapOutline,
    moving,
    magnetism,
    isPending,
    toggleMagnetism,
    cycleContext,
    onPinBlur,
    onLostCapture,
  };
}
