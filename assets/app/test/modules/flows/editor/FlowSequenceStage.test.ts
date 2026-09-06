import { mount } from "@vue/test-utils";
import SequenceVisualLayers from "@modules/flows/sequence/components/SequenceVisualLayers.vue";
import type { SequenceStageState } from "@modules/flows/sequence/types";
import { SEQUENCE_LIBRARY_IMAGE_MIME } from "@modules/flows/editor/components/sequence/sequence-library";
import { createMockLive } from "../../../setup";

const mockLive = createMockLive();
vi.mock("@shared/composables/useLive", () => ({ useLive: () => mockLive }));
const { default: FlowSequenceStage } =
  await import("@modules/flows/editor/components/sequence/FlowSequenceStage.vue");
type ReadyStage = Extract<SequenceStageState, { status: "ready" }>;
function editableStage(): ReadyStage {
  return {
    status: "ready",
    owner: { nodeId: 42, type: "dialogue", compositionSourceId: 10 },
    intervention: { nodeId: 42, speakerName: "Aria", text: "Open the gate." },
    composition: {
      layers: [
        {
          id: "hero",
          key: "hero",
          sequenceId: 10,
          kind: "character",
          label: "Aria",
          url: "/aria.png",
          x: 0.2,
          y: 0.3,
          width: 0.4,
          height: 0.5,
        },
      ],
    },
  };
}
function mountStage(stage: SequenceStageState = editableStage(), extra = {}) {
  const wrapper = mount(FlowSequenceStage, { props: { stage, canEdit: true, ...extra } });
  vi.spyOn(wrapper.get(".flow-sequence-viewport").element, "getBoundingClientRect").mockReturnValue(
    {
      x: 100,
      y: 50,
      left: 100,
      top: 50,
      right: 1100,
      bottom: 550,
      width: 1000,
      height: 500,
      toJSON: () => ({}),
    },
  );
  return wrapper;
}
function pointer(target: EventTarget, type: string, clientX = 100, clientY = 100) {
  target.dispatchEvent(new MouseEvent(type, { bubbles: true, cancelable: true, clientX, clientY }));
}
function move(wrapper: ReturnType<typeof mountStage>) {
  pointer(wrapper.get('[data-layer-control="hero"]').element, "pointerdown");
  pointer(window, "pointermove", 200, 150);
}

