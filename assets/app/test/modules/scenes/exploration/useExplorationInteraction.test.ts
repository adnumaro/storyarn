import { ref } from "vue";
import { describe, expect, it, vi } from "vitest";
import { useExplorationInteraction } from "../../../../modules/scenes/exploration/composables/useExplorationInteraction";

function setupPins(
  pins: Array<{ id: string; visibility: string; flowId: number | string | null }>,
) {
  const pushEvent = vi.fn();
  const explorationZones = ref([]);
  const explorationPins = ref(pins);
  const showZones = ref(false);

  const interaction = useExplorationInteraction({
    pushEvent,
    explorationZones,
    explorationPins,
    showZones,
  });

  return { pushEvent, ...interaction };
}

describe("useExplorationInteraction", () => {
  it("only treats visible pins with a flow as clickable", () => {
    const { clickablePinIds, handlePinClick, pushEvent } = setupPins([
      { id: "with-flow", visibility: "visible", flowId: 7 },
      { id: "without-flow", visibility: "visible", flowId: null },
      { id: "empty-flow", visibility: "visible", flowId: "" },
      { id: "disabled", visibility: "disable", flowId: 8 },
      { id: "hidden", visibility: "hide", flowId: 9 },
    ]);

    expect([...clickablePinIds.value]).toEqual(["with-flow"]);

    handlePinClick("without-flow");
    handlePinClick("empty-flow");
    handlePinClick("disabled");
    handlePinClick("hidden");
    expect(pushEvent).not.toHaveBeenCalled();

    handlePinClick("with-flow");
    expect(pushEvent).toHaveBeenCalledWith("exploration_element_click", {
      element_type: "pin",
      element_id: "with-flow",
      flow_id: 7,
    });
  });
});
