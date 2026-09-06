import { flushPromises, mount } from "@vue/test-utils";
import { defineComponent, nextTick } from "vue";
import type {
  SequenceConfigPanelData,
  SequenceStageState,
  SequenceVisualLayer,
} from "@modules/flows/sequence/types";

const pushEvent = vi.fn();
vi.mock("@shared/composables/useLive", () => ({ useLive: () => ({ pushEvent }) }));
const { default: FlowSequenceWorkspace } =
  await import("@modules/flows/editor/components/sequence/FlowSequenceWorkspace.vue");

const Stage = defineComponent({
  props: ["selectedLayerKey", "lockedLayerKeys", "canEdit"],
  emits: ["update:selectedLayerKey", "add-image"],
  template: "<div data-stage />",
});
const Inspector = defineComponent({
  props: ["layer", "canEdit", "locked"],
  emits: ["update", "remove", "revert"],
  template: "<div data-inspector />",
});
const Library = defineComponent({
  props: ["selectedAssetId", "canReplace", "canEdit"],
  emits: ["add-image", "replace-image"],
  template: "<div data-library />",
});
const background: SequenceVisualLayer = {
  id: "background",
  key: "background",
  rowId: 1,
  sequenceId: 10,
  stackIndex: 0,
  kind: "backdrop",
  label: "Room",
  asset_id: 100,
  url: "/room.png",
  origin: { nodeId: 10, inherited: true },
};
const character: SequenceVisualLayer = {
  id: "character",
  key: "character",
  rowId: 2,
  sequenceId: 20,
  stackIndex: 1,
  kind: "character",
  label: "Ghost",
  asset_id: 101,
  url: "/ghost.png",
  x: 0.4,
  y: 1,
  width: 0.3,
  height: 0.85,
};

function props() {
  const stage: SequenceStageState = {
    status: "ready",
    owner: { nodeId: 20, type: "dialogue" },
    composition: { layers: [background, character] },
  };
  const data: SequenceConfigPanelData = {
    owner_id: 20,
    owner_type: "dialogue",
    composition_source_id: 10,
    composition_sources: [{ id: 10, label: "Previous", type: "dialogue" }],
    visual_layers: [background, character],
  };
  return { stage, data, canEdit: true };
}

function workspace(overrides: Partial<ReturnType<typeof props>> = {}) {
  return mount(FlowSequenceWorkspace, {
    props: { ...props(), ...overrides },
    global: {
      stubs: {
        FlowSequenceStage: Stage,
        FlowSequenceInspector: Inspector,
        FlowSequenceLibrary: Library,
        ImageAsset: true,
      },
    },
  });
}

class TestImage {
  static images: TestImage[] = [];
  onload: (() => void) | null = null;
  onerror: (() => void) | null = null;
  naturalWidth = 400;
  naturalHeight = 800;
  src = "";
  constructor() {
    TestImage.images.push(this);
  }
}

