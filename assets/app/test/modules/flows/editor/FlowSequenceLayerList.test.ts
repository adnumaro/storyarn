import { mount } from "@vue/test-utils";
import FlowSequenceLayerList from "@modules/flows/editor/components/sequence/FlowSequenceLayerList.vue";
import { setTestLocale } from "../../../setup";

describe("FlowSequenceLayerList", () => {
  it("identifies the layer in each visibility and lock control and preserves their states", async () => {
    setTestLocale("en");
    const wrapper = mount(FlowSequenceLayerList, {
      props: {
        layers: [
          { id: "hero", kind: "character", label: "Aria", visible: true },
          { id: "foreground", key: "mist", kind: "overlay", label: " ", visible: false },
        ],
        selectedKey: null,
        lockedKeys: ["hero"],
        canEdit: true,
      },
    });

    const hideHero = wrapper.get('button[aria-label="Hide layer: Aria"]');
    const showMist = wrapper.get('button[aria-label="Show layer: mist"]');
    const lockHero = wrapper.get('button[aria-label="Lock or unlock position: Aria"]');
    const lockMist = wrapper.get('button[aria-label="Lock or unlock position: mist"]');
    expect(hideHero.attributes("aria-pressed")).toBe("true");
    expect(showMist.attributes("aria-pressed")).toBe("false");
    expect(lockHero.attributes("aria-pressed")).toBe("true");
    expect(lockMist.attributes("aria-pressed")).toBe("false");
    await lockMist.trigger("click");
    expect(wrapper.emitted("lock")).toEqual([["mist"]]);
    wrapper.unmount();
  });
});
