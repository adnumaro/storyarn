import { mount } from "@vue/test-utils";
import { expect, it } from "vitest";
import AssetUploadDecisionDialog from "@shared/components/assets/AssetUploadDecisionDialog.vue";

it("explains original preservation and web conversion even without a resize target", () => {
  const wrapper = mount(AssetUploadDecisionDialog, {
    props: {
      state: {
        fileName: "background.png",
        fileSize: "8 MB",
        purpose: "scene_background",
        action: "upload_original_and_create_variant",
        sourceExists: false,
        variantExists: false,
        requiresVariant: true,
        target: null,
      },
    },
    global: {
      stubs: Object.fromEntries(
        [
          "Dialog",
          "DialogContent",
          "DialogHeader",
          "DialogTitle",
          "DialogDescription",
          "DialogFooter",
        ].map((name) => [name, { template: "<div><slot /></div>" }]),
      ),
    },
  });
  expect(wrapper.text()).toContain("keep the original image in Assets");
  expect(wrapper.text()).toContain("compressed WebP copy");
  expect(wrapper.text()).not.toContain("This image can be used as-is.");
  wrapper.unmount();
});
