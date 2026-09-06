import { flushPromises, mount } from "@vue/test-utils";
import { defineComponent, onMounted, reactive } from "vue";
import { createMockLive } from "@app/test/setup";
const live = createMockLive();
vi.mock("@shared/composables/useLive", () => ({ useLive: () => live }));

const liveProjection = reactive<{ vue: { props: { surface?: SurfaceData } } }>({
  vue: { props: {} },
});

vi.mock("live_vue", () => ({ useLiveVue: () => liveProjection }));

const { default: FlowSurface } = await import("@app/live/flow/show/FlowSurface.vue");
type SurfaceData = InstanceType<typeof FlowSurface>["$props"]["surface"];

const canvasMounts = vi.fn();
const FlowCanvasStub = defineComponent({
  name: "FlowCanvas",
  props: ["fitViewRequest"],
  setup() {
    onMounted(canvasMounts);
    return {};
  },
  template: '<div data-canvas-stub="true" />',
});

const stopVoice = vi.fn();
const stopPreviews = vi.fn();
const pausePreviews = vi.fn();
const FlowSequenceStageStub = defineComponent({
  name: "FlowSequenceWorkspace",
  props: ["stage", "canEdit", "fullscreen", "playback", "debugging", "data"],
  setup(_props, { expose }) {
    expose({ stopVoicePreview: stopVoice, stopPreviews, pausePreviews });
  },
  emits: ["toggle-fullscreen"],
  template:
    '<div data-stage-stub="true" :data-status="stage.status" :data-can-edit="canEdit"><button data-stage-fullscreen @click="$emit(\'toggle-fullscreen\')" /></div>',
});

const FlowDockStub = defineComponent({
  name: "FlowDock",
  props: ["visualEditorOpen"],
  emits: ["toggle-visual-editor"],
  template:
    '<button data-visual-editor-toggle :data-open="visualEditorOpen" @click="$emit(\'toggle-visual-editor\')" />',
});

function surfaceData(): SurfaceData {
  return {
    canvas: {
      key: "flow-7",
      flowData: '{"nodes":[],"connections":[]}',
      variableMap: "{}",
      loading: false,
      readonly: false,
      userId: 4,
      userColor: "#123456",
      canvasId: "flow-canvas-7",
      toolbarData: "{}",
    },
    dock: {
      canEdit: true,
      compact: false,
      debugPanelOpen: false,
    },
    stage: { status: "empty" },
  };
}

function mountSurface(surface: SurfaceData) {
  liveProjection.vue.props.surface = surface;
  return mount(FlowSurface, {
    attachTo: document.body,
    props: { surface },
    global: {
      stubs: {
        Teleport: true,
        FlowCanvas: FlowCanvasStub,
        FlowSequenceWorkspace: FlowSequenceStageStub,
        FlowDebugPanel: true,
        FlowDock: FlowDockStub,
        FlowCollabToast: true,
      },
    },
  });
}

