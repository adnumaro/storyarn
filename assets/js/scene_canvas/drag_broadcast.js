/**
 * Shared constants and throttle helper for real-time drag broadcasting.
 *
 * Pins and annotations use a faster interval (lighter payload: {id, x, y}).
 * Zones use a slower interval (heavier payload: {id, vertices[]}).
 */

/** Broadcast interval for pin/annotation drags (ms). */
export const MARKER_DRAG_INTERVAL = 50;

/** Broadcast interval for zone drags (ms). */
export const ZONE_DRAG_INTERVAL = 100;

/**
 * Creates a throttled drag broadcaster.
 *
 * Returns `{ maybePush(pushFn), reset() }`.
 * - `maybePush(fn)` calls `fn` only if enough time has elapsed since last push.
 * - `reset()` clears the timer so the next call always fires.
 *
 * @param {number} intervalMs - Minimum ms between pushes
 */
export function createDragThrottle(intervalMs) {
  let lastPushTime = 0;

  return {
    maybePush(pushFn) {
      const now = Date.now();
      if (now - lastPushTime >= intervalMs) {
        lastPushTime = now;
        try {
          pushFn();
        } catch (_) {
          // LiveView disconnected during drag — safe to ignore
        }
      }
    },

    reset() {
      lastPushTime = 0;
    },
  };
}
