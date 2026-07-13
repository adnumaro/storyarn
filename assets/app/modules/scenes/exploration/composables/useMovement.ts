import { onUnmounted, ref, watch, type ComputedRef, type Ref } from "vue";
import type { ExplorationPin, ExplorationZone, PartyPosition, PixelPoint } from "../types";
import type { Node as KonvaNode } from "konva/lib/Node";
import { findShortestWalkablePath, isPointInWalkableArea } from "../lib/walkablePath";

// --- Constants (matching V1 exactly) ---
const MOVEMENT_SPEED = 15; // %/s
const PARTY_SPEED_FACTOR = 0.8;
const PARTY_DELAY_MS = 200;
const PARTY_SPREAD = 2; // % offset
const ARRIVAL_THRESHOLD = 0.3; // %
const MAX_DT = 0.05; // 50ms cap

interface UseMovementOpts {
  explorationPins: Ref<ExplorationPin[]> | ComputedRef<ExplorationPin[]>;
  explorationZones: Ref<ExplorationZone[]> | ComputedRef<ExplorationZone[]>;
  flowMode: Ref<boolean> | ComputedRef<boolean>;
  percentToPixel: (pctX: number, pctY: number) => PixelPoint;
  getPinNode: (pinId: number | string) => KonvaNode | null;
}

/**
 * Movement engine for exploration mode.
 * Handles click-to-move with leader/party following and walkable area enforcement.
 * Updates Konva node positions directly for 60fps performance (bypasses Vue reactivity).
 */