describe("FlowSequenceWorkspace", () => {
  beforeEach(() => {
    pushEvent.mockReset();
    TestImage.images = [];
    vi.stubGlobal("Image", TestImage);
  });
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("shares selection and editor locks between the stage, stack and inspector", async () => {
    const wrapper = workspace();
    wrapper.getComponent(Stage).vm.$emit("update:selectedLayerKey", "character");
    await nextTick();
    expect(wrapper.getComponent(Inspector).props("layer").key).toBe("character");
    expect(wrapper.getComponent(Library).props("selectedAssetId")).toBe(101);
    expect(wrapper.get('[data-select-layer="character"]').attributes("aria-pressed")).toBe("true");
    await wrapper.get('[data-select-layer="background"]').trigger("click");
    expect(wrapper.getComponent(Stage).props("selectedLayerKey")).toBe("background");
    await wrapper
      .get('[data-layer-row="background"] button[aria-label="Lock or unlock position"]')
      .trigger("click");
    expect(wrapper.getComponent(Stage).props("lockedLayerKeys")).toEqual(["background"]);
    expect(wrapper.getComponent(Inspector).props("locked")).toBe(true);
    expect(pushEvent).not.toHaveBeenCalled();
    await wrapper.setProps({
      stage: {
        ...props().stage,
        composition: {
          layers: [background, character],
          diagnostics: [{ code: "missing_asset" }],
        },
      },
    });
    expect(wrapper.find("[data-sequence-diagnostics]").exists()).toBe(true);
    wrapper.unmount();
  });

  it("replaces an inherited image locally without changing its geometry or source", async () => {
    const wrapper = workspace();
    await wrapper.get('[data-select-layer="background"]').trigger("click");
    wrapper.getComponent(Library).vm.$emit("replace-image", {
      asset_id: 900,
      url: "/night.png",
      label: "Night",
      source: "asset",
    });
    expect(pushEvent).toHaveBeenCalledWith("override_sequence_visual_layer", {
      id: 20,
      layer_key: "background",
      asset_id: 900,
      label: "Night",
    });
    wrapper.unmount();
  });

  it("uses the local row for edits and discards an old inspector's asynchronous upload", async () => {
    const wrapper = workspace();
    await wrapper.get('[data-select-layer="character"]').trigger("click");
    const oldInspector = wrapper.getComponent(Inspector);
    oldInspector.vm.$emit("update", { opacity: 0.5 });
    expect(pushEvent).toHaveBeenCalledWith("update_sequence_visual_layer", {
      id: 20,
      layer_id: 2,
      opacity: 0.5,
    });
    pushEvent.mockClear();
    await wrapper.get('[data-select-layer="background"]').trigger("click");
    oldInspector.vm.$emit("update", { asset_id: 999 });
    expect(pushEvent).not.toHaveBeenCalled();
    wrapper.unmount();
  });

  it("sends a complete back-to-front stack when moving an inherited layer forward", async () => {
    const wrapper = workspace();
    await wrapper.get('[data-select-layer="background"]').trigger("click");
    await wrapper.get("[data-layer-forward]").trigger("click");
    expect(pushEvent).toHaveBeenCalledWith("reorder_sequence_visual_layers", {
      id: 20,
      layer_keys: ["character", "background"],
    });
    wrapper.unmount();
  });

  it("creates the dropped image with its original aspect and stage coordinates", async () => {
    const wrapper = workspace();
    wrapper.getComponent(Stage).vm.$emit("add-image", {
      image: {
        asset_id: 900,
        url: "/ghost.png",
        label: "Ghost · Happy",
        source: "gallery",
        sheet_id: 40,
      },
      x: -0.15,
      y: 1.1,
    });
    TestImage.images[0]!.onload!();
    await flushPromises();
    expect(pushEvent).toHaveBeenCalledWith(
      "create_sequence_visual_layer",
      expect.objectContaining({
        id: 20,
        asset_id: 900,
        x: -0.15,
        y: 1.1,
        width: (0.85 * 0.5 * 9) / 16,
        height: 0.85,
      }),
      expect.any(Function),
      expect.any(Function),
    );
    wrapper.unmount();
  });

  it("does not create an image if Stop closes the workspace while its size is loading", async () => {
    const wrapper = workspace();
    wrapper
      .getComponent(Library)
      .vm.$emit("add-image", { asset_id: 900, url: "/ghost.png", label: "Ghost", source: "asset" });
    wrapper.unmount();
    TestImage.images[0]!.onload!();
    await flushPromises();
    expect(pushEvent).not.toHaveBeenCalled();
  });

  it("rejects edits from readonly or stale-owner surfaces", async () => {
    const wrapper = workspace({ canEdit: false });
    await wrapper.get('[data-select-layer="character"]').trigger("click");
    wrapper.getComponent(Inspector).vm.$emit("update", { x: 5 });
    expect(pushEvent).not.toHaveBeenCalled();
    await wrapper.setProps({
      canEdit: true,
      stage: {
        status: "ready",
        owner: { nodeId: 30, type: "dialogue" },
        composition: { layers: [] },
      },
    });
    expect(wrapper.getComponent(Stage).props("canEdit")).toBe(false);
    expect(wrapper.getComponent(Inspector).props("layer")).toBeNull();
    wrapper.unmount();
  });
});
