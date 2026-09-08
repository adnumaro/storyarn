import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { mount, type VueWrapper } from "@vue/test-utils";
import { defineComponent, h, ref } from "vue";
import { useCanvasViewport } from "@modules/ideation/composables/useCanvasViewport";

let wrapper: VueWrapper;
let viewport: ReturnType<typeof useCanvasViewport>;
function space(target: EventTarget, type = "keydown", options: KeyboardEventInit = {}) {
  const event = new KeyboardEvent(type, {
    code: "Space",
    key: " ",
    bubbles: true,
    cancelable: true,
    ...options,
  });
  target.dispatchEvent(event);
  return event;
}
beforeEach(() => {
  vi.stubGlobal(
    "ResizeObserver",
    class {
      observe() {}
      disconnect() {}
    },
  );
  wrapper = mount(
    defineComponent({
      setup() {
        const root = ref<HTMLElement | null>(null);
        viewport = useCanvasViewport(root);
        return () => h("div", { ref: root, tabindex: 0 });
      },
    }),
    { attachTo: document.body },
  );
});
afterEach(() => {
  wrapper.unmount();
  vi.unstubAllGlobals();
});

describe("canvas Space panning", () => {
  it("only captures Space within the canvas, and releases it outside or on blur", () => {
    expect(space(document.body).defaultPrevented).toBe(false);
    expect(viewport.space.value).toBe(false);
    expect(space(wrapper.element).defaultPrevented).toBe(true);
    expect(viewport.space.value).toBe(true);
    space(document.body, "keyup");
    expect(viewport.space.value).toBe(false);
    space(wrapper.element);
    window.dispatchEvent(new Event("blur"));
    expect(viewport.space.value).toBe(false);
  });

  it.each([
    "<button><span>Save</span></button>",
    '<a href="#help"><span>Help</span></a>',
    '<input type="checkbox">',
    "<textarea></textarea>",
    "<select><option>One</option></select>",
    "<summary>Details</summary>",
    '<div contenteditable="true"><span>Text</span></div>',
    '<div role="button"><span>Open</span></div>',
    "<div data-canvas-chrome><span>Toolbar</span></div>",
  ])("leaves focused controls to handle Space: %s", (html) => {
    wrapper.element.innerHTML = html;
    const target = wrapper.element.querySelector("span") ?? wrapper.element.firstElementChild!;
    expect(space(target).defaultPrevented).toBe(false);
    expect(viewport.space.value).toBe(false);
  });

  it("does not intercept modified or already handled shortcuts", () => {
    expect(space(wrapper.element, "keydown", { ctrlKey: true }).defaultPrevented).toBe(false);
    expect(space(wrapper.element, "keydown", { metaKey: true }).defaultPrevented).toBe(false);
    const event = new KeyboardEvent("keydown", { code: "Space", cancelable: true, bubbles: true });
    event.preventDefault();
    wrapper.element.dispatchEvent(event);
    expect(viewport.space.value).toBe(false);
  });
});
