import { describe, expect, it } from "vitest";
import { mount } from "@vue/test-utils";
import ToolbarColorPicker from "../../../components/toolbar/ToolbarColorPicker.vue";

function mountPicker() {
  return mount(ToolbarColorPicker, {
    props: {
      color: "#3b82f6",
    },
    global: {
      stubs: {
        Popover: { template: "<div><slot /></div>" },
        PopoverTrigger: { template: "<div><slot /></div>" },
        PopoverContent: { template: "<div><slot /></div>" },
        ToolbarTooltip: { template: "<div><slot /></div>" },
      },
    },
  });
}

describe("ToolbarColorPicker", () => {
  it("renders the custom color input and emits its selected color", async () => {
    const wrapper = mountPicker();
    const customInput = wrapper.get("input[type='color']");

    await customInput.setValue("#22c55e");

    expect(wrapper.findAll("input[type='color']")).toHaveLength(1);
    expect(wrapper.emitted("update:color")).toEqual([["#22c55e"]]);
  });
});
