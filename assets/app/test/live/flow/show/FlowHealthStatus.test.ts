import { mount } from "@vue/test-utils";
import { afterEach, describe, expect, it, vi } from "vitest";
import FlowHealthStatus from "@modules/flows/editor/components/chrome/header/FlowHealthStatus.vue";
import type { FlowHealth } from "@modules/flows/types/health";
import { createMockLive } from "@app/test/setup";

// The sibling of SheetHealthStatus.test.ts and deliberately shaped like it: the
// flows header no longer owns a popover of its own, it delegates to the shared
// HealthStatusPopover exactly as sheets and scenes do.

const passthrough = { template: "<div><slot /></div>" };

function mountStatus(health: FlowHealth) {
  const live = createMockLive();

  const wrapper = mount(FlowHealthStatus, {
    props: { health },
    attachTo: document.body,
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

afterEach(() => {
  document.body.innerHTML = "";
  vi.restoreAllMocks();
});

describe("FlowHealthStatus", () => {
  it("counts every reason and labels each visible severity", () => {
    const { wrapper } = mountStatus({
      errorItems: [
        {
          entityType: "jump",
          entityId: 11,
          label: "Jump #11",
          // Both catalogs land in one popover now: a reference-integrity code and
          // an editorial one on the same badge.
          reasons: [{ code: "stale_jump_target" }, { code: "stale_variable_reference" }],
        },
      ],
      warningItems: [
        {
          entityType: "dialogue",
          entityId: 12,
          label: "Dialogue #12",
          reasons: [{ code: "missing_dialogue_speaker" }],
        },
      ],
      infoItems: [
        {
          entityType: "condition",
          entityId: 13,
          label: "Condition #13",
          reasons: [{ code: "empty_condition" }],
        },
      ],
    });

    expect(wrapper.get('[data-testid="flow-health-error-count"]').text()).toBe("2");
    expect(wrapper.get('[data-testid="flow-health-warning-count"]').text()).toBe("1");
    expect(wrapper.get('[data-testid="flow-health-info-count"]').text()).toBe("1");
    expect(wrapper.get('[data-testid="flow-health-errors"]').text()).toContain("Errors");
    expect(wrapper.get('[data-testid="flow-health-warnings"]').text()).toContain("Warnings");
    expect(wrapper.get('[data-testid="flow-health-info"]').text()).toContain("Info");
  });

  it("navigates to a node finding and disables flow-level ones", async () => {
    const { wrapper, live } = mountStatus({
      errorItems: [
        {
          entityType: "flow",
          entityId: null,
          label: "Opening",
          reasons: [{ code: "missing_entry" }],
        },
      ],
      warningItems: [
        {
          entityType: "dialogue",
          entityId: 42,
          label: "Dialogue #42",
          reasons: [{ code: "no_outgoing_connection" }],
        },
      ],
      infoItems: [],
    });

    // A flow-level finding has nowhere to jump to.
    expect(wrapper.get('[data-health-severity="error"]').attributes()).toHaveProperty("disabled");
    expect(live.pushEvent).not.toHaveBeenCalled();

    await wrapper.get('[data-health-entity-id="42"]').trigger("click");

    expect(live.pushEvent).toHaveBeenCalledWith("navigate_to_node", { id: 42 }, undefined);
  });

  it("shows the clean state when there are no findings", () => {
    const { wrapper } = mountStatus({ errorItems: [], warningItems: [], infoItems: [] });

    expect(wrapper.find('[data-testid="flow-health-clean"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="flow-health-trigger"]').exists()).toBe(false);
  });
});
