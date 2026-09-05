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
  setup() {
    onMounted(canvasMounts);
    return {};
  },
  template: '<div data-canvas-stub="true" />',
});

const FlowSequenceStageStub = defineComponent({
  name: "FlowSequenceStage",
  props: ["stage", "canEdit"],
  template: '<div data-stage-stub="true" :data-status="stage.status" :data-can-edit="canEdit" />',
});

const FlowDebugPanelStub = defineComponent({
  name: "FlowDebugPanel",
  props: ["open", "embedded"],
  template: '<div v-if="open" data-debug-stub="true" :data-embedded="embedded" />',
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
      workspaceSlug: "team",
      projectSlug: "story",
      flowId: 7,
    },
    stage: { status: "empty" },
    debug: {
      open: false,
      state: null,
      nodes: {},
      controls: {
        activeTab: "console",
        autoPlaying: false,
        speed: 800,
        varFilter: "",
        varChangedOnly: false,
        flowName: "Opening",
        stepLimitReached: false,
      },
    },
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
        FlowDebugPanel: FlowDebugPanelStub,
        FlowDock: true,
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

  it("keeps the canvas usable with the pre-sequence surface contract", () => {
    const legacySurface = surfaceData();
    delete legacySurface.stage;
    delete legacySurface.debug;

    const wrapper = mountSurface(legacySurface);

    expect(wrapper.get("[data-stage-stub]").attributes("data-status")).toBe("empty");
    expect(wrapper.get('[data-flow-workspace="canvas"]').isVisible()).toBe(true);
    expect(wrapper.find('[data-flow-workspace="debug"]').exists()).toBe(false);
    wrapper.unmount();
  });

  it("projects stage updates without remounting the Flow canvas", async () => {
    const surface = surfaceData();
    const wrapper = mountSurface(surface);
    const canvas = wrapper.get("[data-canvas-stub]").element;

    liveProjection.vue.props.surface = {
      ...surface,
      stage: {
        status: "ready",
        intervention: { nodeId: 42, speakerName: "Aria" },
        composition: { layers: [] },
      },
    };
    await wrapper.vm.$nextTick();

    expect(wrapper.get("[data-stage-stub]").attributes("data-status")).toBe("ready");
    expect(wrapper.get("[data-stage-stub]").attributes("data-can-edit")).toBe("true");
    expect(wrapper.get("[data-canvas-stub]").element).toBe(canvas);
    expect(canvasMounts).toHaveBeenCalledTimes(1);
    wrapper.unmount();
  });

  it("alternates the lower workspace to embedded Debug while retaining the canvas", async () => {
    const surface = surfaceData();
    const wrapper = mountSurface(surface);
    const canvas = wrapper.get("[data-canvas-stub]").element;

    liveProjection.vue.props.surface = {
      ...surface,
      dock: { ...surface.dock, debugPanelOpen: true },
      debug: {
        ...surface.debug!,
        open: true,
        state: {
          status: "paused",
          current_node_id: 42,
          start_node_id: 42,
          step_count: 1,
          max_steps: 1000,
          variables: {},
          console: [],
          history: [],
          execution_path: [42],
          execution_log: [{ node_id: 42, depth: 0 }],
          pending_choices: null,
          call_stack: [],
          breakpoints: [],
        },
      },
    };
    await wrapper.vm.$nextTick();

    expect(wrapper.get('[data-flow-workspace="canvas"]').isVisible()).toBe(false);
    expect(wrapper.get('[data-flow-workspace="debug"]').isVisible()).toBe(true);
    expect(wrapper.get("[data-debug-stub]").attributes()).toHaveProperty("data-embedded");
    expect(wrapper.get("[data-canvas-stub]").element).toBe(canvas);
    expect(canvasMounts).toHaveBeenCalledTimes(1);
    wrapper.unmount();
  });
});
