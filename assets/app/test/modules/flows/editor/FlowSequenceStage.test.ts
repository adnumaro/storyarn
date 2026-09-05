import { mount } from "@vue/test-utils";
import SequenceVisualLayers from "@modules/flows/sequence/components/SequenceVisualLayers.vue";
import type { SequenceStageState } from "@modules/flows/sequence/types";
import { createMockLive } from "../../../setup";

const mockLive = createMockLive();

vi.mock("@shared/composables/useLive", () => ({
  useLive: () => mockLive,
}));

const { default: FlowSequenceStage } =
  await import("@modules/flows/editor/components/sequence/FlowSequenceStage.vue");

function mountStage(stage: SequenceStageState, canEdit = false) {
  return mount(FlowSequenceStage, { props: { stage, canEdit } });
}

function dispatchPointer(target: EventTarget, type: string, clientX: number, clientY: number) {
  target.dispatchEvent(new MouseEvent(type, { bubbles: true, cancelable: true, clientX, clientY }));
}

type ReadySequenceStage = Extract<SequenceStageState, { status: "ready" }>;

function editableStage(): ReadySequenceStage {
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

describe("FlowSequenceStage", () => {
  beforeEach(() => {
    vi.mocked(mockLive.pushEvent).mockClear();
  });

  it("guides the author to select a speaker intervention", () => {
    const wrapper = mountStage({ status: "empty" });

    expect(wrapper.attributes("data-status")).toBe("empty");
    expect(wrapper.text()).toContain("Select a speaker intervention");
    expect(wrapper.findComponent(SequenceVisualLayers).exists()).toBe(false);
  });

  it("renders a ready intervention and its effective visual composition", () => {
    const stage: SequenceStageState = {
      status: "ready",
      intervention: {
        nodeId: 42,
        speakerName: "Aria Vale",
        speakerColor: "#7c3aed",
        text: "<p>Open the gate.</p>",
        stageDirections: "Barely above a whisper",
      },
      composition: {
        layers: [
          {
            id: 5,
            kind: "backdrop",
            label: "Moonlit gate",
            url: "/gate.png",
            fit: "cover",
          },
        ],
        diagnostics: [{ code: "missing_prop", severity: "warning" }],
      },
    };
    const wrapper = mountStage(stage);

    expect(wrapper.attributes("data-status")).toBe("ready");
    expect(wrapper.getComponent(SequenceVisualLayers).props("layers")).toEqual(
      stage.composition.layers,
    );
    expect(wrapper.get("[data-sequence-intervention]").text()).toContain("Aria Vale");
    expect(wrapper.get("[data-sequence-intervention]").text()).toContain("Open the gate.");
    expect(wrapper.get("[data-sequence-intervention]").text()).toContain("Barely above a whisper");
    expect(wrapper.get("[data-sequence-diagnostics]").text()).toContain("1 composition issue");
  });

  it("renders the server error without stale visual layers", () => {
    const wrapper = mountStage({
      status: "error",
      errorMessage: "The inherited backdrop is unavailable.",
    });

    expect(wrapper.attributes("data-status")).toBe("error");
    expect(wrapper.text()).toContain("The inherited backdrop is unavailable.");
    expect(wrapper.findComponent(SequenceVisualLayers).exists()).toBe(false);
  });

  it("opens the inspector for the current sequence owner", async () => {
    const wrapper = mountStage(editableStage());

    await wrapper.get("[data-open-sequence-inspector]").trigger("click");

    expect(mockLive.pushEvent).toHaveBeenCalledWith("open_sequence_config", { id: 42 });
  });

  it("keeps direct layer selection in the same stack order as the visual renderer", async () => {
    const stage: ReadySequenceStage = {
      ...editableStage(),
      composition: {
        layers: [
          {
            id: "child-low-z",
            key: "child-low-z",
            sequenceDepth: 1,
            kind: "character",
            label: "Child",
            url: "/child.png",
            zIndex: -1000,
          },
          {
            id: "root-high-z",
            key: "root-high-z",
            sequence_depth: 0,
            kind: "backdrop",
            label: "Root",
            url: "/root.png",
            z_index: 1000,
          },
        ],
      },
    };
    const wrapper = mountStage(stage, true);
    const rendered = wrapper.findAll(".sequence-visual-layer");
    const controls = wrapper.findAll("[data-layer-control]");

    expect(rendered.map((layer) => layer.attributes("data-layer-id"))).toEqual([
      "root-high-z",
      "child-low-z",
    ]);
    expect(controls.map((control) => control.attributes("data-layer-control"))).toEqual([
      "root-high-z",
      "child-low-z",
    ]);
    expect(controls.map((control) => control.attributes("style"))).toEqual([
      expect.stringContaining("z-index: 0"),
      expect.stringContaining("z-index: 1"),
    ]);

    await controls[1]!.trigger("click");
    expect(controls[1]!.attributes("data-selected")).toBe("true");
  });

  it("moves an inherited layer and persists its geometry as an override", async () => {
    const wrapper = mountStage(editableStage(), true);
    const viewport = wrapper.get(".flow-sequence-viewport");
    vi.spyOn(viewport.element, "getBoundingClientRect").mockReturnValue({
      x: 0,
      y: 0,
      left: 0,
      top: 0,
      right: 1000,
      bottom: 500,
      width: 1000,
      height: 500,
      toJSON: () => ({}),
    });

    dispatchPointer(wrapper.get('[data-layer-control="hero"]').element, "pointerdown", 100, 100);
    dispatchPointer(window, "pointermove", 200, 150);
    dispatchPointer(window, "pointerup", 200, 150);

    expect(mockLive.pushEvent).toHaveBeenCalledWith("override_sequence_visual_layer", {
      id: 42,
      layer_key: "hero",
      x: 0.3,
      y: 0.4,
    });
    wrapper.unmount();
  });

  it("moves an owner-defined layer by its persisted row id", () => {
    const stage = editableStage();
    const layer = stage.composition.layers[0]!;
    layer.sequenceId = 42;
    layer.rowId = 501;
    const wrapper = mountStage(stage, true);
    const viewport = wrapper.get(".flow-sequence-viewport");
    vi.spyOn(viewport.element, "getBoundingClientRect").mockReturnValue({
      x: 0,
      y: 0,
      left: 0,
      top: 0,
      right: 1000,
      bottom: 500,
      width: 1000,
      height: 500,
      toJSON: () => ({}),
    });

    dispatchPointer(wrapper.get('[data-layer-control="hero"]').element, "pointerdown", 100, 100);
    dispatchPointer(window, "pointermove", 200, 150);
    dispatchPointer(window, "pointerup", 200, 150);

    expect(mockLive.pushEvent).toHaveBeenCalledWith("update_sequence_visual_layer", {
      id: 42,
      layer_id: 501,
      x: 0.3,
      y: 0.4,
    });
    wrapper.unmount();
  });

  it("resizes an inherited layer as an override and hides controls in read-only mode", async () => {
    const readOnly = mountStage(editableStage());
    expect(readOnly.find("[data-sequence-layer-controls]").exists()).toBe(false);

    const wrapper = mountStage(editableStage(), true);
    const viewport = wrapper.get(".flow-sequence-viewport");
    vi.spyOn(viewport.element, "getBoundingClientRect").mockReturnValue({
      x: 0,
      y: 0,
      left: 0,
      top: 0,
      right: 1000,
      bottom: 500,
      width: 1000,
      height: 500,
      toJSON: () => ({}),
    });

    await wrapper.get('[data-layer-control="hero"]').trigger("click");
    dispatchPointer(wrapper.get("[data-layer-resize-handle]").element, "pointerdown", 100, 100);
    dispatchPointer(window, "pointermove", 200, 150);
    dispatchPointer(window, "pointerup", 200, 150);

    expect(mockLive.pushEvent).toHaveBeenCalledWith("override_sequence_visual_layer", {
      id: 42,
      layer_key: "hero",
      width: 0.5,
      height: 0.6,
    });
    readOnly.unmount();
    wrapper.unmount();
  });

  it("resizes an owner-defined layer by its persisted row id", async () => {
    const stage = editableStage();
    const layer = stage.composition.layers[0]!;
    layer.sequenceId = 42;
    layer.rowId = 501;
    const wrapper = mountStage(stage, true);
    const viewport = wrapper.get(".flow-sequence-viewport");
    vi.spyOn(viewport.element, "getBoundingClientRect").mockReturnValue({
      x: 0,
      y: 0,
      left: 0,
      top: 0,
      right: 1000,
      bottom: 500,
      width: 1000,
      height: 500,
      toJSON: () => ({}),
    });

    await wrapper.get('[data-layer-control="hero"]').trigger("click");
    dispatchPointer(wrapper.get("[data-layer-resize-handle]").element, "pointerdown", 100, 100);
    dispatchPointer(window, "pointermove", 200, 150);
    dispatchPointer(window, "pointerup", 200, 150);

    expect(mockLive.pushEvent).toHaveBeenCalledWith("update_sequence_visual_layer", {
      id: 42,
      layer_id: 501,
      width: 0.5,
      height: 0.6,
    });
    wrapper.unmount();
  });
});
