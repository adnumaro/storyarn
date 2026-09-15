import { afterEach, describe, expect, it, vi } from "vitest";
import { mount, type VueWrapper } from "@vue/test-utils";
import { defineComponent, nextTick } from "vue";
import RoundBar from "@modules/ideation/components/RoundBar.vue";
import type { Round } from "@modules/ideation/types";
import { createMockLive } from "../../setup";
import { board, round, timer } from "./fixtures";

const Passthrough = defineComponent({ name: "Passthrough", template: "<div><slot /></div>" });
let wrapper: VueWrapper;
let width = 1440;
// The header measures itself; jsdom has no ResizeObserver, so one reports the width under test.
class Observer {
  constructor(private readonly report: (entries: { contentRect: { width: number } }[]) => void) {}
  observe() {
    this.report([{ contentRect: { width } }]);
  }
  unobserve() {}
  disconnect() {}
}
async function header(at: number, overrides: Partial<Round> = {}, canManage = true) {
  width = at;
  vi.stubGlobal("ResizeObserver", Observer);
  wrapper = mount(RoundBar, {
    attachTo: document.body,
    props: {
      round: round({
        id: 20,
        number: 2,
        status: "active",
        prompt: "Which decision of Mara changes the ending?",
        private: true,
        ...overrides,
      }),
      canManage,
      count: 5,
      timer: {
        session: board().session!,
        epoch: "a",
        timer: timer({ status: "running", version: 1 }),
        canEdit: true,
      },
    },
    global: {
      provide: { _live_vue: createMockLive() },
      stubs: {
        DropdownMenu: Passthrough,
        DropdownMenuTrigger: Passthrough,
        DropdownMenuContent: Passthrough,
        DropdownMenuItem: Passthrough,
        DropdownMenuSeparator: true,
        DropdownMenuSub: Passthrough,
        DropdownMenuSubContent: Passthrough,
        DropdownMenuSubTrigger: Passthrough,
        DropdownMenuCheckboxItem: Passthrough,
        ToolbarTooltip: Passthrough,
      },
    },
  });
  await nextTick();
  return wrapper;
}
const button = (id: string) => wrapper.find(`button#${id}`);
afterEach(() => {
  wrapper?.unmount();
  vi.unstubAllGlobals();
});

describe("the round header by width", () => {
  it("shows every piece in full from 1280 px", async () => {
    await header(1440);
    expect(wrapper.attributes("data-tier")).toBe("xl");
    expect(wrapper.text()).toContain("In progress");
    expect(wrapper.get("#brainstorming-round-count-20").text()).toBe("5 notes");
    expect(wrapper.get("#brainstorming-round-private-20").text()).toBe("Private");
    expect(button("brainstorming-round-close-20").text()).toContain("Close round");
    expect(button("brainstorming-round-new-20").text()).toContain("New round");
    expect(button("brainstorming-round-reveal-20").text()).toContain("Reveal");
    expect(button("brainstorming-round-timer-cancel").exists()).toBe(true);
    expect(button("brainstorming-round-timer-pause").text()).toContain("Pause");
    expect(button("brainstorming-round-settings-20").exists()).toBe(true);
    expect(wrapper.find("#brainstorming-round-more-20").exists()).toBe(false);
  });

  it("drops the pause label between 1000 and 1279 px and nothing else", async () => {
    await header(1100);
    expect(wrapper.attributes("data-tier")).toBe("l");
    expect(button("brainstorming-round-timer-pause").text()).toBe("");
    expect(button("brainstorming-round-close-20").text()).toContain("Close round");
    expect(wrapper.text()).toContain("In progress");
    expect(wrapper.find("#brainstorming-round-more-20").exists()).toBe(false);
  });

  it("folds stop, settings and close into a menu below 1000 px and loses the status badge", async () => {
    await header(900);
    expect(wrapper.attributes("data-tier")).toBe("m");
    expect(wrapper.text()).not.toContain("In progress");
    expect(wrapper.get("#brainstorming-round-count-20").text()).toBe("5 notes");
    expect(wrapper.find("#brainstorming-round-more-20").exists()).toBe(true);
    for (const id of [
      "brainstorming-round-close-20",
      "brainstorming-round-timer-cancel",
      "brainstorming-round-settings-20",
    ]) {
      // Each control keeps its id and lives in one place only: the menu.
      expect(wrapper.findAll(`#${id}`)).toHaveLength(1);
      expect(button(id).exists()).toBe(false);
    }
    expect(button("brainstorming-round-new-20").text()).toContain("New round");
    expect(button("brainstorming-round-reveal-20").text()).toBe("");
    expect(button("brainstorming-round-timer-extend").text()).toBe("1 min");
  });

  it("keeps only icons and the digits between 640 and 799 px", async () => {
    await header(700);
    expect(wrapper.attributes("data-tier")).toBe("s");
    expect(wrapper.find("#brainstorming-round-count-20").exists()).toBe(false);
    expect(wrapper.get("#brainstorming-round-private-20").text()).toBe("");
    expect(button("brainstorming-round-new-20").text()).toBe("");
    expect(wrapper.get("#brainstorming-round-timer").text()).toBe("05:00");
  });

  it("gives the question the whole first row below 640 px", async () => {
    await header(500);
    expect(wrapper.attributes("data-tier")).toBe("xs");
    const question = wrapper.get("#brainstorming-round-prompt-20").element.closest(".basis-full");
    expect(question).not.toBeNull();
    expect(wrapper.find("span.order-2").text()).toBe("Round 2");
    expect(button("brainstorming-round-new-20").exists()).toBe(false);
    expect(wrapper.findAll("#brainstorming-round-new-20")).toHaveLength(1);
    expect(button("brainstorming-round-timer-extend").text()).toBe("1");
  });

  it("offers a participant nothing to fold and a closed last round only the next round", async () => {
    await header(500, {}, false);
    expect(wrapper.find("#brainstorming-round-more-20").exists()).toBe(false);
    wrapper.unmount();
    await header(500, { status: "closed", private: false });
    expect(wrapper.find("#brainstorming-round-more-20").exists()).toBe(false);
    wrapper.unmount();
    wrapper = await mount(RoundBar, {
      props: { round: round({ id: 20, number: 2, status: "closed" }), canManage: true, last: true },
      global: {
        stubs: {
          DropdownMenu: Passthrough,
          DropdownMenuTrigger: Passthrough,
          DropdownMenuContent: Passthrough,
          DropdownMenuItem: Passthrough,
        },
      },
    });
    await nextTick();
    expect(wrapper.find("#brainstorming-round-more-20").exists()).toBe(true);
    expect(wrapper.findAll("#brainstorming-round-new-20")).toHaveLength(1);
    expect(wrapper.find("#brainstorming-round-close-20").exists()).toBe(false);
  });
});
