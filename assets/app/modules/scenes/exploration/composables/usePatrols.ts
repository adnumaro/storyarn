import { onUnmounted, ref, watch, type ComputedRef, type Ref } from "vue";
import type { Node as KonvaNode } from "konva/lib/Node";
import type { ScenePatrolRoutePoint } from "@modules/scenes/types/routes";

const PATROL_BASE_SPEED = 8; // %/s
const ARRIVAL_THRESHOLD = 0.3; // %
const MAX_DT = 0.05; // 50ms cap

interface PixelPoint {
  x: number;
  y: number;
}

interface PatrolPin {
  id: number | string;
  positionX: number;
  positionY: number;
  isPlayable: boolean;
  visibility: string;
  patrolMode: string | null;
  patrolRoute: ScenePatrolRoutePoint[] | null;
  patrolPauseMs: number;
  patrolSpeed: number | null;
}

interface PatrolState {
  routeIndex: number;
  direction: number; // 1=forward, -1=backward (for ping_pong)
  paused: boolean;
  pauseTimer: ReturnType<typeof setTimeout> | null;
  moving: boolean;
  currentX: number;
  currentY: number;
}

interface UsePatrolsOpts {
  explorationPins: Ref<PatrolPin[]> | ComputedRef<PatrolPin[]>;
  percentToPixel: (pctX: number, pctY: number) => PixelPoint;
  getPinNode: (pinId: number | string) => KonvaNode | null;
}

/**
 * Patrol animation for NPC pins that move along connection routes.
 * Supports loop, ping_pong, and one_way modes.
 *
 * routeIndex = the waypoint the pin is currently moving TOWARD.
 * On arrival, advanceIndex sets the NEXT target based on mode.
 */
export function usePatrols({ explorationPins, percentToPixel, getPinNode }: UsePatrolsOpts) {
  const globalPaused = ref(false);

  let patrolPins: PatrolPin[] = [];
  let patrolStates: Record<string | number, PatrolState> = {};
  let frameId: number | null = null;
  let lastTime = 0;

  // --- Init ---

  function initPatrolData(): void {
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

  function ensureLoop(): void {
    if (!frameId) {
      lastTime = performance.now();
      frameId = requestAnimationFrame(loop);
    }
  }

  function loop(timestamp: number): void {
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

  function hasActivePatrols(): boolean {
    return patrolPins.some((p) => {
      const s = patrolStates[p.id];
      return s?.moving;
    });
  }

  // --- Step all patrols ---

  /** Step a single pin toward its next waypoint. Returns true if still moving. */
  function stepPin(pin: PatrolPin, state: PatrolState, dt: number): boolean {
    const route = pin.patrolRoute!;
    if (state.routeIndex < 0 || state.routeIndex >= route.length) {
      state.moving = false;
      return false;
    }

    const target = route[state.routeIndex];
    const dx = target.x - state.currentX;
    const dy = target.y - state.currentY;
    const dist = Math.sqrt(dx * dx + dy * dy);

    if (dist < ARRIVAL_THRESHOLD) {
      state.currentX = target.x;
      state.currentY = target.y;
      updatePinPosition(pin.id, state.currentX, state.currentY);
      handleArrival(pin, state, target);
      return false;
    }

    // Move toward target
    const speed = PATROL_BASE_SPEED * (pin.patrolSpeed || 1.0);
    const ratio = Math.min((speed * dt) / dist, 1);
    state.currentX += dx * ratio;
    state.currentY += dy * ratio;
    updatePinPosition(pin.id, state.currentX, state.currentY);
    return true;
  }

  function handleArrival(pin: PatrolPin, state: PatrolState, target: ScenePatrolRoutePoint): void {
    const pauseMs = target.pauseMs ?? (target.isPinStop ? pin.patrolPauseMs : 0);

    if ((target.isStop || target.isPinStop) && pauseMs > 0) {
      state.paused = true;
      state.pauseTimer = setTimeout(() => {
        state.paused = false;
        state.pauseTimer = null;
        advanceIndex(pin, state);
        ensureLoop();
      }, pauseMs);
    } else {
      advanceIndex(pin, state);
    }
  }

  function stepAll(dt: number): boolean {
    let anyMoving = false;

    for (const pin of patrolPins) {
      const state = patrolStates[pin.id];
      if (!state || !state.moving || state.paused) continue;

      if (stepPin(pin, state, dt)) {
        anyMoving = true;
      }
    }

    return anyMoving;
  }

  // --- Advance route index by mode ---

  function advanceIndex(pin: PatrolPin, state: PatrolState): void {
    const route = pin.patrolRoute!;

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

  function updatePinPosition(pinId: number | string, pctX: number, pctY: number): void {
    const node = getPinNode(pinId);
    if (!node) {
      return;
    }
    const { x, y } = percentToPixel(pctX, pctY);
    node.position({ x, y });
    node.getLayer()?.batchDraw();
  }

  // --- Global pause/resume ---

  function pause(): void {
    globalPaused.value = true;
  }

  function resume(): void {
    globalPaused.value = false;
    ensureLoop();
  }

  // --- Cleanup ---

  function cleanup(): void {
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
  };
}
