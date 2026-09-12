import { afterEach, describe, expect, it } from "vitest";
import { mount, type VueWrapper } from "@vue/test-utils";
import Picker from "@app/live/ideation/DecisionSourcePicker.vue";
import { source } from "./decisionFixtures";

let wrapper: VueWrapper;
function picker() {
  wrapper = mount(Picker, {
    props: { sources: [], results: [source()], nextCursor: 10, searched: true, pending: false },
  });
}
function acknowledge() {
  const calls = wrapper.emitted("search")!;
  (calls[calls.length - 1][3] as () => void)();
  return wrapper.vm.$nextTick();
}
afterEach(() => wrapper?.unmount());
describe("decision source browsing", () => {
  it("navigates forward and back with the same query, committing the cursor only after a successful response", async () => {
    picker();
    await wrapper.get("#decision-source-query").setValue("road");
    await wrapper.get("form").trigger("submit");
    expect(wrapper.emitted("search")![0].slice(0, 3)).toEqual(["idea", "road", null]);
    await acknowledge();
    await wrapper.get("#decision-source-next").trigger("click");
    expect(wrapper.find("#decision-source-previous").exists()).toBe(false);
    expect(wrapper.emitted("search")![1].slice(0, 3)).toEqual(["idea", "road", 10]);
    await wrapper.setProps({
      nextCursor: 5,
      results: [source({ id: 6, identity: "next-source" })],
    });
    await acknowledge();
    expect(wrapper.find("#decision-source-option-idea-10").exists()).toBe(false);
    await wrapper.get("#decision-source-previous").trigger("click");
    expect(wrapper.emitted("search")![2].slice(0, 3)).toEqual(["idea", "road", null]);
    await acknowledge();
    expect(wrapper.find("#decision-source-previous").exists()).toBe(false);
    expect(wrapper.get<HTMLInputElement>("#decision-source-query").element.value).toBe("road");
  });
  it("resets page history after a new query and ignores the old query acknowledgement", async () => {
    picker();
    await wrapper.get("form").trigger("submit");
    const oldReply = wrapper.emitted("search")![0][3] as () => void;
    await wrapper.get("#decision-source-query").setValue("forest");
    oldReply();
    await wrapper.vm.$nextTick();
    expect(wrapper.find("#decision-source-next").exists()).toBe(false);
    await wrapper.get("form").trigger("submit");
    expect(wrapper.emitted("search")![1].slice(0, 3)).toEqual(["idea", "forest", null]);
    await acknowledge();
    expect(wrapper.find("#decision-source-next").exists()).toBe(true);
  });
  it("disables selected identities and hides unavailable metadata", async () => {
    picker();
    await wrapper.setProps({
      sources: [source()],
      results: [
        source(),
        source({ id: null, identity: "gone-a", available: false, title: "Secret A" }),
        source({ id: null, identity: "gone-b", available: false, title: "Secret B" }),
      ],
    });
    expect(wrapper.get("#decision-source-option-idea-10").attributes("disabled")).toBeDefined();
    expect(wrapper.get("#decision-source-option-idea-gone-a").attributes("disabled")).toBeDefined();
    expect(wrapper.get("#decision-source-option-idea-gone-b").attributes("disabled")).toBeDefined();
    expect(wrapper.text()).not.toContain("Secret");
  });
});
