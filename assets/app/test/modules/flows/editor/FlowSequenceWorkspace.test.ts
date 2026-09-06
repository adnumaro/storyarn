import { flushPromises, mount } from "@vue/test-utils";
import { defineComponent, nextTick } from "vue";
import { Select } from "@components/ui/select";
import type {
  SequenceConfigPanelData,
  SequenceStageState,
  SequenceVisualLayer,
} from "@modules/flows/sequence/types";

const pushEvent = vi.fn();
const uploadFile = vi.fn();
vi.mock("@shared/composables/useLive", () => ({ useLive: () => ({ pushEvent }) }));
vi.mock("@shared/composables/useUpload", () => ({ useUpload: () => ({ uploadFile }) }));
const { default: FlowSequenceWorkspace } =
  await import("@modules/flows/editor/components/sequence/FlowSequenceWorkspace.vue");

const Stage = defineComponent({
  props: ["selectedLayerKey", "lockedLayerKeys", "canEdit"],
  emits: ["update:selectedLayerKey", "add-image"],
  template: "<div data-stage data-sequence-canvas><div data-sequence-frame /></div>",
});
const Inspector = defineComponent({
  props: ["layer", "canEdit", "locked"],
  emits: ["update", "remove", "revert"],
  template: "<div data-inspector />",
});
const Library = defineComponent({
  props: ["selectedAssetId", "canReplace", "canEdit", "uploadedAssets"],
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

function workspace(overrides: Partial<InstanceType<typeof FlowSequenceWorkspace>["$props"]> = {}) {
  return mount(FlowSequenceWorkspace, {
    props: { ...props(), ...overrides },
    global: {
      stubs: {
        FlowSequenceStage: Stage,
        FlowSequenceInspector: Inspector,
        FlowSequenceLibrary: Library,
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
    uploadFile.mockReset();
    TestImage.images = [];
    vi.stubGlobal("Image", TestImage);
  });
  afterEach(() => {
    vi.restoreAllMocks();
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
      .get('[data-layer-row="background"] button[aria-label="Lock or unlock position: Room"]')
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

  it("allows repairing the source of an invalid composition while stage edits remain disabled", async () => {
    const invalidStage: SequenceStageState = {
      ...props().stage,
      status: "error",
      composition: { layers: [], diagnostics: [{ code: "composition_cycle", severity: "error" }] },
    };
    const wrapper = workspace({ stage: invalidStage });
    const source = () => wrapper.findAllComponents(Select)[0]!;
    expect(source().props("disabled")).toBe(false);
    expect(wrapper.getComponent(Stage).props("canEdit")).toBe(false);
    source().vm.$emit("update:modelValue", "__initial__");
    expect(pushEvent).toHaveBeenCalledExactlyOnceWith("set_composition_source", {
      id: 20,
      source_id: null,
    });

    pushEvent.mockClear();
    await wrapper.setProps({ canEdit: false });
    expect(source().props("disabled")).toBe(true);
    source().vm.$emit("update:modelValue", "10");
    expect(pushEvent).not.toHaveBeenCalled();

    await wrapper.setProps({ canEdit: true, data: { ...props().data, owner_id: 30 } });
    expect(wrapper.find("[data-workspace-source]").exists()).toBe(false);
    wrapper.unmount();
  });

  it("plays the selected dialogue inline and restores the editor after stopping", async () => {
    const wrapper = workspace();
    await wrapper.get("[data-sequence-playback-toggle]").trigger("click");
    expect(pushEvent).toHaveBeenCalledWith(
      "sequence_playback",
      expect.objectContaining({ action: "start", id: 20 }),
      expect.any(Function),
      expect.any(Function),
    );
    pushEvent.mock.calls[0]![2]();
    await wrapper.setProps({
      playback: {
        slide: { type: "dialogue", text: "Playing" },
        visualLayers: [],
        audioTracks: [],
        voice: null,
        canGoBack: false,
        showContinue: true,
        isFinished: false,
        error: null,
      },
    });
    expect(wrapper.find("[data-sequence-playback]").exists()).toBe(true);
    expect(wrapper.getComponent(Stage).isVisible()).toBe(false);
    expect(wrapper.getComponent(Stage).props("canEdit")).toBe(false);
    await wrapper.get("[data-playback-continue]").trigger("click");
    expect(pushEvent.mock.calls[1]![1]).toMatchObject({ action: "continue" });
    pushEvent.mock.calls[1]![2]();
    await nextTick();
    await wrapper.get("[data-sequence-playback-toggle]").trigger("click");
    expect(pushEvent.mock.calls[2]![1]).toMatchObject({ action: "stop" });
    pushEvent.mock.calls[2]![2]();
    await wrapper.setProps({ playback: null });
    expect(wrapper.find("[data-sequence-playback]").exists()).toBe(false);
    expect(wrapper.getComponent(Stage).isVisible()).toBe(true);
    expect(wrapper.getComponent(Stage).props("canEdit")).toBe(true);
    wrapper.unmount();
  });

  it("resizes both side panels through their accessible separators", async () => {
    vi.spyOn(HTMLElement.prototype, "getBoundingClientRect").mockReturnValue({
      width: 1400,
    } as DOMRect);
    const wrapper = workspace();
    await nextTick();
    expect(wrapper.findAll('[role="separator"]')).toHaveLength(2);
    const library = wrapper.get('[data-sequence-resize="library"]');
    await library.trigger("keydown", { key: "ArrowRight", shiftKey: true });
    await library.trigger("keyup", { key: "ArrowRight" });
    expect(library.attributes("aria-valuenow")).toBe("280");
    expect(wrapper.element.style.getPropertyValue("--library-width")).toBe("280px");
    const inspector = wrapper.get('[data-sequence-resize="inspector"]');
    await inspector.trigger("keydown", { key: "ArrowLeft" });
    expect(inspector.attributes("aria-valuenow")).toBe("298");
    expect(wrapper.element.style.getPropertyValue("--inspector-width")).toBe("298px");
    wrapper.unmount();
  });

  it("uploads selected images into Assets without adding layers", async () => {
    uploadFile.mockResolvedValueOnce({ id: 900, url: "/uploaded.png" });
    const wrapper = workspace();
    const file = new File(["image"], "portrait.png", { type: "image/png" });
    const input = wrapper.get<HTMLInputElement>("[data-sequence-upload-input]");
    Object.defineProperty(input.element, "files", { value: [file] });
    await input.trigger("change");
    await flushPromises();
    expect(uploadFile).toHaveBeenCalledWith(file, "image");
    expect(wrapper.getComponent(Library).props("uploadedAssets")).toEqual([
      { id: 900, url: "/uploaded.png", filename: "portrait.png" },
    ]);
    expect(pushEvent).not.toHaveBeenCalled();
    expect(wrapper.get("[data-sequence-upload]").attributes("disabled")).toBeUndefined();
    wrapper.unmount();
  });

  it("imports native stage drops sequentially and places saved assets at the drop position", async () => {
    uploadFile.mockResolvedValueOnce({ id: 900, url: "/one.png" });
    uploadFile.mockResolvedValueOnce({ id: 901, url: "/two.png" });
    const wrapper = workspace();
    vi.spyOn(wrapper.get("[data-sequence-frame]").element, "getBoundingClientRect").mockReturnValue(
      { left: 100, top: 50, width: 800, height: 450 } as DOMRect,
    );
    const files = ["one.png", "two.png"].map(
      (name) => new File([name], name, { type: "image/png" }),
    );
    await wrapper.get("[data-stage]").trigger("drop", {
      dataTransfer: { types: ["Files"], files },
      clientX: 300,
      clientY: 275,
    });
    await flushPromises();
    expect(uploadFile).toHaveBeenCalledTimes(1);
    TestImage.images[0]!.onload!();
    await flushPromises();
    expect(pushEvent).toHaveBeenCalledWith(
      "create_sequence_visual_layer",
      expect.objectContaining({
        id: 20,
        asset_id: 900,
        label: "one.png",
        x: 0.25,
        y: 0.5,
      }),
      expect.any(Function),
      expect.any(Function),
    );
    // The next image waits for the first layer to be acknowledged.
    expect(uploadFile).toHaveBeenCalledTimes(1);
    pushEvent.mock.calls[0]![2]();
    await flushPromises();
    expect(uploadFile).toHaveBeenCalledTimes(2);
    TestImage.images[1]!.onload!();
    await flushPromises();
    expect(pushEvent.mock.calls[1]![1]).toMatchObject({ id: 20, asset_id: 901, x: 0.25, y: 0.5 });
    pushEvent.mock.calls[1]![2]();
    await flushPromises();
    expect(wrapper.getComponent(Library).props("uploadedAssets")).toHaveLength(2);
    wrapper.unmount();
  });

  it("keeps an uploaded image in Assets without attaching it after changing dialogue and returning", async () => {
    let finish!: (asset: { id: number; url: string }) => void;
    uploadFile.mockImplementation(
      () =>
        new Promise((resolve) => {
          finish = resolve;
        }),
    );
    const wrapper = workspace();
    vi.spyOn(wrapper.get("[data-sequence-frame]").element, "getBoundingClientRect").mockReturnValue(
      { left: 0, top: 0, width: 800, height: 450 } as DOMRect,
    );
    await wrapper.get("[data-stage]").trigger("drop", {
      dataTransfer: {
        types: ["Files"],
        files: [new File(["image"], "portrait.png", { type: "image/png" })],
      },
      clientX: 400,
      clientY: 225,
    });
    await wrapper.setProps({
      stage: { ...props().stage, owner: { nodeId: 30, type: "dialogue" } },
    });
    await wrapper.setProps({ stage: props().stage });
    finish({ id: 900, url: "/portrait.png" });
    await flushPromises();
    expect(wrapper.getComponent(Library).props("uploadedAssets")).toHaveLength(1);
    expect(TestImage.images).toHaveLength(0);
    expect(pushEvent).not.toHaveBeenCalled();
    wrapper.unmount();
  });

  it("keeps a completed stage upload visible after edit permission changes without creating a layer", async () => {
    let finish!: (asset: { id: number; url: string }) => void;
    uploadFile.mockImplementation(
      () =>
        new Promise((resolve) => {
          finish = resolve;
        }),
    );
    const wrapper = workspace();
    vi.spyOn(wrapper.get("[data-sequence-frame]").element, "getBoundingClientRect").mockReturnValue(
      { left: 0, top: 0, width: 800, height: 450 } as DOMRect,
    );
    await wrapper.get("[data-stage]").trigger("drop", {
      dataTransfer: {
        types: ["Files"],
        files: [new File(["image"], "portrait.png", { type: "image/png" })],
      },
      clientX: 400,
      clientY: 225,
    });
    await wrapper.setProps({ canEdit: false });
    finish({ id: 900, url: "/portrait.png" });
    await flushPromises();
    expect(wrapper.getComponent(Library).props("uploadedAssets")).toEqual([
      { id: 900, url: "/portrait.png", filename: "portrait.png" },
    ]);
    expect(TestImage.images).toHaveLength(0);
    expect(pushEvent).not.toHaveBeenCalled();
    wrapper.unmount();
  });

  it("prevents read-only native drops and leaves internal library drags untouched", async () => {
    const wrapper = workspace({ canEdit: false });
    expect(wrapper.get("[data-sequence-upload]").attributes("disabled")).toBeDefined();
    await wrapper.get("[data-library]").trigger("drop", {
      dataTransfer: {
        types: ["Files"],
        files: [new File(["image"], "portrait.png", { type: "image/png" })],
      },
    });
    expect(uploadFile).not.toHaveBeenCalled();
    const event = new Event("drop", { bubbles: true, cancelable: true });
    Object.defineProperty(event, "dataTransfer", {
      value: { types: ["application/x-storyarn-sequence-image"], files: [] },
    });
    wrapper.get("[data-stage]").element.dispatchEvent(event);
    expect(event.defaultPrevented).toBe(false);
    wrapper.unmount();
  });
});
