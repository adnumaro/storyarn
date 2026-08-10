import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vitest";
import AssetsDashboard from "../../../../live/assets/dashboard/AssetsDashboard.vue";
import { createMockLive } from "../../../setup";

const asset = {
  id: 17,
  filename: "portrait.png",
  url: "/media/assets/17",
  contentType: "image/png",
  size: 2048,
  insertedAt: "2026-08-10T10:00:00Z",
};

function mountDashboard(canEdit = true, props: Record<string, unknown> = {}) {
  const live = createMockLive();
  const wrapper = mount(AssetsDashboard, {
    props: {
      assets: [asset],
      selectedAsset: asset,
      canEdit,
      workspaceSlug: "writers-room",
      projectSlug: "veilbreak",
      ...props,
    },
    global: {
      provide: { _live_vue: live },
      stubs: { Teleport: true },
    },
  });

  return { live, wrapper };
}

describe("AssetsDashboard recoverable trash", () => {
  it("explains recoverability and confirms the move-to-trash event", async () => {
    const { live, wrapper } = mountDashboard();
    const moveButton = wrapper
      .findAll("button")
      .find((button) => button.text() === "Move to trash");

    expect(moveButton).toBeDefined();
    await moveButton!.trigger("click");

    expect(wrapper.text()).toContain("Move asset to trash?");
    expect(wrapper.text()).toContain("recoverable");

    const confirmButton = wrapper
      .findAll("button")
      .filter((button) => button.text() === "Move to trash")
      .at(-1);

    expect(confirmButton).toBeDefined();
    await confirmButton!.trigger("click");

    expect(live.pushEvent).toHaveBeenCalledWith("confirm_trash_asset", {}, undefined);
  });

  it("does not expose the move-to-trash action to read-only members", () => {
    const { wrapper } = mountDashboard(false);

    expect(wrapper.findAll("button").some((button) => button.text() === "Move to trash")).toBe(
      false,
    );
  });

  it("blocks moving an asset while active content still references it", async () => {
    const { live, wrapper } = mountDashboard(true, {
      assetUsages: {
        assetMetadataLinks: [],
        flowNodes: [
          { nodeId: 1, nodeType: "dialogue", flowId: 2, flowName: "Intro", trashed: false },
        ],
        sequenceVisualLayers: [],
        sequenceTracks: [],
        sheetAvatars: [],
        sheetBanners: [],
        sceneBackgrounds: [],
        scenePinIcons: [],
        sceneZoneIcons: [],
        localizedVoiceovers: [],
        galleryImages: [],
      },
    });

    expect(wrapper.text()).toContain("Remove this asset from its 1 active use");
    const moveButton = wrapper
      .findAll("button")
      .find((button) => button.text() === "Move to trash");
    expect(moveButton?.attributes("disabled")).toBeDefined();

    await moveButton!.trigger("click");
    expect(live.pushEvent).not.toHaveBeenCalledWith("confirm_trash_asset", {}, undefined);
  });
});