describe("FlowSequenceStage", () => {
  beforeEach(() => vi.mocked(mockLive.pushEvent).mockClear());

  it("guides authors when empty and does not retain stale layers on error", async () => {
    const wrapper = mountStage({ status: "empty" });
    expect(wrapper.text()).toContain("Select a speaker intervention");
    expect(wrapper.findComponent(SequenceVisualLayers).exists()).toBe(false);
    await wrapper.setProps({ stage: { status: "error", errorMessage: "Unavailable backdrop" } });
    expect(wrapper.text()).toContain("Unavailable backdrop");
    expect(wrapper.findComponent(SequenceVisualLayers).exists()).toBe(false);
    wrapper.unmount();
  });

  it("renders effective layers and dialogue and opens its owner's inspector", async () => {
    const stage = editableStage();
    const wrapper = mountStage(stage);
    expect(wrapper.getComponent(SequenceVisualLayers).props("layers")).toEqual(
      stage.composition.layers,
    );
    expect(wrapper.get("[data-sequence-intervention]").text()).toContain("Open the gate.");
    expect(wrapper.get("[data-sequence-intervention]").classes()).toContain("pointer-events-none");
    await wrapper.get("[data-open-sequence-inspector]").trigger("click");
    expect(mockLive.pushEvent).toHaveBeenCalledWith("open_sequence_config", { id: 42 });
    await wrapper.setProps({ embedded: true });
    expect(wrapper.find("header").exists()).toBe(false);
    wrapper.unmount();
  });

  it("shares selection with the inspector and makes locked layers click through", async () => {
    const wrapper = mountStage(editableStage(), { selectedLayerKey: null });
    await wrapper.get('[data-layer-control="hero"]').trigger("click");
    expect(wrapper.emitted("update:selectedLayerKey")).toEqual([["hero"]]);
    expect(wrapper.find("[data-layer-resize-handle]").exists()).toBe(false);
    await wrapper.setProps({ selectedLayerKey: "hero" });
    expect(wrapper.findAll("[data-layer-resize-handle]")).toHaveLength(8);
    await wrapper.setProps({ lockedLayerKeys: ["hero"] });
    const control = wrapper.get('[data-layer-control="hero"]');
    expect(control.classes()).toContain("pointer-events-none");
    expect(wrapper.find("[data-layer-resize-handle]").exists()).toBe(false);
    pointer(control.element, "pointerdown");
    pointer(window, "pointerup", 200, 150);
    await control.trigger("keydown", { key: "ArrowRight" });
    expect(mockLive.pushEvent).not.toHaveBeenCalled();
    wrapper.unmount();
  });

  it("clips oversized images to the screen while keeping resize controls outside its clip", () => {
    const stage = editableStage();
    Object.assign(stage.composition.layers[0]!, {
      x: -0.5,
      y: -0.5,
      width: 2,
      height: 2,
      zIndex: 99999,
    });
    const wrapper = mountStage(stage, { selectedLayerKey: "hero" });
    const frame = wrapper.get("[data-sequence-frame]");
    const renderer = wrapper.getComponent(SequenceVisualLayers);
    const controls = wrapper.get("[data-sequence-layer-controls]");
    const outline = wrapper.get("[data-sequence-frame-outline]");
    expect(renderer.classes()).toContain("overflow-hidden");
    expect((renderer.element as HTMLElement).style.overflow).not.toBe("visible");
    expect(frame.classes()).not.toContain("overflow-hidden");
    expect(controls.element.parentElement).toBe(frame.element);
    expect(renderer.element.contains(controls.element)).toBe(false);
    expect(wrapper.get('[data-layer-control="hero"]').attributes("style")).toContain("left: -50%");
    expect(wrapper.get('[data-layer-control="hero"]').attributes("style")).toContain("width: 200%");
    expect(wrapper.findAll("[data-layer-resize-handle]")).toHaveLength(8);
    // Image z-indices stay inside the renderer's stacking context, below the frame outline.
    expect(renderer.classes()).toContain("z-0");
    expect(outline.classes()).toEqual(expect.arrayContaining(["z-30", "pointer-events-none"]));
    expect(outline.element.parentElement).toBe(frame.element);
    pointer(wrapper.get('[data-layer-resize-handle="e"]').element, "pointerdown");
    pointer(window, "pointerup", 200, 100);
    expect(mockLive.pushEvent).toHaveBeenCalledOnce();
    wrapper.unmount();
  });

  it("uses the same authoritative stack order as the renderer", () => {
    const stage = editableStage();
    stage.composition.layers = [
      {
        id: "front",
        key: "front",
        kind: "backdrop",
        url: "/front.png",
        stack_index: 1,
        sequence_depth: 0,
      },
      {
        id: "back",
        key: "back",
        kind: "character",
        url: "/back.png",
        stack_index: 0,
        sequence_depth: 5,
      },
    ];
    const wrapper = mountStage(stage);
    expect(
      wrapper.findAll(".sequence-visual-layer").map((node) => node.attributes("data-layer-id")),
    ).toEqual(["back", "front"]);
    expect(
      wrapper.findAll("[data-layer-control]").map((node) => node.attributes("data-layer-control")),
    ).toEqual(["back", "front"]);
    wrapper.unmount();
  });

  it("keeps a hidden layer selected for inspection and clears selection only when removed", async () => {
    const wrapper = mountStage(editableStage(), { selectedLayerKey: "hero" });
    const hidden = editableStage();
    hidden.composition.layers[0]!.visible = false;
    await wrapper.setProps({ stage: hidden });
    expect(wrapper.find('[data-layer-control="hero"]').exists()).toBe(false);
    expect(wrapper.emitted("update:selectedLayerKey")).toBeUndefined();
    await wrapper.setProps({ stage: { ...hidden, composition: { layers: [] } } });
    expect(wrapper.emitted("update:selectedLayerKey")).toEqual([[null]]);
    wrapper.unmount();
  });

  it("moves freely outside the frame and persists one override when released", () => {
    const wrapper = mountStage();
    pointer(wrapper.get('[data-layer-control="hero"]').element, "pointerdown");
    pointer(window, "pointermove", -400, 200);
    expect(mockLive.pushEvent).not.toHaveBeenCalled();
    pointer(window, "pointerup", -400, 200);
    expect(mockLive.pushEvent).toHaveBeenCalledExactlyOnceWith(
      "override_sequence_visual_layer",
      {
        id: 42,
        layer_key: "hero",
        interaction_id: expect.any(String),
        x: -0.3,
        y: 0.5,
      },
      expect.any(Function),
      expect.any(Function),
    );
    wrapper.unmount();
  });

  it("updates a local layer by row id", () => {
    const stage = editableStage();
    Object.assign(stage.composition.layers[0]!, { sequenceId: 42, rowId: 501 });
    const wrapper = mountStage(stage);
    move(wrapper);
    pointer(window, "pointerup", 200, 150);
    expect(mockLive.pushEvent).toHaveBeenCalledExactlyOnceWith(
      "update_sequence_visual_layer",
      {
        id: 42,
        layer_id: 501,
        interaction_id: expect.any(String),
        x: 0.3,
        y: 0.4,
      },
      expect.any(Function),
      expect.any(Function),
    );
    wrapper.unmount();
  });

  it("keeps proportions and updates anchor coordinates while resizing", async () => {
    const stage = editableStage();
    Object.assign(stage.composition.layers[0]!, { anchorX: 0.5, anchorY: 1 });
    const wrapper = mountStage(stage);
    await wrapper.get('[data-layer-control="hero"]').trigger("click");
    pointer(wrapper.get('[data-layer-resize-handle="nw"]').element, "pointerdown");
    pointer(window, "pointermove", 0, 50);
    pointer(window, "pointerup", 0, 50);
    expect(mockLive.pushEvent).toHaveBeenCalledExactlyOnceWith(
      "override_sequence_visual_layer",
      {
        id: 42,
        layer_key: "hero",
        interaction_id: expect.any(String),
        x: 0.15,
        width: 0.5,
        height: 0.625,
      },
      expect.any(Function),
      expect.any(Function),
    );
    wrapper.unmount();
  });

  it.each(["character", "prop", "backdrop"] as const)(
    "resizes a %s from its side with one commit",
    async (kind) => {
      const stage = editableStage();
      Object.assign(stage.composition.layers[0]!, { kind, anchorX: 0.5, anchorY: 1 });
      const wrapper = mountStage(stage, { selectedLayerKey: "hero" });
      pointer(wrapper.get('[data-layer-resize-handle="e"]').element, "pointerdown");
      pointer(window, "pointermove", 150, 300);
      pointer(window, "pointermove", 200, 350);
      expect(mockLive.pushEvent).not.toHaveBeenCalled();
      pointer(window, "pointerup", 200, 350);
      expect(mockLive.pushEvent).toHaveBeenCalledExactlyOnceWith(
        "override_sequence_visual_layer",
        {
          id: 42,
          layer_key: "hero",
          interaction_id: expect.any(String),
          x: 0.25,
          width: 0.5,
          ...(kind === "character" ? { y: 0.3625, height: 0.625 } : {}),
        },
        expect.any(Function),
        expect.any(Function),
      );
      wrapper.unmount();
    },
  );

  it("cancels a side resize without persisting", () => {
    const wrapper = mountStage(editableStage(), { selectedLayerKey: "hero" });
    pointer(wrapper.get('[data-layer-resize-handle="s"]').element, "pointerdown");
    pointer(window, "pointermove", 200, 200);
    pointer(window, "pointercancel");
    pointer(window, "pointerup", 200, 200);
    expect(mockLive.pushEvent).not.toHaveBeenCalled();
    wrapper.unmount();
  });

  it.each(["pointercancel", "escape", "owner", "unmount"])(
    "cancels safely on %s",
    async (reason) => {
      const wrapper = mountStage();
      move(wrapper);
      if (reason === "pointercancel") pointer(window, "pointercancel");
      if (reason === "escape")
        window.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape" }));
      if (reason === "owner")
        await wrapper.setProps({
          stage: { ...editableStage(), owner: { nodeId: 99, type: "dialogue" } },
        });
      if (reason === "unmount") wrapper.unmount();
      pointer(window, "pointerup", 200, 150);
      expect(mockLive.pushEvent).not.toHaveBeenCalled();
      if (reason !== "unmount") wrapper.unmount();
    },
  );

  it("groups repeated keyboard nudges into one change with a larger Shift step", async () => {
    const wrapper = mountStage();
    const control = wrapper.get('[data-layer-control="hero"]');
    await control.trigger("keydown", { key: "ArrowRight" });
    await control.trigger("keydown", { key: "ArrowRight", repeat: true });
    await control.trigger("keydown", { key: "ArrowRight", shiftKey: true, repeat: true });
    expect(mockLive.pushEvent).not.toHaveBeenCalled();
    window.dispatchEvent(new KeyboardEvent("keyup", { key: "ArrowRight" }));
    expect(mockLive.pushEvent).toHaveBeenCalledExactlyOnceWith(
      "override_sequence_visual_layer",
      {
        id: 42,
        layer_key: "hero",
        interaction_id: expect.any(String),
        x: 0.212,
      },
      expect.any(Function),
      expect.any(Function),
    );
    wrapper.unmount();
  });

  it("keeps rapid gestures cumulative until the server confirms and ignores stale callbacks", async () => {
    const wrapper = mountStage();
    const control = wrapper.get('[data-layer-control="hero"]');
    await control.trigger("keydown", { key: "ArrowRight" });
    window.dispatchEvent(new KeyboardEvent("keyup", { key: "ArrowRight" }));
    await control.trigger("keydown", { key: "ArrowRight" });
    window.dispatchEvent(new KeyboardEvent("keyup", { key: "ArrowRight" }));
    expect(vi.mocked(mockLive.pushEvent).mock.calls[1]?.[1]).toMatchObject({ x: 0.202 });
    vi.mocked(mockLive.pushEvent).mock.calls[0]?.[2]?.({});
    await wrapper.vm.$nextTick();
    expect(wrapper.getComponent(SequenceVisualLayers).props("layers")?.[0]?.x).toBe(0.202);
    const confirmed = editableStage();
    confirmed.composition.layers[0]!.x = 0.202;
    await wrapper.setProps({ stage: confirmed });
    vi.mocked(mockLive.pushEvent).mock.calls[1]?.[2]?.({});
    await wrapper.vm.$nextTick();
    expect(wrapper.getComponent(SequenceVisualLayers).props("layers")?.[0]?.x).toBe(0.202);
    wrapper.unmount();
  });

  it("rolls back optimistic geometry on transport failure", async () => {
    const wrapper = mountStage();
    move(wrapper);
    pointer(window, "pointerup", 200, 150);
    await wrapper.vm.$nextTick();
    expect(wrapper.getComponent(SequenceVisualLayers).props("layers")?.[0]?.x).toBe(0.3);
    vi.mocked(mockLive.pushEvent).mock.calls[0]?.[3]?.(new Error("Disconnected"));
    await wrapper.vm.$nextTick();
    expect(wrapper.getComponent(SequenceVisualLayers).props("layers")?.[0]?.x).toBe(0.2);
    wrapper.unmount();
  });

  it("emits a dropped library image with coordinates relative to the displayed frame", async () => {
    const wrapper = mountStage();
    const image = { asset_id: 12, label: "Aria", url: "/aria.png", source: "asset" };
    await wrapper.get("[data-sequence-canvas]").trigger("drop", {
      clientX: 350,
      clientY: 150,
      dataTransfer: {
        getData: (mime: string) =>
          mime === SEQUENCE_LIBRARY_IMAGE_MIME ? JSON.stringify(image) : "",
      },
    });
    expect(wrapper.emitted("add-image")).toEqual([[{ image, x: 0.25, y: 0.2 }]]);
    expect(mockLive.pushEvent).not.toHaveBeenCalled();
    wrapper.unmount();
  });

  it("hides authoring controls when read only", () => {
    const wrapper = mountStage(editableStage(), { canEdit: false });
    expect(wrapper.find("[data-sequence-layer-controls]").exists()).toBe(false);
    wrapper.unmount();
  });
});
