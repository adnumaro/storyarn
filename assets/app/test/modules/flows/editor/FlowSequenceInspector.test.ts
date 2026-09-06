import { mount } from "@vue/test-utils";
import FlowSequenceInspector from "@modules/flows/editor/components/sequence/FlowSequenceInspector.vue";

describe("FlowSequenceInspector", () => {
  it("updates the layer label together with a replacement image", () => {
    const wrapper = mount(FlowSequenceInspector, {
      props: {
        layer: { id: "hero", kind: "character", asset_id: 1, label: "Old portrait" },
        imageAssets: [{ id: 2, filename: "New portrait.png", url: "/new.png" }],
        canEdit: true,
      },
      global: { stubs: { ImageAsset: true } },
    });

    wrapper.findComponent({ name: "ImageAsset" }).vm.$emit("select", {
      id: 2,
      filename: "New portrait.png",
    });

    expect(wrapper.emitted("update")).toEqual([[{ asset_id: 2, label: "New portrait.png" }]]);
    wrapper.unmount();
  });
});
