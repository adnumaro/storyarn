import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vitest";
import SliderField from "../../../components/forms/fields/SliderField.vue";

describe("SliderField", () => {
  it("previews while dragging and commits once on release", async () => {
    const wrapper = mount(SliderField, {
      props: { label: "Speed", value: 1, min: 0, max: 3, step: 0.1 },
    });
    const range = wrapper.get<HTMLInputElement>('input[type="range"]');

    // Dragging fires `input` only; `setValue` would also fire `change`.
    for (const value of ["1.2", "1.5", "1.8"]) {
      range.element.value = value;
      await range.trigger("input");
    }

    expect(wrapper.emitted("update")).toBeUndefined();
    expect(wrapper.text()).toContain("1.8");

    await range.trigger("change");

    expect(wrapper.emitted("update")).toEqual([["1.8"]]);
  });

  it("keeps the released value until the new value arrives", async () => {
    const wrapper = mount(SliderField, {
      props: { label: "Speed", value: 1, min: 0, max: 3, step: 0.1 },
    });
    const range = wrapper.get<HTMLInputElement>('input[type="range"]');

    range.element.value = "2.4";
    await range.trigger("input");
    await range.trigger("change");

    // The server has not answered yet: neither the thumb nor the label jump back.
    expect(range.element.value).toBe("2.4");
    expect(wrapper.text()).toContain("2.4");

    await wrapper.setProps({ value: 2.5 });

    expect(range.element.value).toBe("2.5");
    expect(wrapper.text()).toContain("2.5");
  });
});
