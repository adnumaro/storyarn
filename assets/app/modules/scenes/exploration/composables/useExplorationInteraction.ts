import { computed, type ComputedRef, type Ref } from "vue";
import type { LiveInterface } from "@shared/composables/useLive.ts";

interface ExplorationActionData {
  [key: string]: unknown;
}

interface ExplorationZone {
  id: number | string;
  visibility: string;
  actionType: string | null;
  isWalkable: boolean;
  targetType: string | null;
  targetId: number | string | null;
  actionData: ExplorationActionData;
  fillColor: string | null;
  opacity: number | null;
}

interface ExplorationPin {
  id: number | string;
  visibility: string;
  flowId: number | string | null;
}

interface ZoneShowOverride {
  fill: string;
  opacity: number;
}

type MaybeComputedRef<T> = Ref<T> | ComputedRef<T>;

interface UseExplorationInteractionOpts {
  pushEvent: LiveInterface["pushEvent"];
  explorationZones: MaybeComputedRef<ExplorationZone[]>;
  explorationPins: MaybeComputedRef<ExplorationPin[]>;
  showZones: MaybeComputedRef<boolean>;
}

function isHiddenOrDisabled(visibility: string): boolean {
  return visibility === "hide" || visibility === "disable";
}

function isWalkableOnly(zone: ExplorationZone): boolean {
  const actionType = zone.actionType || "action";
  return zone.isWalkable && !zone.targetType && actionType === "walkable";
}

function actionHasInstructions(zone: ExplorationZone): boolean {
  const assignments = zone.actionData?.assignments;
  return Array.isArray(assignments) && assignments.length > 0;
}

function actionHasTarget(zone: ExplorationZone): boolean {
  return !!zone.targetType && !!zone.targetId;
}

function isActionClickable(zone: ExplorationZone): boolean {
  return actionHasInstructions(zone) || actionHasTarget(zone);
}

function isZoneClickable(zone: ExplorationZone): boolean {
  if (isHiddenOrDisabled(zone.visibility) || isWalkableOnly(zone)) return false;
  const actionType = zone.actionType || "action";
  if (actionType === "collection") return true;
  return actionType === "action" && isActionClickable(zone);
}

function pinHasFlow(pin: ExplorationPin): boolean {
  return pin.flowId !== null && pin.flowId !== undefined && pin.flowId !== "";
}

function isPinClickable(pin: ExplorationPin): boolean {
  return !isHiddenOrDisabled(pin.visibility) && pinHasFlow(pin);
}

/**
 * Composable for exploration mode element interactions.
 * Handles zone/pin click events and show-zones visual mode.
 */
export function useExplorationInteraction({
  pushEvent,
  explorationZones,
  explorationPins,
  showZones,
}: UseExplorationInteractionOpts) {
  // --- Zone click ---

  function handleZoneClick(zoneId: number | string): void {
    const zone = explorationZones.value.find((z) => z.id === zoneId);
    if (!zone || !isZoneClickable(zone)) return;

    const actionType = zone.actionType || "action";
    pushEvent("exploration_element_click", {
      element_type: "zone",
      element_id: zone.id,
      action_type: actionType,
      action_data: zone.actionData || {},
      target_type: actionType === "action" ? zone.targetType || null : null,
      target_id: actionType === "action" ? zone.targetId || null : null,
    });
  }

  // --- Pin click ---

  function handlePinClick(pinId: number | string): void {
    const pin = explorationPins.value.find((p) => p.id === pinId);
    if (!pin || !isPinClickable(pin)) {
      return;
    }

    pushEvent("exploration_element_click", {
      element_type: "pin",
      element_id: pin.id,
      flow_id: pin.flowId || null,
    });
  }

  // --- Show-zones visual overrides ---

  function zoneShowOverride(zone: ExplorationZone): ZoneShowOverride | null {
    if (!showZones.value) return null;

    if (isWalkableOnly(zone)) return { fill: "#4ade80", opacity: 0.2 };
    return { fill: zone.fillColor || "#3b82f6", opacity: zone.opacity ?? 0.3 };
  }

  // --- Clickability check (for cursor/listening) ---

  const clickableZoneIds = computed<Set<number | string>>(() => {
    const ids = new Set<number | string>();
    for (const zone of explorationZones.value) {
      if (isZoneClickable(zone)) ids.add(zone.id);
    }
    return ids;
  });

  const clickablePinIds = computed<Set<number | string>>(() => {
    const ids = new Set<number | string>();
    for (const pin of explorationPins.value) {
      if (isPinClickable(pin)) ids.add(pin.id);
    }
    return ids;
  });

  return {
    handleZoneClick,
    handlePinClick,
    zoneShowOverride,
    clickableZoneIds,
    clickablePinIds,
  };
}
