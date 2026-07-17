import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vitest";
import FlowHeader from "../../../../live/flow/show/FlowHeader.vue";
import { createMockLive } from "../../../setup";

const passthrough = { template: "<div><slot /></div>" };

interface TestHealthNode {
  id: number | string | null;
  label: string;
  reason?: string;
  reasons?: string[];
}

interface TestFlowHealth {
  wordCount: number;
  errorNodes: TestHealthNode[];
  warningNodes: TestHealthNode[];
  infoNodes: TestHealthNode[];
}

function mountHeader(flowHealth: TestFlowHealth) {
  const live = createMockLive();
  const wrapper = mount(FlowHeader, {
    props: {
      flowName: "Opening",
      flowShortcut: "opening",
      isMain: true,
      canEdit: false,
      saveStatus: "idle",
      navHistory: { back: null, forward: null },
      flowHealth,
      sceneSelected: { name: null, inherited: false },
      projectScenes: [],
    },
    global: {
      provide: {
        _live_vue: live,
      },
      stubs: {
        Badge: passthrough,
        EditableText: passthrough,
        Popover: {
          props: ["open"],
          emits: ["update:open"],
          template: "<div><slot /></div>",
        },
        PopoverAnchor: passthrough,
        PopoverContent: passthrough,
        PopoverTrigger: {
          template: '<button type="button"><slot /></button>',
        },
        ToolbarTooltip: passthrough,
      },
    },
  });

  return { live, wrapper };
}

describe("FlowHeader flow health", () => {
  it("counts findings from every reason and always labels each visible severity", () => {
    const { wrapper } = mountHeader({
      wordCount: 0,
      errorNodes: [
        {
          id: 11,
          label: "Dialogue #11",
          reasons: ["Broken reference", "Missing dialogue text"],
        },
      ],
      warningNodes: [
        {
          id: 12,
          label: "Subflow #12",
          reason: "No outgoing connection",
        },
      ],
      infoNodes: [
        {
          id: 13,
          label: "Dialogue #13",
          reasons: ["Optional metadata", "Draft content"],
        },
      ],
    });

    expect(wrapper.get('[data-testid="flow-health-error-count"]').text()).toBe("2");
    expect(wrapper.get('[data-testid="flow-health-warning-count"]').text()).toBe("1");
    expect(wrapper.get('[data-testid="flow-health-info-count"]').text()).toBe("2");
    expect(wrapper.get('[data-testid="flow-health-errors"]').text()).toBe("Errors");
    expect(wrapper.get('[data-testid="flow-health-warnings"]').text()).toBe("Warnings");
    expect(wrapper.get('[data-testid="flow-health-info"]').text()).toBe("Info");
  });

  it("navigates to node findings but disables flow-level findings", async () => {
    const { live, wrapper } = mountHeader({
      wordCount: 0,
      errorNodes: [
        {
          id: null,
          label: "Opening",
          reasons: ["Flow has no entry node"],
        },
      ],
      warningNodes: [
        {
          id: 42,
          label: "Subflow #42",
          reasons: ["No outgoing connection"],
        },
      ],
      infoNodes: [],
    });

    const flowFinding = wrapper.get('[data-health-severity="error"]');
    expect(flowFinding.attributes()).toHaveProperty("disabled");
    await flowFinding.trigger("click");
    expect(live.pushEvent).not.toHaveBeenCalled();

    await wrapper.get('[data-health-node-id="42"]').trigger("click");
    expect(live.pushEvent).toHaveBeenCalledWith("navigate_to_node", { id: 42 }, undefined);
  });
});