export function useMovement({
  explorationPins,
  explorationZones,
  flowMode,
  percentToPixel,
  getPinNode,
}: UseMovementOpts) {
  // --- State ---
  const leaderMoving = ref(false);

  let leaderPin: ExplorationPin | null = null;
  let partyPins: ExplorationPin[] = [];
  let walkableZones: ExplorationZone[] = [];

  let leaderCurrentX = 0;
  let leaderCurrentY = 0;
  let leaderTargetX = 0;
  let leaderTargetY = 0;
  let leaderPath: PixelPoint[] = [];

  let partyPositions: PartyPosition[] = []; // [{id, x, y}]
  let partyTargets: PartyPosition[] = []; // [{id, x, y}]
  let partyMoving = false;

  let frameId: number | null = null;
  let lastTime = 0;
  let partyTimeout: ReturnType<typeof setTimeout> | null = null;

  // --- Init from pin/zone data ---

  function initMovementData() {
    const pins = explorationPins.value || [];
    const zones = explorationZones.value || [];

    walkableZones = zones.filter(isMovementWalkableZone);

    const playablePins = pins.filter(isMovementPlayablePin);
    leaderPin = playablePins.find((p) => p.isLeader) || null;
    partyPins = playablePins.filter((p) => !p.isLeader);

    if (leaderPin) {
      leaderCurrentX = leaderPin.positionX;
      leaderCurrentY = leaderPin.positionY;
      leaderTargetX = leaderCurrentX;
      leaderTargetY = leaderCurrentY;
    }

    partyPositions = partyPins.map((p) => ({
      id: p.id,
      x: p.positionX,
      y: p.positionY,
    }));
    partyTargets = partyPositions.map((p) => ({ ...p }));
  }

  // Re-init when data changes
  watch([explorationPins, explorationZones], initMovementData, {
    immediate: true,
  });

  // --- Stage click handler ---

  function handleStageClick(pctX: number, pctY: number): "walkable" | "blocked" | null {
    if (flowMode.value) {
      return null;
    }
    if (!leaderPin) {
      return null;
    }

    const target = { x: pctX, y: pctY };
    if (!isPointInWalkableArea(target, walkableZones)) {
      return "blocked";
    }

    const path = findShortestWalkablePath(
      { x: leaderCurrentX, y: leaderCurrentY },
      target,
      walkableZones,
    );
    if (!path) {
      return "blocked";
    }

    startMovement(pctX, pctY, path);
    return "walkable";
  }

  // --- Movement start ---

  function startMovement(targetX: number, targetY: number, path: PixelPoint[]) {
    leaderTargetX = targetX;
    leaderTargetY = targetY;
    leaderPath = path;
    leaderMoving.value = true;

    // Start party following after delay
    if (partyTimeout) {
      clearTimeout(partyTimeout);
    }
    if (partyPins.length > 0) {
      partyTimeout = setTimeout(() => startPartyFollowing(), PARTY_DELAY_MS);
    }

    // Start animation loop if not running
    if (!frameId) {
      lastTime = performance.now();
      frameId = requestAnimationFrame(movementLoop);
    }
  }

  // --- Party fan formation ---

  function startPartyFollowing() {
    if (!leaderMoving.value) {
      return;
    }

    const dx = leaderTargetX - leaderCurrentX;
    const dy = leaderTargetY - leaderCurrentY;
    const dist = Math.sqrt(dx * dx + dy * dy);

    if (dist < ARRIVAL_THRESHOLD) {
      return;
    }

    const ndx = dx / dist;
    const ndy = dy / dist;
    // Perpendicular for fan spread
    const perpX = -ndy;
    const perpY = ndx;

    const numParty = partyPins.length;
    partyTargets = partyPins.map((p, i) => {
      const offset = (i - (numParty - 1) / 2) * PARTY_SPREAD;
      return {
        id: p.id,
        x: leaderTargetX - ndx * PARTY_SPREAD + perpX * offset,
        y: leaderTargetY - ndy * PARTY_SPREAD + perpY * offset,
      };
    });
    partyMoving = true;
  }

  // --- Animation loop ---

  function movementLoop(timestamp: number) {
    const dt = Math.min((timestamp - lastTime) / 1000, MAX_DT);
    lastTime = timestamp;

    let anyMoving = false;

    if (leaderMoving.value) {
      if (stepLeader(dt)) {
        anyMoving = true;
      }
    }

    if (partyMoving) {
      if (stepParty(dt)) {
        anyMoving = true;
      }
    }

    if (anyMoving) {
      frameId = requestAnimationFrame(movementLoop);
    } else {
      frameId = null;
      leaderMoving.value = false;
    }
  }

  // --- Leader step ---

  function stepLeader(dt: number): boolean {
    let remainingStep = MOVEMENT_SPEED * dt;

    while (leaderPath.length > 0) {
      const waypoint = leaderPath[0];
      const dx = waypoint.x - leaderCurrentX;
      const dy = waypoint.y - leaderCurrentY;
      const dist = Math.sqrt(dx * dx + dy * dy);

      if (dist < ARRIVAL_THRESHOLD || dist <= remainingStep) {
        leaderCurrentX = waypoint.x;
        leaderCurrentY = waypoint.y;
        leaderPath.shift();
        updateLeaderPosition();

        if (leaderPath.length === 0) {
          leaderMoving.value = false;
          return false;
        }

        if (dist >= remainingStep) {
          return true;
        }

        remainingStep -= dist;
        continue;
      }

      const ratio = remainingStep / dist;
      const nextX = leaderCurrentX + dx * ratio;
      const nextY = leaderCurrentY + dy * ratio;

      if (!isPointInWalkableArea({ x: nextX, y: nextY }, walkableZones)) {
        leaderPath = [];
        leaderMoving.value = false;
        return false;
      }

      leaderCurrentX = nextX;
      leaderCurrentY = nextY;
      updateLeaderPosition();
      return true;
    }

    leaderMoving.value = false;
    return false;
  }

  function updateLeaderPosition() {
    if (leaderPin) {
      updatePinPosition(leaderPin.id, leaderCurrentX, leaderCurrentY);
    }
  }

  // --- Party step ---

  function stepParty(dt: number): boolean {
    let anyMoving = false;
    const speed = MOVEMENT_SPEED * PARTY_SPEED_FACTOR * dt;

    for (let i = 0; i < partyPositions.length; i++) {
      const pos = partyPositions[i];
      const target = partyTargets[i];
      if (!target) {
        continue;
      }

      const dx = target.x - pos.x;
      const dy = target.y - pos.y;
      const dist = Math.sqrt(dx * dx + dy * dy);

      if (dist < ARRIVAL_THRESHOLD) {
        pos.x = target.x;
        pos.y = target.y;
        updatePinPosition(pos.id, pos.x, pos.y);
        continue;
      }

      const ratio = Math.min(speed / dist, 1);
      const nextX = pos.x + dx * ratio;
      const nextY = pos.y + dy * ratio;

      // Party members skip walkable check (follow leader)
      pos.x = nextX;
      pos.y = nextY;
      updatePinPosition(pos.id, pos.x, pos.y);
      anyMoving = true;
    }

    if (!anyMoving) {
      partyMoving = false;
    }
    return anyMoving;
  }

  // --- Konva position update ---

  function updatePinPosition(pinId: number | string, pctX: number, pctY: number) {
    const node = getPinNode(pinId);
    if (!node) {
      return;
    }
    const { x, y } = percentToPixel(pctX, pctY);
    node.position({ x, y });
    node.getLayer()?.batchDraw();
  }

  // --- Pause when flow starts ---
  watch(flowMode, (active) => {
    if (active && leaderMoving.value) {
      leaderMoving.value = false;
      leaderPath = [];
      partyMoving = false;
      if (frameId) {
        cancelAnimationFrame(frameId);
        frameId = null;
      }
      if (partyTimeout) {
        clearTimeout(partyTimeout);
        partyTimeout = null;
      }
    }
  });

  // --- Get current positions (for session save) ---

  function getPositions() {
    return {
      leader: leaderPin ? { x: leaderCurrentX, y: leaderCurrentY } : null,
      party: partyPositions.map((p) => ({ id: p.id, x: p.x, y: p.y })),
    };
  }

  // --- Restore positions (from session) ---

  function restorePositions(leader: unknown, party: unknown) {
    const leaderPos = leader as { x: number; y: number } | null;
    const partyPos = party as PartyPosition[] | null;

    if (leaderPos && leaderPin) {
      leaderCurrentX = leaderPos.x;
      leaderCurrentY = leaderPos.y;
      leaderTargetX = leaderPos.x;
      leaderTargetY = leaderPos.y;
      updatePinPosition(leaderPin.id, leaderPos.x, leaderPos.y);
    }
    if (partyPos && partyPos.length > 0) {
      for (const p of partyPos) {
        const idx = partyPositions.findIndex((pp) => pp.id === p.id);
        if (idx >= 0) {
          partyPositions[idx].x = p.x;
          partyPositions[idx].y = p.y;
          partyTargets[idx] = { ...partyTargets[idx], x: p.x, y: p.y };
          updatePinPosition(p.id, p.x, p.y);
        }
      }
    }
  }

  // --- Cleanup ---

  onUnmounted(() => {
    if (frameId) {
      cancelAnimationFrame(frameId);
    }
    if (partyTimeout) {
      clearTimeout(partyTimeout);
    }
  });

  return {
    leaderMoving,
    handleStageClick,
    getPositions,
    restorePositions,
  };
}

export function isMovementWalkableZone(zone: ExplorationZone): boolean {
  return (
    zone.actionType === "walkable" &&
    zone.isWalkable &&
    !!zone.vertices &&
    zone.vertices.length >= 3 &&
    zone.visibility !== "hide"
  );
}

export function isMovementPlayablePin(pin: ExplorationPin): boolean {
  return pin.isPlayable && pin.visibility !== "hide" && pin.visibility !== "disable";
}
