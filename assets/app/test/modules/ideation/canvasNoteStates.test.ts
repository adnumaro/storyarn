import { afterEach, describe, expect, it } from "vitest";
import { mount, type VueWrapper } from "@vue/test-utils";
import { nextTick } from "vue";
import CanvasNote from "@modules/ideation/components/CanvasNote.vue";
import { idea } from "./fixtures";
import type { Idea } from "@modules/ideation/types";

const mounted: VueWrapper[] = [];
async function note(overrides: Partial<Idea>, editing = false) {
  const wrapper = mount(CanvasNote, {
    props: {
      note: idea(overrides),
      body: "<p>Start</p>",
      editing,
      selected: false,
      author: "Alex",
    },
    attachTo: document.body,
  });
  mounted.push(wrapper);
  await nextTick();
  return wrapper;
}
afterEach(() => {
  for (const wrapper of mounted.splice(0)) wrapper.unmount();
});

describe("note states on the card", () => {
  it("keeps an active note plain", async () => {
    const wrapper = await note({ state: "active" });
    expect(wrapper.attributes("data-note-state")).toBe("active");
    expect(wrapper.find(".note-tab").exists()).toBe(false);
    expect(wrapper.find(".note-dash").exists()).toBe(false);
    expect(wrapper.classes()).not.toContain("canvas-note--discarded");
  });

  it("gives a note kept for later a tab over its edge and a dashed outline that follows its shape", async () => {
    const wrapper = await note({ state: "parked" });
    expect(wrapper.attributes("data-note-state")).toBe("parked");
    expect(wrapper.get(".note-tab").text()).toBe("For later");
    expect(wrapper.find(".note-dash rect").exists()).toBe(true);
    await wrapper.setProps({ note: idea({ state: "parked", canvas: { shape: "ellipse" } }) });
    expect(wrapper.find(".note-dash ellipse").exists()).toBe(true);
    await wrapper.setProps({ note: idea({ state: "parked", canvas: { shape: "diamond" } }) });
    expect(wrapper.find(".note-dash polygon").exists()).toBe(true);
  });

  it("fades a discarded note behind the others, under its own tab, until it is being edited", async () => {
    const wrapper = await note({ state: "discarded" });
    expect(wrapper.classes()).toContain("canvas-note--discarded");
    expect(wrapper.get(".note-tab").text()).toBe("Discarded");
    expect(wrapper.find(".note-dash rect").exists()).toBe(true);
    await wrapper.setProps({ editing: true });
    expect(wrapper.classes()).toContain("canvas-note--discarded");
    expect(wrapper.classes()).toContain("canvas-note--editing");
  });
});
