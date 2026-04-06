import { onUnmounted, ref, watch } from "vue";

const PATROL_BASE_SPEED = 8; // %/s
const ARRIVAL_THRESHOLD = 0.3; // %
const MAX_DT = 0.05; // 50ms cap

/**
 * Patrol animation for NPC pins that move along connection routes.
 * Supports loop, ping_pong, and one_way modes.
 *
 * routeIndex = the waypoint the pin is currently moving TOWARD.
 * On arrival, advanceIndex sets the NEXT target based on mode.
 *
 * @param {Object} opts
 * @param {import('vue').Ref<Array>} opts.explorationPins - all pins with patrolRoute data
 * @param {Function} opts.percentToPixel - (pctX, pctY) => { x, y }
 * @param {Function} opts.getPinNode - (pinId) => Konva.Group node or null
 */
export function usePatrols({ explorationPins, percentToPixel, getPinNode }) {
  const globalPaused = ref(false);

  let patrolPins = [];
  let patrolStates = {};
  let frameId = null;
  let lastTime = 0;

  // --- Init ---

  function initPatrolData() {
    cleanup();

    const pins = explorationPins.value || [];

    patrolPins = pins.filter(
      (p) =>
        p.patrolMode &&
        p.patrolMode !== "none" &&
        !p.isPlayable &&
        p.visibility !== "hide" &&
        p.patrolRoute &&
        p.patrolRoute.length >= 2,
    );

    patrolStates = {};
    for (const pin of patrolPins) {
      patrolStates[pin.id] = {
        routeIndex: 1, // Start moving toward second point (first is starting position)
        direction: 1, // 1=forward, -1=backward (for ping_pong)
        paused: false,
        pauseTimer: null,
        moving: true,
        currentX: pin.positionX,
        currentY: pin.positionY,
      };
    }

    if (patrolPins.length > 0) {
      ensureLoop();
    }
  }

  watch(explorationPins, initPatrolData, { immediate: true });

  // --- Animation loop ---

  function ensureLoop() {
    if (!frameId) {
      lastTime = performance.now();
      frameId = requestAnimationFrame(loop);
    }
  }

  function loop(timestamp) {
    const dt = Math.min((timestamp - lastTime) / 1000, MAX_DT);
    lastTime = timestamp;

    const anyMoving = globalPaused.value ? false : stepAll(dt);

    // Keep loop alive if there are active patrols (they might unpause)
    if (anyMoving || hasActivePatrols()) {
      frameId = requestAnimationFrame(loop);
    } else {
      frameId = null;
    }
  }

  function hasActivePatrols() {
    return patrolPins.some((p) => {
      const s = patrolStates[p.id];
      return s?.moving;
    });
  }

  // --- Step all patrols ---

  function stepAll(dt) {
    let anyMoving = false;

    for (const pin of patrolPins) {
      const state = patrolStates[pin.id];
      if (!state || !state.moving || state.paused) {
        continue;
      }

      const route = pin.patrolRoute;
      if (state.routeIndex < 0 || state.routeIndex >= route.length) {
        state.moving = false;
        continue;
      }

      const target = route[state.routeIndex];
      const dx = target.x - state.currentX;
      const dy = target.y - state.currentY;
      const dist = Math.sqrt(dx * dx + dy * dy);

      if (dist < ARRIVAL_THRESHOLD) {
        // Snap to target
        state.currentX = target.x;
        state.currentY = target.y;
        updatePinPosition(pin.id, state.currentX, state.currentY);

        // Pause at pin stops if configured
        if (target.isPinStop && pin.patrolPauseMs > 0) {
          state.paused = true;
          state.pauseTimer = setTimeout(() => {
            state.paused = false;
            state.pauseTimer = null;
            advanceIndex(pin, state);
            ensureLoop();
          }, pin.patrolPauseMs);
        } else {
          advanceIndex(pin, state);
        }
      } else {
        // Move toward target
        const speed = PATROL_BASE_SPEED * (pin.patrolSpeed || 1.0);
        const step = speed * dt;
        const ratio = Math.min(step / dist, 1);
        state.currentX += dx * ratio;
        state.currentY += dy * ratio;
        updatePinPosition(pin.id, state.currentX, state.currentY);
        anyMoving = true;
      }
    }

    return anyMoving;
  }

  // --- Advance route index by mode ---

  function advanceIndex(pin, state) {
    const route = pin.patrolRoute;

    switch (pin.patrolMode) {
      case "loop":
        state.routeIndex = (state.routeIndex + 1) % route.length;
        break;

      case "ping_pong": {
        const next = state.routeIndex + state.direction;
        if (next >= route.length || next < 0) {
          state.direction *= -1;
          state.routeIndex += state.direction;
        } else {
          state.routeIndex = next;
        }
        break;
      }

      case "one_way":
        if (state.routeIndex + 1 >= route.length) {
          state.moving = false;
        } else {
          state.routeIndex++;
        }
        break;
    }
  }

  // --- Konva position update ---

  function updatePinPosition(pinId, pctX, pctY) {
    const node = getPinNode(pinId);
    if (!node) {
      return;
    }
    const { x, y } = percentToPixel(pctX, pctY);
    node.position({ x, y });
    node.getLayer()?.batchDraw();
  }

  // --- Global pause/resume ---

  function pause() {
    globalPaused.value = true;
  }

  function resume() {
    globalPaused.value = false;
    ensureLoop();
  }

  // --- Per-pin pause/resume ---

  function pausePin(pinId) {
    const state = patrolStates[pinId];
    if (!state) {
      return;
    }
    if (state.pauseTimer) {
      clearTimeout(state.pauseTimer);
      state.pauseTimer = null;
    }
    state.moving = false;
  }

  function resumePin(pinId) {
    const state = patrolStates[pinId];
    if (!state) {
      return;
    }
    const pin = patrolPins.find((p) => p.id === pinId);
    if (!pin || !pin.patrolRoute || pin.patrolRoute.length < 2) {
      return;
    }
    state.moving = true;
    state.paused = false;
    ensureLoop();
  }

  // --- Cleanup ---

  function cleanup() {
    if (frameId) {
      cancelAnimationFrame(frameId);
      frameId = null;
    }
    for (const state of Object.values(patrolStates)) {
      if (state.pauseTimer) {
        clearTimeout(state.pauseTimer);
      }
    }
  }

  onUnmounted(cleanup);

  return {
    pause,
    resume,
    pausePin,
    resumePin,
  };
}
