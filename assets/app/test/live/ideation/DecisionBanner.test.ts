import { afterEach, describe, expect, it, vi } from "vitest";
import { mount, type VueWrapper } from "@vue/test-utils";
import Banner from "@app/live/ideation/DecisionBanner.vue";
import type { DecisionBannerState } from "@app/live/ideation/decisionTypes";
import { accepted } from "./decisionFixtures";

const passthrough = { template: "<div><slot /></div>" };
let wrapper: VueWrapper;
afterEach(() => {
  wrapper?.unmount();
  vi.useRealTimers();
});

function banner(overrides: Partial<DecisionBannerState> = {}) {
  wrapper = mount(Banner, {
    props: {
      banner: {
        decision: accepted({ id: 5 }),
        targetKey: "target-mara",
        sessionTitle: "Endings",
        sessionUrl: "/brainstorming/3?decision=5",
        marked: null,
        error: null,
        ...overrides,
      },
    },
    global: {
      stubs: { Popover: passthrough, PopoverTrigger: passthrough, PopoverContent: passthrough },
    },
  });
  return wrapper;
}

describe("the apply banner", () => {
  it("names the decision, what it does here and where it was decided", () => {
    const view = banner();
    expect(view.text()).toContain("Take the forest path");
    expect(view.text()).toContain("Change");
    expect(view.text()).toContain("Mara");
    expect(view.text()).toContain("Endings");
  });

  it("marks with an optional note as a statement for this content", async () => {
    const view = banner();
    await view.findAll("textarea")[1].setValue("Rewrote her motivation");
    await view.findAll("#decision-banner-mark-confirm")[1].trigger("click");
    expect(view.emitted("declare")).toEqual([["partially_applied", "Rewrote her motivation"]]);
  });

  it("offers Undo for a few seconds, then leaves", async () => {
    vi.useFakeTimers();
    const view = banner({ marked: { state: "applied" } });
    expect(view.text()).toContain("Marked applied");
    await view.get("#decision-banner-undo").trigger("click");
    expect(view.emitted("undo")).toHaveLength(1);
    vi.advanceTimersByTime(5000);
    expect(view.emitted("dismiss")).toHaveLength(1);
  });

  it("offers no marking without the right to declare", () => {
    const view = banner({ decision: accepted({ id: 5, canDeclare: false }) });
    expect(view.find("#decision-banner-applied").exists()).toBe(false);
  });
});
