import { mount, flushPromises } from "@vue/test-utils";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { isReactive, reactive, ref } from "vue";
import { FLOW_CONTEXT_KEY } from "@modules/flows/editor/lib/flow-context";
import { FlowNode as ReteFlowNode } from "@modules/flows/editor/lib/flow-node";

const init = vi.fn();
const setToolbarProps = vi.fn();
const setCommentCounts = vi.fn();
const focusCommentNode = vi.fn();
vi.mock("live_vue", () => ({ useLiveVue: () => liveProjection }));
vi.mock("@modules/flows/editor/composables/useFlowCanvas", () => ({
  useFlowCanvas: () => ({
    init,
    editor: ref(null),
    area: ref(null),
    setToolbarProps,
    setCommentCounts,
    focusCommentNode,
  }),
}));
const { default: FlowCanvas } = await import("@app/live/flow/show/FlowCanvas.vue");
const { default: FlowSurface } = await import("@app/live/flow/show/FlowSurface.vue");
const { default: FlowNode } =
  await import("@modules/flows/editor/components/entities/rete/FlowNode.vue");
const { default: SequenceNode } =
  await import("@modules/flows/editor/components/entities/nodes/SequenceNode.vue");
type SurfaceData = InstanceType<typeof FlowSurface>["$props"]["surface"];
const liveProjection = reactive<{ vue: { props: { surface?: SurfaceData } } }>({
  vue: { props: {} },
});

const props = {
  flowData: '{"nodes":[],"connections":[]}',
  variableMap: "{}",
  loading: false,
  readonly: true,
  userId: 4,
  userColor: "#123456",
  canvasId: "test-canvas",
  toolbarData: "{}",
};

describe("FlowCanvas comment projection", () => {
  beforeEach(() => {
    init.mockReset();
    setCommentCounts.mockClear();
    focusCommentNode.mockClear();
    liveProjection.vue.props.surface = undefined;
  });

  it("waits for canvas readiness and uses the latest deep-link target", async () => {
    let ready!: () => void;
    init.mockReturnValue(
      new Promise<void>((resolve) => {
        ready = resolve;
      }),
    );
    const wrapper = mount(FlowCanvas, {
      props: { ...props, comments: { enabled: true, counts: { 42: 1 }, focusNodeId: 42 } },
    });
    await wrapper.setProps({ comments: { enabled: true, counts: { 43: 2 }, focusNodeId: 43 } });
    expect(focusCommentNode).not.toHaveBeenCalled();
    ready();
    await flushPromises();
    expect(focusCommentNode).toHaveBeenCalledExactlyOnceWith(43);
    expect(setCommentCounts).toHaveBeenLastCalledWith({ 43: 2 }, true);
    wrapper.unmount();
  });

  it("leaves comments disabled in standalone compact and version canvases", async () => {
    init.mockResolvedValue(undefined);
    const wrapper = mount(FlowCanvas, { props });
    await flushPromises();
    expect(setCommentCounts).toHaveBeenCalledWith({}, false);
    expect(focusCommentNode).not.toHaveBeenCalled();
    wrapper.unmount();
  });

  it("does not resync comment counts for unrelated live surface updates", async () => {
    init.mockResolvedValue(undefined);
    const surface: SurfaceData = {
      canvas: { ...props, key: "flow-7", commentCounts: { 42: 1 }, commentFocusNodeId: null },
      dock: {
        canEdit: false,
        compact: false,
        debugPanelOpen: false,
        workspaceSlug: "team",
        projectSlug: "story",
        flowId: 7,
      },
    };
    liveProjection.vue.props.surface = surface;
    const wrapper = mount(FlowSurface, {
      props: { surface },
      global: { stubs: { FlowDock: true, FlowCollabToast: true } },
    });
    await flushPromises();
    setCommentCounts.mockClear();

    liveProjection.vue.props.surface!.canvas.toolbarData = '{"hubs":[]}';
    await wrapper.vm.$nextTick();
    liveProjection.vue.props.surface!.dock.debugPanelOpen = true;
    await wrapper.vm.$nextTick();
    liveProjection.vue.props.surface!.canvas = {
      ...liveProjection.vue.props.surface!.canvas,
      userColor: "#abcdef",
    };
    await wrapper.vm.$nextTick();
    expect(setCommentCounts).not.toHaveBeenCalled();

    liveProjection.vue.props.surface!.canvas.commentCounts = { 42: 2 };
    await wrapper.vm.$nextTick();
    expect(setCommentCounts).toHaveBeenCalledExactlyOnceWith({ 42: 2 }, true);
    wrapper.unmount();
  });

  it("updates both node renderers when LiveVue patches counts in place", async () => {
    init.mockResolvedValue(undefined);
    const surface: SurfaceData = {
      canvas: { ...props, key: "flow-7", commentCounts: { 42: 1 }, commentFocusNodeId: null },
      dock: {
        canEdit: false,
        compact: false,
        debugPanelOpen: false,
        workspaceSlug: "team",
        projectSlug: "story",
        flowId: 7,
      },
    };
    liveProjection.vue.props.surface = surface;
    const wrapper = mount(FlowSurface, {
      props: { surface },
      global: { stubs: { FlowDock: true, FlowCollabToast: true } },
    });
    await flushPromises();

    const counts = liveProjection.vue.props.surface!.canvas.commentCounts!;
    const installedCounts = setCommentCounts.mock.lastCall![0] as Record<string, number>;
    expect(installedCounts).toBe(counts);
    expect(isReactive(installedCounts)).toBe(true);
    // The Rete bridge assigns this same map to its reactive, provided context.
    const context = reactive({
      commentCounts: installedCounts,
      commentsEnabled: true,
      sheetsMap: {},
      hubsMap: {},
      lod: "full",
      nodeDataVersion: 0,
      selectedReteNodeId: null,
      selectedReteIds: new Set<string | number>(),
      canEdit: false,
      toolbarProps: {},
      zoom: 1,
    });
    const global = {
      provide: { [FLOW_CONTEXT_KEY]: context },
      stubs: { HubNode: true, FlowNodeToolbar: true },
    };
    const sequence = new ReteFlowNode("sequence", 42, { name: "Sequence" });
    sequence.id = "node-42";
    const nodes = [
      mount(FlowNode, {
        props: { data: { id: "node-42", nodeType: "hub", nodeData: {} }, emit: vi.fn() },
        global,
      }),
      mount(SequenceNode, { props: { data: sequence }, global }),
    ];
    for (const node of nodes) {
      expect(node.get("#flow-node-comments-42").text()).toBe("1");
    }
    setCommentCounts.mockClear();

    // LiveVue's JSON Patch replace/remove mutate nested reactive maps in place.
    counts[42] = 2;
    await wrapper.vm.$nextTick();
    for (const node of nodes) {
      expect(node.get("#flow-node-comments-42").text()).toBe("2");
    }
    delete counts[42];
    await wrapper.vm.$nextTick();
    for (const node of nodes) {
      expect(node.get("#flow-node-comments-42").attributes("aria-label")).toBe("New thread");
      expect(node.get("#flow-node-comments-42").find("span").exists()).toBe(false);
      node.unmount();
    }
    expect(context.commentCounts).toBe(counts);
    expect(setCommentCounts).not.toHaveBeenCalled();
    wrapper.unmount();
  });
});
