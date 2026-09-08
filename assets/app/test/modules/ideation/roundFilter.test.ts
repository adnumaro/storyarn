import { afterEach, describe, expect, it } from "vitest";
import { mount, type VueWrapper } from "@vue/test-utils";
import RoundFilter from "@modules/ideation/components/RoundFilter.vue";
import { round } from "./fixtures";

let wrapper: VueWrapper;
afterEach(() => wrapper?.unmount());

describe("round filter choices", () => {
  it("keeps a cancelled selected round labelled until the participant chooses another view", async () => {
    wrapper = mount(RoundFilter, {
      props: { rounds: [round({ status: "planned" })], value: 20 },
      global: {
        stubs: {
          Select: { template: "<div><slot /></div>" },
          SelectTrigger: { template: "<div><slot /></div>" },
          SelectValue: true,
          SelectContent: { template: "<div><slot /></div>" },
          SelectItem: {
            props: ["value"],
            template: '<div :data-round-option="value"><slot /></div>',
          },
        },
      },
    });
    await wrapper.setProps({
      rounds: [round({ status: "cancelled" }), round({ id: 21, number: 2, status: "cancelled" })],
    });
    expect(wrapper.get('[data-round-option="20"]').text()).toBe("Round 1 · Cancelled");
    expect(wrapper.find('[data-round-option="21"]').exists()).toBe(false);
    await wrapper.setProps({ value: "all" });
    expect(wrapper.find('[data-round-option="20"]').exists()).toBe(false);
    expect(wrapper.get('[data-round-option="all"]').text()).toBe("All rounds");
  });
});
