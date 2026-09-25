import { afterEach, describe, expect, it } from "vitest";
import { mount, type VueWrapper } from "@vue/test-utils";
import Card from "@app/live/ideation/DecisionDashboardCard.vue";
import type { DashboardDecision } from "@app/live/ideation/decisionDashboard";
import { accepted, revision, target } from "./decisionFixtures";

let wrapper: VueWrapper;
afterEach(() => wrapper?.unmount());
const passthrough = { template: "<div><slot /></div>" };

const mara = target({ href: "/sheets/7" });
const act = target({ key: "act", type: "flow", id: 9, name: "Act 3", href: "/flows/9" });
const applied = {
  state: "applied" as const,
  note: null,
  actorName: "Noor",
  at: "2026-09-13T12:00:00Z",
};

function item(overrides: Partial<DashboardDecision["decision"]> = {}): DashboardDecision {
  const agreement = revision({ revision: 2, operation: "accept", targets: [mara, act] });
  return {
    decision: accepted({
      id: 4,
      accepted: agreement,
      proposal: agreement,
      application: {
        targets: [{ ...mara, application: applied }, act],
        decision: null,
        pending: 1,
        total: 2,
      },
      ...overrides,
    }),
    sessionId: 3,
    sessionTitle: "Endings",
    roundCount: 2,
  };
}

function card(entry: DashboardDecision, groupKey: string | null = null) {
  wrapper = mount(Card, {
    props: { item: entry, href: "/brainstorming/3?decision=4", groupKey, declared: 0 },
    global: {
      stubs: { Popover: passthrough, PopoverTrigger: passthrough, PopoverContent: passthrough },
    },
  });
}

describe("a dashboard decision card", () => {
  it("carries its session and round inside and applies the first content still pending", async () => {
    card(item());
    expect(wrapper.get("[data-decision-session]").text()).toBe("Endings");
    expect(wrapper.text()).toContain("R1");
    const apply = wrapper.get("#dashboard-decision-4-act-apply");
    expect(apply.attributes("href")).toBe("/flows/9?decision=4&session=3");
    expect(wrapper.text()).toContain("Mark Act 3 as applied");

    await wrapper.get("#dashboard-decision-4-act-mark-note").setValue("Done in the flow");
    await wrapper.get("#dashboard-decision-4-act-mark-confirm").trigger("click");
    expect(wrapper.emitted("declare")?.[0]?.slice(1)).toEqual([
      "act",
      "applied",
      "Done in the flow",
    ]);
  });

  it("keeps the mark form and its note open until the declaration is confirmed", async () => {
    const Popover = {
      props: ["open"],
      emits: ["update:open"],
      // Only its trigger opens it; the form's own buttons must not.
      template: `<div data-popover :data-open="String(open)" @click="$event.target.closest('#dashboard-decision-4-act-mark') && $emit('update:open', true)"><slot /></div>`,
    };
    wrapper = mount(Card, {
      props: { item: item(), href: "/brainstorming/3?decision=4", declared: 0 },
      global: { stubs: { Popover, PopoverTrigger: passthrough, PopoverContent: passthrough } },
    });
    const popover = () => wrapper.get("[data-popover]").attributes("data-open");
    await wrapper.get("#dashboard-decision-4-act-mark").trigger("click");
    expect(popover()).toBe("true");
    await wrapper.get("#dashboard-decision-4-act-mark-note").setValue("Done in the flow");
    await wrapper.get("#dashboard-decision-4-act-mark-confirm").trigger("click");
    expect(wrapper.emitted("declare")).toHaveLength(1);
    // Until the save is confirmed the form stays, so a failure keeps the note.
    expect(popover()).toBe("true");
    await wrapper.setProps({ declared: 1 });
    expect(popover()).toBe("false");
  });

  it("applies the content of its group when grouped", () => {
    const pendingBoth = item();
    pendingBoth.decision.application!.targets = [mara, act];
    card(pendingBoth, "flow:9");
    expect(wrapper.get("#dashboard-decision-4-act-apply").attributes("href")).toContain("/flows/9");
    card(pendingBoth, "sheet:7");
    // The same decision grouped under another content has its own controls.
    expect(wrapper.get("#dashboard-decision-4-target-mara-apply").attributes("href")).toContain(
      "/sheets/7",
    );
  });

  it("offers nothing to apply to a reader who cannot declare, or once it is retired", () => {
    card(item({ canDeclare: false }));
    expect(wrapper.find("[id$=-apply]").exists()).toBe(false);
    card(item({ status: "superseded" }));
    expect(wrapper.find("[id$=-mark]").exists()).toBe(false);
  });
});
