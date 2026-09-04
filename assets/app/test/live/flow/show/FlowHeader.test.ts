import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vitest";
import FlowHeader from "@app/live/flow/show/FlowHeader.vue";
import type { FlowHealth } from "@modules/flows/types/health";
import { createMockLive } from "@app/test/setup";

// Health itself is covered in FlowHealthStatus.test.ts — the header stopped
// owning a popover when flows moved onto the shared component. What is left to
// prove here is that the header still renders the pieces it owns and hands the
// health payload down untouched.

const passthrough = { template: "<div><slot /></div>" };

const EMPTY_HEALTH: FlowHealth = { errorItems: [], warningItems: [], infoItems: [] };

function mountHeader(health: FlowHealth = EMPTY_HEALTH, wordCount = 330) {
  const live = createMockLive();

  const wrapper = mount(FlowHeader, {
    props: {
      flowName: "Opening",
      flowShortcut: "opening",
      isMain: true,
      canEdit: false,
      saveStatus: "idle",
      navHistory: { back: null, forward: null },
      flowHealth: { wordCount, health },
      sceneSelected: { name: null, inherited: false },
      projectScenes: [],
    },
    global: {
      provide: { _live_vue: live },
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
        PopoverTrigger: { template: '<button type="button"><slot /></button>' },
        ToolbarTooltip: passthrough,
      },
    },
  });

  return { live, wrapper };
}

describe("FlowHeader", () => {
  it("opens comments for a read-only viewer", async () => {
    const { live, wrapper } = mountHeader();
    await wrapper.get("#flow-comments-toggle").trigger("click");
    expect(live.pushEvent).toHaveBeenCalledWith("comments_open", {}, undefined);
    expect(wrapper.find("#flow-comments-create-mode").exists()).toBe(false);
  });

  it("toggles canvas comment placement separately from the comments list", async () => {
    const { live, wrapper } = mountHeader();
    await wrapper.setProps({
      comments: { count: 2, open: false, canComment: true, placing: false },
    });
    const toggle = wrapper.get("#flow-comments-create-mode");
    expect(toggle.attributes("aria-pressed")).toBe("false");
    await toggle.trigger("click");
    expect(live.pushEvent).toHaveBeenCalledWith("comments_mode", { active: true }, undefined);
    await wrapper.setProps({
      comments: { count: 2, open: false, canComment: true, placing: true },
    });
    expect(toggle.attributes("aria-pressed")).toBe("true");
    await toggle.trigger("click");
    expect(live.pushEvent).toHaveBeenCalledWith("comments_mode", { active: false }, undefined);
    await wrapper.get("#flow-comments-toggle").trigger("click");
    expect(live.pushEvent).toHaveBeenCalledWith("comments_open", {}, undefined);
  });

  it("renders the word count", () => {
    const { wrapper } = mountHeader();

    expect(wrapper.text()).toContain("330");
  });

  it("delegates health to the shared status component", () => {
    const health: FlowHealth = {
      errorItems: [],
      warningItems: [
        {
          entityType: "dialogue",
          entityId: 42,
          label: "Dialogue #42",
          reasons: [{ code: "missing_dialogue_speaker" }],
        },
      ],
      infoItems: [],
    };

    const { wrapper } = mountHeader(health);

    // The badge and its count come from the shared popover, so seeing them here
    // is proof the payload arrived intact.
    expect(wrapper.get('[data-testid="flow-health-warning-count"]').text()).toBe("1");
    expect(wrapper.find('[data-testid="flow-health-error-count"]').exists()).toBe(false);
  });
});
