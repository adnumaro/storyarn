import { afterEach, describe, expect, it, vi } from "vitest";
import { mount, type VueWrapper } from "@vue/test-utils";
import RoundStartedToast from "@modules/ideation/components/RoundStartedToast.vue";
import { round } from "./fixtures";

const mounted: VueWrapper[] = [];
afterEach(() => {
  for (const wrapper of mounted.splice(0)) wrapper.unmount();
  vi.useRealTimers();
});

describe("round started toast", () => {
  it("announces the round, jumps to it on request and dismisses itself", async () => {
    vi.useFakeTimers();
    const wrapper = mount(RoundStartedToast, { props: { round: null } });
    mounted.push(wrapper);
    expect(wrapper.find("#brainstorming-round-started").exists()).toBe(false);
    const started = round({ id: 21, number: 3 });
    await wrapper.setProps({ round: started });
    expect(wrapper.get("#brainstorming-round-started").text()).toContain("Round 3 started");
    await wrapper.get("#brainstorming-round-started button").trigger("click");
    expect(wrapper.emitted("go")).toEqual([[started]]);
    vi.advanceTimersByTime(8000);
    expect(wrapper.emitted("dismiss")).toHaveLength(1);
  });
});
