import { afterEach, describe, expect, it } from "vitest";
import { mount, type VueWrapper } from "@vue/test-utils";
import RoundContext from "@modules/ideation/components/RoundContext.vue";
import { round } from "./fixtures";

let wrapper: VueWrapper;
afterEach(() => wrapper?.unmount());

describe("current round context", () => {
  it("shows the question without opening round controls and exposes its full text", () => {
    const prompt = `A longer question with several possible approaches.\n${"More context. ".repeat(40)}`;
    wrapper = mount(RoundContext, {
      props: { round: round({ prompt }) },
      global: {
        stubs: {
          Popover: { template: "<div><slot /></div>" },
          PopoverTrigger: { template: "<div><slot /></div>" },
          PopoverContent: { template: "<div data-full-context><slot /></div>" },
        },
      },
    });
    const trigger = wrapper.get("#brainstorming-round-context-trigger");
    expect(wrapper.get("#brainstorming-round-context").text()).toContain("Round 1");
    expect(trigger.get("span").element.textContent).toBe(prompt);
    expect(trigger.attributes("aria-label")).toBe(`Current round question: ${prompt}`);
    expect(wrapper.get("[data-full-context] p").element.textContent?.trim()).toBe(prompt.trim());
  });
});
