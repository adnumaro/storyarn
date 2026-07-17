import { beforeEach, describe, expect, it, vi } from "vitest";
import { mount } from "@vue/test-utils";
import { createMockLive } from "../../../../setup";

const mockLive = createMockLive();

vi.mock("@shared/composables/useLive", () => ({
  useLive: () => mockLive,
}));

const { default: HubToolbar } =
  await import("../../../../../modules/flows/editor/components/entities/toolbar/sections/HubToolbar.vue");

function mountIt(color = "#3b82f6") {
  return mount(HubToolbar, {
    props: {
      nodeData: { hub_id: "checkpoint", label: "Checkpoint", color },
      nodeId: 42,
      referencingJumps: [],
    },
    global: {
      stubs: {
        ToolbarColorPicker: true,
        ToolbarTooltip: { template: "<div><slot /></div>" },
        ToolbarSeparator: { template: "<span data-stub-separator />" },
      },
    },
  });
}

describe("HubToolbar", () => {
  beforeEach(() => {
    vi.mocked(mockLive.pushEvent).mockClear();
  });

  it("shows the Hub's stored color in the shared toolbar picker", () => {
    const wrapper = mountIt("#06b6d4");
    const picker = wrapper.findComponent({ name: "ToolbarColorPicker" });

    expect(picker.exists()).toBe(true);
    expect(picker.props("color")).toBe("#06b6d4");
  });

  it("uses the Hub default when no color is stored", () => {
    const wrapper = mountIt("");
    const picker = wrapper.findComponent({ name: "ToolbarColorPicker" });

    expect(picker.props("color")).toBe("#be185d");
  });

  it("pushes color changes through the Hub color event", () => {
    const wrapper = mountIt();
    const picker = wrapper.findComponent({ name: "ToolbarColorPicker" });

    picker.vm.$emit("update:color", "#22c55e");

    expect(mockLive.pushEvent).toHaveBeenCalledWith("update_hub_color", {
      color: "#22c55e",
    });
  });
});
