import { afterEach, describe, expect, it } from "vitest";
import { mount, type VueWrapper } from "@vue/test-utils";
import DecisionApplication from "@app/live/ideation/DecisionApplication.vue";
import DecisionsAbout from "@app/live/ideation/DecisionsAbout.vue";
import { accepted, target } from "./decisionFixtures";

let wrapper: VueWrapper;
afterEach(() => wrapper?.unmount());
const passthrough = { template: "<div><slot /></div>" };

// Only the named trigger opens the popover; the form's own buttons must not.
function popover(trigger: string) {
  return {
    props: ["open"],
    emits: ["update:open"],
    template: `<div data-popover :data-open="String(open)" @click="$event.target.closest('${trigger}') && $emit('update:open', true)"><slot /></div>`,
  };
}
function stubs(trigger: string) {
  return {
    Popover: popover(trigger),
    PopoverTrigger: passthrough,
    PopoverContent: passthrough,
    LiveLink: passthrough,
  };
}
async function markAndConfirm(prefix: string) {
  await wrapper.get(`#${prefix}`).trigger("click");
  expect(wrapper.get("[data-popover]").attributes("data-open")).toBe("true");
  await wrapper.get(`#${prefix}-note`).setValue("Done in the flow");
  await wrapper.get(`#${prefix}-confirm`).trigger("click");
  expect(wrapper.emitted("declare")).toHaveLength(1);
  // Until the save is confirmed the form stays, so a failure keeps the note.
  expect(wrapper.get("[data-popover]").attributes("data-open")).toBe("true");
  await wrapper.setProps({ declared: 1 });
  expect(wrapper.get("[data-popover]").attributes("data-open")).toBe("false");
}

describe("marking a decision applied", () => {
  it("keeps the panel's form open until the declaration is confirmed", async () => {
    const mara = target({ href: "/sheets/7" });
    wrapper = mount(DecisionApplication, {
      props: {
        decision: accepted({
          application: { targets: [mara], decision: null, pending: 1, total: 1 },
        }),
        declared: 0,
      },
      global: { stubs: stubs("#decision-mark-target-mara") },
    });
    await markAndConfirm("decision-mark-target-mara");
  });

  it("keeps the Explorations form open until the declaration is confirmed", async () => {
    const item = {
      decision: accepted({ id: 5, sessionId: 3 }),
      targetKey: "target-mara",
      sessionId: 3,
      sessionTitle: "Endings",
      sessionUrl: "/brainstorming/3?decision=5",
      roundCount: 2,
      toApply: true,
    };
    wrapper = mount(DecisionsAbout, {
      props: { items: [item], name: "Mara", canEdit: true, declared: 0 },
      global: { stubs: stubs("#exploration-decision-mark-5") },
    });
    await markAndConfirm("exploration-decision-mark-5");
  });

  it("always shows when a content was marked, however long the name of who marked it", () => {
    const marked = target({
      application: {
        state: "applied",
        note: null,
        actorName: "Maximiliana de la Vega y Santisteban del Castillo",
        at: "2026-09-25T12:00:00Z",
      },
    });
    wrapper = mount(DecisionApplication, {
      props: {
        decision: accepted({
          application: { targets: [marked], decision: null, pending: 0, total: 1 },
        }),
      },
      global: { stubs: stubs("#none") },
    });
    expect(wrapper.get("[data-application-actor]").classes()).toContain("truncate");
    const date = wrapper.get("[data-application-date]");
    expect(date.classes()).toContain("shrink-0");
    expect(date.text()).toMatch(/Sep 25/);
  });
});
