/**
 * Shared reactive state for the reparent gesture.
 *
 * Drag-reparenting a node into / out of a sequence is a two-part gesture:
 *
 *   - Without Cmd/Ctrl held → the sequence auto-resizes to contain the node
 *     (`resizeParent` during `nodetranslated`). The `.parent` pointer stays
 *     as-is, so on reload the node is still logically inside its original
 *     parent. This is the default rete-scopes "grow to fit children"
 *     behaviour and we want to keep it.
 *
 *   - With Cmd/Ctrl held → the gesture actually reparents. Drop on a
 *     sequence's bbox = `.parent = that sequence`. Drop on empty canvas =
 *     `.parent = undefined` (root). Persists to the server.
 *
 * This module keeps the modifier state and the active-drag flag in plain
 * refs so `Sequence.vue` can react to both at once (highlight drop targets
 * only when a reparent gesture is in-flight — i.e. modifier held AND a
 * drag is active).
 *
 * We deliberately do NOT use `useLive.pushEvent` here — this is pure client
 * state with no server round-trip. See
 * `feedback_no_liveview_for_pure_client_state.md`.
 */

import { ref, computed } from "vue";

/** True while a reparent modifier key is currently held down. */
const modifierHeld = ref(false);

/** True while a node drag is in flight. Set on `nodepicked`, cleared on `nodedragged`. */
const dragActive = ref(false);

/**
 * Drop targets should light up only while both are true: modifier held AND
 * a drag is in progress. Before Sequence.vue consumes this, it also checks
 * that the rendered sequence is NOT itself part of the moving selection
 * (you can't drop into yourself).
 */
export const reparentGestureActive = computed(() => modifierHeld.value && dragActive.value);

/** Matches `metaKey` on Mac, `ctrlKey` elsewhere — the "precision" modifier. */
function isReparentModifier(event: KeyboardEvent | MouseEvent | PointerEvent): boolean {
  return event.metaKey || event.ctrlKey;
}

/**
 * Update the modifier state from a pointer event. Call this from any
 * `pointerdown` / `pointermove` / `pointerup` handler that sees the raw
 * event. Covers the case where keyboard events never reach
 * `document.addEventListener("keydown", ...)` — e.g. when the app is
 * embedded in an iframe harness (Cowork preview) that swallows keyboard
 * focus before it reaches the inner page.
 */
export function syncReparentModifierFromPointerEvent(
  event: PointerEvent | MouseEvent,
): void {
  modifierHeld.value = isReparentModifier(event);
}

/**
 * Install a single document-level listener pair that tracks the modifier
 * state. Idempotent — calling multiple times adds only one listener set.
 * Returns a teardown function.
 */
let listenersInstalled = false;
let installedTeardown: (() => void) | null = null;

export function installReparentModifierListeners(): () => void {
  if (listenersInstalled && installedTeardown) {
    return installedTeardown;
  }

  const onKeyDown = (e: KeyboardEvent) => {
    if (isReparentModifier(e)) {
      modifierHeld.value = true;
    }
  };
  const onKeyUp = (e: KeyboardEvent) => {
    // Some browsers fire keyup for only one of Cmd/Ctrl after both were
    // pressed; re-read from the event to stay in sync.
    modifierHeld.value = isReparentModifier(e);
    if (e.key === "Meta" || e.key === "Control") {
      modifierHeld.value = false;
    }
  };
  const onBlur = () => {
    modifierHeld.value = false;
  };

  document.addEventListener("keydown", onKeyDown);
  document.addEventListener("keyup", onKeyUp);
  window.addEventListener("blur", onBlur);

  listenersInstalled = true;
  installedTeardown = () => {
    document.removeEventListener("keydown", onKeyDown);
    document.removeEventListener("keyup", onKeyUp);
    window.removeEventListener("blur", onBlur);
    listenersInstalled = false;
    installedTeardown = null;
  };
  return installedTeardown;
}

/** Called by the scopes preset when a pick starts a drag gesture. */
export function markDragActive(): void {
  dragActive.value = true;
}

/** Called by the scopes preset when a drag gesture ends (dragged or cancelled). */
export function markDragInactive(): void {
  dragActive.value = false;
}

/** Read the current modifier state synchronously — used by the scopes preset on `nodedragged`. */
export function isReparentModifierActive(): boolean {
  return modifierHeld.value;
}
