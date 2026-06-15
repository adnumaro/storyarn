import { describe, expect, it } from "vitest";
import { mount } from "@vue/test-utils";
import ImageFit from "../../../components/forms/assets/ImageFit.vue";

function mountIt(props: Record<string, unknown> = {}) {
  return mount(ImageFit, { props });
}

describe("ImageFit", () => {
  it("emits fit-change with the selected fit", () => {
    const w = mountIt({ fit: "cover", canEdit: true });
    const group = w.findComponent({ name: "ToggleGroup" });

    group.vm.$emit("update:modelValue", "contain");

    expect(w.emitted("fit-change")![0]).toEqual(["contain"]);
  });

  it("ignores empty deselection from ToggleGroup type=single", () => {
    const w = mountIt({ fit: "cover", canEdit: true });
    const group = w.findComponent({ name: "ToggleGroup" });

    group.vm.$emit("update:modelValue", "");

    expect(w.emitted("fit-change")).toBeUndefined();
  });

  it("renders one tab per fit option and honors disabled state", () => {
    const w = mountIt({ fit: "cover", canEdit: false });
    const values = w.findAllComponents({ name: "ToggleGroupItem" }).map((i) => i.props("value"));

    expect(values).toEqual(expect.arrayContaining(["cover", "contain", "fill"]));
    expect(w.findComponent({ name: "ToggleGroup" }).props("disabled")).toBe(true);
  });

  it("keeps a stable visual width independent of parent layout", () => {
    const w = mountIt({ fit: "cover", canEdit: true });

    expect(w.classes()).toEqual(expect.arrayContaining(["w-60", "max-w-full", "flex-none"]));
  });
});
