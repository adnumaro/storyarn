import { computed, type Ref } from "vue";

interface ExplorationZone {
  id: number | string;
  visibility: string;
  actionType: string | null;
  isWalkable: boolean;
  targetType: string | null;
  targetId: number | string | null;
  actionData: Record<string, string | number | boolean | null>;
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

interface UseExplorationInteractionOpts {
  pushEvent: (event: string, payload: Record<string, unknown>) => void;
  explorationZones: Ref<ExplorationZone[]>;
  explorationPins: Ref<ExplorationPin[]>;
  showZones: Ref<boolean>;
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
    if (!zone || zone.visibility === "hide" || zone.visibility === "disable") {
      return;
    }

    const actionType = zone.actionType || "none";
    const isWalkableOnly =
      zone.isWalkable && !zone.targetType && ["none", "walkable"].includes(actionType);

    // Walkable-only zones don't trigger server events (they're for movement)
    if (isWalkableOnly) {
      return;
    }

    // Clickable if it has an action or a target
    const isClickable =
      ["instruction", "collection", "display"].includes(actionType) || !!zone.targetType;

    if (!isClickable) {
      return;
    }

    pushEvent("exploration_element_click", {
      element_type: "zone",
      element_id: zone.id,
      action_type: actionType,
      action_data: zone.actionData || {},
      target_type: zone.targetType || null,
      target_id: zone.targetId || null,
    });
  }

  // --- Pin click ---

  function handlePinClick(pinId: number | string): void {
    const pin = explorationPins.value.find((p) => p.id === pinId);
    if (!pin || pin.visibility === "hide" || pin.visibility === "disable") {
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
    if (!showZones.value) {
      return null;
    }

    const actionType = zone.actionType || "none";
    const isWalkableOnly =
      zone.isWalkable && !zone.targetType && ["none", "walkable"].includes(actionType);

    if (isWalkableOnly) {
      return { fill: "#4ade80", opacity: 0.2 };
    }
    return { fill: zone.fillColor || "#3b82f6", opacity: zone.opacity ?? 0.3 };
  }

  // --- Clickability check (for cursor/listening) ---

  const clickableZoneIds = computed<Set<number | string>>(() => {
    const ids = new Set<number | string>();
    for (const zone of explorationZones.value) {
      if (zone.visibility === "hide" || zone.visibility === "disable") {
        continue;
      }
      const actionType = zone.actionType || "none";
      const isWalkableOnly =
        zone.isWalkable && !zone.targetType && ["none", "walkable"].includes(actionType);
      if (isWalkableOnly) {
        continue;
      }
      const isClickable =
        ["instruction", "collection", "display"].includes(actionType) || !!zone.targetType;
      if (isClickable) {
        ids.add(zone.id);
      }
    }
    return ids;
  });

  const clickablePinIds = computed<Set<number | string>>(() => {
    const ids = new Set<number | string>();
    for (const pin of explorationPins.value) {
      if (pin.visibility === "hide" || pin.visibility === "disable") {
        continue;
      }
      ids.add(pin.id);
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
