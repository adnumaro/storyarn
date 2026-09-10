import { afterEach, describe, expect, it } from "vitest";
import { mount, flushPromises, type VueWrapper } from "@vue/test-utils";
import CanvasShapePicker from "@modules/ideation/components/CanvasShapePicker.vue";

let wrapper: VueWrapper;
afterEach(() => wrapper?.unmount());
function button(id: string) {
  const element = document.getElementById(id);
  if (!(element instanceof HTMLButtonElement)) throw new Error(`Missing shape button: ${id}`);
  return element;
}
describe("note shape picker", () => {
  it("shows the current shape and closes after choosing a labelled alternative", async () => {
    wrapper = mount(CanvasShapePicker, {
      attachTo: document.body,
      props: { value: "ellipse", count: 1, disabled: false },
    });
    await wrapper.get("#brainstorming-shape-picker").trigger("click");
    await flushPromises();
    expect(button("note-shape-ellipse").getAttribute("aria-pressed")).toBe("true");
    expect(button("note-shape-diamond").getAttribute("aria-label")).toBe("Diamond");
    button("note-shape-diamond").click();
    await flushPromises();
    expect(wrapper.emitted("change")).toEqual([["diamond"]]);
    expect(document.getElementById("note-shape-diamond")).toBeNull();
  });
  it("represents a mixed selection without claiming a common shape and closes when disabled", async () => {
    wrapper = mount(CanvasShapePicker, {
      attachTo: document.body,
      props: { value: null, count: 3, disabled: false },
    });
    await wrapper.get("#brainstorming-shape-picker").trigger("click");
    await flushPromises();
    expect(document.body.textContent).toContain("Shape for 3 notes");
    for (const shape of ["plain", "rectangle", "ellipse", "diamond"])
      expect(button(`note-shape-${shape}`).getAttribute("aria-pressed")).toBe("false");
    await wrapper.setProps({ disabled: true });
    await flushPromises();
    expect(document.getElementById("note-shape-diamond")).toBeNull();
    expect(button("brainstorming-shape-picker").disabled).toBe(true);
    expect(wrapper.emitted("change")).toBeUndefined();
  });
  it("lets a note return to plain text and restores editing focus through the close event", async () => {
    wrapper = mount(CanvasShapePicker, {
      attachTo: document.body,
      props: { value: "rectangle", count: 1, disabled: false },
    });
    await wrapper.get("#brainstorming-shape-picker").trigger("click");
    await flushPromises();
    expect(button("note-shape-plain").getAttribute("aria-pressed")).toBe("false");
    button("note-shape-plain").click();
    await flushPromises();
    expect(wrapper.emitted("change")).toEqual([["plain"]]);
    expect(wrapper.emitted("close")).toHaveLength(1);
  });
});
