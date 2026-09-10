import { afterEach, describe, expect, it } from "vitest";
import { mount, flushPromises, type VueWrapper } from "@vue/test-utils";
import CanvasConnectionTools from "@modules/ideation/components/CanvasConnectionTools.vue";

const mounted: VueWrapper[] = [];
function tools(props = {}) {
  const wrapper = mount(CanvasConnectionTools, {
    attachTo: document.body,
    props: {
      selection: [
        { id: 10, label: "The first thought" },
        { id: 11, label: "A consequence" },
      ],
      hasConnections: true,
      canCreate: true,
      busy: false,
      ...props,
    },
  });
  mounted.push(wrapper);
  return wrapper;
}
function button(id: string) {
  const element = document.getElementById(id);
  if (!(element instanceof HTMLButtonElement)) throw new Error(`Missing action: ${id}`);
  return element;
}
afterEach(() => {
  for (const wrapper of mounted.splice(0)) wrapper.unmount();
});

describe("contextual connection actions", () => {
  it("changes origin inside the same open menu and shows the choice before connecting", async () => {
    const wrapper = tools();
    await wrapper.get("#brainstorming-connection-tools").trigger("click");
    await flushPromises();
    expect(button("connection-origin-10").getAttribute("aria-pressed")).toBe("true");
    button("connection-origin-11").click();
    await flushPromises();
    expect(wrapper.emitted("origin")).toEqual([[11]]);
    await wrapper.setProps({
      selection: [
        { id: 11, label: "A consequence" },
        { id: 10, label: "The first thought" },
      ],
    });
    expect(button("connection-origin-11").getAttribute("aria-pressed")).toBe("true");
    button("connect-selected-ideas").click();
    await flushPromises();
    expect(wrapper.emitted("connect")).toEqual([[]]);
    expect(document.getElementById("connect-selected-ideas")).toBeNull();
  });

  it("offers all four destinations and does not offer disconnect when nothing is linked", async () => {
    const wrapper = tools({ hasConnections: false });
    await wrapper.get("#brainstorming-connection-tools").trigger("click");
    await flushPromises();
    expect(button("disconnect-selected-ideas").disabled).toBe(true);
    for (const direction of ["up", "right", "down", "left"])
      expect(button(`add-connected-idea-${direction}`).disabled).toBe(false);
    button("add-connected-idea-down").click();
    await flushPromises();
    expect(wrapper.emitted("create")).toEqual([["down"]]);
  });

  it("closes a pending menu and keeps creation out of a session with closed contributions", async () => {
    const wrapper = tools({ canCreate: false });
    await wrapper.get("#brainstorming-connection-tools").trigger("click");
    await flushPromises();
    expect(document.getElementById("add-connected-idea-down")).toBeNull();
    expect(button("connect-selected-ideas")).toBeTruthy();
    await wrapper.setProps({ busy: true });
    await flushPromises();
    expect(document.getElementById("connect-selected-ideas")).toBeNull();
    expect(wrapper.get("#brainstorming-connection-tools").attributes("disabled")).toBeDefined();
  });
});