describe("FlowSurface sequence workspace", () => {
  beforeEach(() => {
    canvasMounts.mockClear();
    stopVoice.mockClear();
    stopPreviews.mockClear();
    pausePreviews.mockClear();
    liveProjection.vue.props.surface = undefined;
  });

  it("uses Play and Stop to toggle the visual editor beside the same Flow canvas", async () => {
    const surface = surfaceData();
    const wrapper = mountSurface(surface);
    const canvas = wrapper.get("[data-canvas-stub]").element;
    const toggle = wrapper.get("[data-visual-editor-toggle]");

    expect(wrapper.getComponent(FlowDockStub).props("visualEditorOpen")).toBe(false);
    await toggle.trigger("click");

    expect(wrapper.find("[data-stage-stub]").exists()).toBe(true);
    expect(wrapper.find("[data-flow-splitter]").exists()).toBe(true);
    expect(wrapper.getComponent(FlowDockStub).props("visualEditorOpen")).toBe(true);
    expect(wrapper.getComponent(FlowCanvasStub).props("fitViewRequest")).toBe(1);
    expect(wrapper.get("[data-canvas-stub]").element).toBe(canvas);

    liveProjection.vue.props.surface = {
      ...surface,
      stage: { status: "ready", composition: { layers: [] } },
      sequencePlayback: {
        slide: { type: "dialogue", text: "Hello" },
        visualLayers: [],
        audioTracks: [],
        voice: null,
        canGoBack: false,
        showContinue: true,
        isFinished: false,
        error: null,
      },
    };
    await flushPromises();
    expect(wrapper.get("[data-stage-stub]").attributes("data-status")).toBe("ready");
    expect(wrapper.getComponent(FlowSequenceStageStub).props("playback").slide.text).toBe("Hello");
    expect(wrapper.get("[data-canvas-stub]").element).toBe(canvas);

    await toggle.trigger("click");

    expect(wrapper.find("[data-stage-stub]").exists()).toBe(false);
    expect(wrapper.find("[data-flow-splitter]").exists()).toBe(false);
    expect(wrapper.getComponent(FlowDockStub).props("visualEditorOpen")).toBe(false);
    expect(wrapper.get("[data-canvas-stub]").element).toBe(canvas);
    expect(canvasMounts).toHaveBeenCalledTimes(1);
    wrapper.unmount();
  });

  it("starts with a larger split and lets the author resize both views", async () => {
    const wrapper = mountSurface(surfaceData());
    await wrapper.get("[data-visual-editor-toggle]").trigger("click");
    const root = wrapper.element as HTMLElement;
    vi.spyOn(root, "getBoundingClientRect").mockReturnValue(
      DOMRect.fromRect({ width: 1200, height: 1000 }),
    );

    expect(wrapper.get("[data-flow-upper-workspace]").attributes("style")).toContain("60%");
    wrapper
      .get("[data-flow-splitter]")
      .element.dispatchEvent(
        new MouseEvent("pointerdown", { bubbles: true, cancelable: true, clientY: 600 }),
      );
    window.dispatchEvent(new MouseEvent("pointermove", { clientY: 700 }));
    window.dispatchEvent(new MouseEvent("pointerup", { clientY: 700 }));
    await flushPromises();

    expect(wrapper.get("[data-flow-upper-workspace]").attributes("style")).toContain("70%");
    wrapper.unmount();
  });

  it("keeps the upper editor clear of the open sequence sidebar", async () => {
    const surface = surfaceData();
    surface.sequencePanelOpen = true;
    const wrapper = mountSurface(surface);
    const canvas = wrapper.get("[data-canvas-stub]").element;
    await wrapper.get("[data-visual-editor-toggle]").trigger("click");

    expect(wrapper.get("[data-flow-upper-workspace]").classes()).toContain("md:pr-[24.75rem]");

    await wrapper.get("[data-stage-fullscreen]").trigger("click");

    expect(wrapper.get("[data-flow-upper-workspace]").classes()).not.toContain("md:pr-[24.75rem]");
    expect(wrapper.get("[data-flow-upper-workspace]").classes()).toContain("z-45");
    expect(wrapper.get("#flow-lower-workspace").isVisible()).toBe(false);
    expect(wrapper.get("[data-canvas-stub]").element).toBe(canvas);
    wrapper.unmount();
  });
  it.each([false, true])(
    "shows executed composition during Debug and restores prior open=%s",
    async (wasOpen) => {
      const surface = surfaceData();
      const wrapper = mountSurface(surface);
      if (wasOpen) await wrapper.get("[data-visual-editor-toggle]").trigger("click");
      const debug: NonNullable<SurfaceData["debug"]> = {
        open: true,
        state: {
          status: "paused",
          current_node_id: 42,
          start_node_id: 1,
          step_count: 1,
          max_steps: 1000,
          variables: {},
          console: [],
          history: [],
          execution_path: [42],
          execution_log: [],
          pending_choices: null,
          call_stack: [],
          breakpoints: [],
        },
        nodes: {},
        controls: {
          activeTab: "composition",
          autoPlaying: false,
          speed: 800,
          varFilter: "",
          varChangedOnly: false,
          flowName: "Test",
          stepLimitReached: false,
        },
        composition: {
          presentationNodeId: 42,
          visualLayers: [],
          removedVisualLayers: [],
          audioTracks: [],
          removedAudioTracks: [],
          diagnostics: [],
        },
      };
      liveProjection.vue.props.surface = {
        ...surface,
        debug,
        stage: {
          status: "ready",
          owner: { nodeId: 42, type: "dialogue" },
          composition: { layers: [], audioTracks: [] },
        },
      };
      await flushPromises();
      const stage = wrapper.getComponent(FlowSequenceStageStub);
      expect(stage.props("canEdit")).toBe(false);
      expect(stage.props("debugging")).toBe(true);
      expect(stage.props("data").owner_id).toBe(42);
      expect(wrapper.get("[data-flow-workspace='canvas']").isVisible()).toBe(false);
      wrapper.getComponent({ name: "FlowDebugPanel" }).vm.$emit("playback-action", "pause");
      expect(pausePreviews).toHaveBeenCalled();
      wrapper.getComponent({ name: "FlowDebugPanel" }).vm.$emit("playback-action", "step");
      expect(stopVoice).toHaveBeenCalled();
      liveProjection.vue.props.surface = surface;
      await flushPromises();
      expect(stopPreviews).toHaveBeenCalled();
      expect(wrapper.find("[data-stage-stub]").exists()).toBe(wasOpen);
      expect(wrapper.get("[data-flow-workspace='canvas']").isVisible()).toBe(true);
      wrapper.unmount();
    },
  );
});
