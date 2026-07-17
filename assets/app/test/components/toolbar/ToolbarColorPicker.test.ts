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
  it("identifies every swatch and exposes the selected color", () => {
    const wrapper = mountPicker();
    const swatches = wrapper.findAll("button[aria-pressed]");
    const labels = swatches.map((swatch) => swatch.attributes("aria-label"));

    expect(swatches).toHaveLength(23);
    expect(new Set(labels)).toHaveLength(swatches.length);
    expect(wrapper.get('button[aria-label="Color #3b82f6"]').attributes("aria-pressed")).toBe(
      "true",
    );
    expect(wrapper.get('button[aria-label="Color #ef4444"]').attributes("aria-pressed")).toBe(
      "false",
    );
  });

  it("renders the custom color input and emits its selected color", async () => {
    const wrapper = mountPicker();
    const customInput = wrapper.get("input[type='color']");

    expect(customInput.attributes("aria-label")).toBe("Custom color");

    await customInput.setValue("#22c55e");

    expect(wrapper.findAll("input[type='color']")).toHaveLength(1);
    expect(wrapper.emitted("update:color")).toEqual([["#22c55e"]]);
  });
});
