import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vitest";
import SceneHealthStatus from "../../../../modules/scenes/editor/components/chrome/header/SceneHealthStatus.vue";
import type { SceneHealth } from "../../../../modules/scenes/types/health";
import { createMockLive } from "../../../setup";

const passthrough = { template: "<div><slot /></div>" };

function mountStatus(health: SceneHealth) {
  const live = createMockLive();
  const wrapper = mount(SceneHealthStatus, {
    props: { health },
    global: {
      provide: { _live_vue: live },
      stubs: {
        Popover: {
          props: ["open"],
          emits: ["update:open"],
          template: "<div><slot /></div>",
        },
        PopoverAnchor: passthrough,
        PopoverContent: passthrough,
        PopoverTrigger: { template: '<button type="button"><slot /></button>' },
        ToolbarTooltip: passthrough,
      },
    },
  });

  return { wrapper, live };
}

describe("SceneHealthStatus", () => {
  it("counts every reason and renders all severities", () => {
    const { wrapper } = mountStatus({
      errorItems: [
        {
          entityType: "zone",
          entityId: 11,
          label: "Gate",
          reasons: [{ code: "invalid_zone_geometry" }, { code: "stale_zone_target" }],
        },
      ],
      warningItems: [
        {
          entityType: "scene",
          entityId: null,
          label: "World",
          reasons: [{ code: "missing_background" }],
        },
      ],
      infoItems: [
        {
          entityType: "zone",
          entityId: 12,
          label: "Loot",
          reasons: [{ code: "empty_collection" }],
        },
      ],
    });

    expect(wrapper.get('[data-testid="scene-health-error-count"]').text()).toBe("2");
    expect(wrapper.get('[data-testid="scene-health-warning-count"]').text()).toBe("1");
    expect(wrapper.get('[data-testid="scene-health-info-count"]').text()).toBe("1");
    expect(wrapper.get('[data-testid="scene-health-error"]').text()).toContain("Errors");
    expect(wrapper.get('[data-testid="scene-health-warning"]').text()).toContain("Warnings");
    expect(wrapper.get('[data-testid="scene-health-info"]').text()).toContain("Info");
  });

  it("focuses canvas entities and disables scene-level findings", async () => {
    const { wrapper, live } = mountStatus({
      errorItems: [],
      warningItems: [
        {
          entityType: "scene",
          entityId: null,
          label: "World",
          reasons: [{ code: "missing_background" }],
        },
        {
          entityType: "pin",
          entityId: 42,
          label: "Hero",
          reasons: [{ code: "patrol_on_playable_pin" }],
        },
      ],
      infoItems: [],
    });

    expect(wrapper.get('[data-health-entity-type="scene"]').attributes()).toHaveProperty(
      "disabled",
    );

    await wrapper.get('[data-health-entity-id="42"]').trigger("click");

    expect(live.pushEvent).toHaveBeenCalledWith(
      "focus_search_result",
      {
        type: "pin",
        id: 42,
      },
      undefined,
    );
  });

  it("shows the clean state when there are no findings", () => {
    const { wrapper } = mountStatus({ errorItems: [], warningItems: [], infoItems: [] });
    expect(wrapper.find('[data-testid="scene-health-clean"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="scene-health-trigger"]').exists()).toBe(false);
  });
});
