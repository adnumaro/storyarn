import { afterEach, describe, expect, it, vi } from "vitest";
import { mount, type VueWrapper } from "@vue/test-utils";
import CanvasDecisionLane from "@modules/ideation/components/CanvasDecisionLane.vue";
import CanvasDecisionHover from "@modules/ideation/components/CanvasDecisionHover.vue";
import { layoutLane } from "@modules/ideation/lib/decisionLanes";
import type { DecisionSource } from "@app/live/ideation/decisionTypes";
import { accepted, decision, revision, source } from "../../live/ideation/decisionFixtures";

let wrapper: VueWrapper | undefined;
afterEach(() => {
  wrapper?.unmount();
  wrapper = undefined;
  vi.useRealTimers();
});

function lane(focusId: number | null = null) {
  const first = decision({
    id: 1,
    proposal: revision({ sources: [source({ id: 10 }), source({ id: 11, available: false })] }),
  });
  const second = accepted({ id: 2, proposal: revision({ sources: [source({ id: 12 })] }) });
  const layout = layoutLane(20, [first, second], { top: 0, bottom: 200, left: 0, cardHeight: 150 });
  const anchor = (item: DecisionSource) =>
    item.id === 10 || item.id === 12 ? { x: item.id * 10, y: 40, width: 100, height: 60 } : null;
  wrapper = mount(CanvasDecisionLane, {
    props: {
      lanes: [layout],
      focusId,
      comments: { "2": 3 },
      roundNumbers: new Map([[20, 1]]),
      roundCount: 2,
      anchor,
    },
  });
  return wrapper;
}

describe("the decision lane", () => {
  it("draws a card per decision with connectors to the sources the reader can see", () => {
    const view = lane();
    expect(view.findAll("[id^=decision-lane-card-]")).toHaveLength(2);
    expect(view.findAll("[data-decision-link]")).toHaveLength(2);
    expect(view.get("[data-decision-lane]").text()).toContain("Decisions · Round 1 · 2");
    // The lane renders several roots: find the card first, then look inside it.
    const card = (id: number) => view.findAll(`#decision-lane-card-${id}`)[0];
    expect(card(2).get("[data-decision-comments]").text()).toBe("3");
    expect(card(1).find("[data-decision-comments]").exists()).toBe(false);
    expect(view.findAll("[data-decision-source-outline]")).toHaveLength(0);
  });

  it("outlines the focused decision's sources and opens it on double click or Enter", async () => {
    const view = lane(1);
    const outlines = view.findAll("[data-decision-source-outline]");
    expect(outlines).toHaveLength(1);
    expect(outlines[0].attributes("style")).toContain("translate(96px, 36px)");
    const [card] = view.findAll("#decision-lane-card-1");
    expect(card.attributes("aria-pressed")).toBe("true");
    await view.findAll("#decision-lane-card-2")[0].trigger("click");
    await card.trigger("dblclick");
    await card.trigger("keydown", { key: "Enter" });
    expect(view.emitted("focus")).toEqual([[2]]);
    expect(view.emitted("open")).toEqual([[1], [1]]);
  });
});

describe("the hover card", () => {
  const passthrough = { template: "<div><slot /></div>" };
  function hover(target: { id: number; element: HTMLElement } | null) {
    wrapper = mount(CanvasDecisionHover, {
      props: { target, decisions: [decision({ id: 7 }), accepted({ id: 8 })], roundCount: 1 },
      global: { stubs: { Popover: passthrough, PopoverContent: passthrough } },
    });
    return wrapper;
  }

  it("waits for the pointer to rest on the note, then opens the decision it names", async () => {
    vi.useFakeTimers();
    const view = hover(null);
    await view.setProps({ target: { id: 10, element: document.createElement("div") } });
    expect(view.find("[data-decision-hover-card]").exists()).toBe(false);
    vi.advanceTimersByTime(400);
    await view.vm.$nextTick();
    expect(view.findAll("[data-decision-hover-card]")).toHaveLength(2);
    expect(view.text()).toContain("Supports 2 decisions");
    await view.get("[data-decision-hover-card='8']").trigger("click");
    expect(view.emitted("open")).toEqual([[8]]);
    expect(view.find("[data-decision-hover-card]").exists()).toBe(false);
  });

  it("closes shortly after the pointer leaves the note", async () => {
    vi.useFakeTimers();
    const view = hover(null);
    await view.setProps({ target: { id: 10, element: document.createElement("div") } });
    vi.advanceTimersByTime(400);
    await view.vm.$nextTick();
    await view.setProps({ target: null });
    vi.advanceTimersByTime(200);
    await view.vm.$nextTick();
    expect(view.find("[data-decision-hover-card]").exists()).toBe(false);
  });
});
