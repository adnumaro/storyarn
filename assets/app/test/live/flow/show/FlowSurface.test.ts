import { mount } from "@vue/test-utils";
import { defineComponent, onMounted, reactive } from "vue";

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

const FlowSequenceStageStub = defineComponent({
  name: "FlowSequenceStage",
  props: ["stage", "canEdit", "fullscreen"],
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
    props: { surface },
    global: {
      stubs: {
        FlowCanvas: FlowCanvasStub,
        FlowSequenceStage: FlowSequenceStageStub,
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
    };
    await wrapper.vm.$nextTick();
    expect(wrapper.get("[data-stage-stub]").attributes("data-status")).toBe("ready");

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
    await wrapper.vm.$nextTick();

    expect(wrapper.get("[data-flow-upper-workspace]").attributes("style")).toContain("70%");
    wrapper.unmount();
  });

  it("keeps the upper editor clear of the open sequence sidebar", async () => {
    const surface = surfaceData();
    surface.sequencePanelOpen = true;
    const wrapper = mountSurface(surface);
    const canvas = wrapper.get("[data-canvas-stub]").element;
    await wrapper.get("[data-visual-editor-toggle]").trigger("click");
    const upperWorkspace = wrapper.get("[data-flow-upper-workspace]");

    expect(upperWorkspace.classes()).toContain("md:pr-[24.75rem]");

    await wrapper.get("[data-stage-fullscreen]").trigger("click");

    expect(upperWorkspace.classes()).not.toContain("md:pr-[24.75rem]");
    expect(wrapper.get("[data-flow-upper-workspace]").classes()).toContain("z-30");
    expect(wrapper.get("#flow-lower-workspace").isVisible()).toBe(false);
    expect(wrapper.get("[data-canvas-stub]").element).toBe(canvas);
    wrapper.unmount();
  });
});
