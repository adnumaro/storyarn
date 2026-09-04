import { mount, flushPromises } from "@vue/test-utils";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { reactive, ref } from "vue";
import { FLOW_CONTEXT_KEY } from "@modules/flows/editor/lib/flow-context";
import { FlowNode as ReteFlowNode } from "@modules/flows/editor/lib/flow-node";
import type { FlowCommentsPanelState, FlowCommentThread } from "@modules/flows/types/comments";

const init = vi.fn();
const setToolbarProps = vi.fn();
const setCommentCounts = vi.fn();
vi.mock("live_vue", () => ({ useLiveVue: () => liveProjection }));
vi.mock("@modules/flows/editor/composables/useFlowCanvas", () => ({
  useFlowCanvas: () => ({
    init,
    editor: ref(null),
    area: ref(null),
    setToolbarProps,
    setCommentCounts,
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
const comments: FlowCommentsPanelState = {
  open: false,
  presentation: "panel",
  threads: [],
  thread: null,
  messages: [],
  nextCursor: null,
  messageNextCursor: null,
  members: [],
  canComment: false,
  selectedNodeId: null,
  error: null,
};
const linkedThread: FlowCommentThread = {
  id: 12,
  status: "open",
  revision: 1,
  message_count: 1,
  created_at: "2026-09-04T09:00:00Z",
  last_activity_at: "2026-09-04T09:00:00Z",
  resolved_at: null,
  resolved_by: null,
  author: { id: 4, display_name: "Ada", avatar_url: null },
  source: { type: "flow_node", id: 42, flow_id: 7, label: "Dialogue", status: "available" },
  position: { x: 10, y: 20 },
};

beforeEach(() => {
  init.mockReset();
  setCommentCounts.mockClear();
  liveProjection.vue.props.surface = undefined;
});

describe("FlowCanvas spatial comment boundary", () => {
  it("enables comment menus before asynchronous node loading finishes", async () => {
    let finish!: () => void;
    init.mockReturnValue(
      new Promise<void>((resolve) => {
        finish = resolve;
      }),
    );
    const wrapper = mount(FlowCanvas, {
      props: { ...props, comments: { state: comments, pins: [], focusThreadId: null } },
    });
    expect(init.mock.calls[0][2]).toMatchObject({ commentsEnabled: true });
    expect(setCommentCounts).not.toHaveBeenCalled();
    finish();
    await flushPromises();
    wrapper.unmount();
  });

  it("skips the initial auto-fit when a thread deep link owns the viewport", async () => {
    init.mockResolvedValue(undefined);
    const wrapper = mount(FlowCanvas, {
      props: {
        ...props,
        flowData: JSON.stringify({
          nodes: [{ id: 42, type: "dialogue", data: {}, position: { x: 300, y: 400 } }],
          connections: [],
        }),
        comments: {
          state: { ...comments, open: true, presentation: "canvas", thread: linkedThread },
          pins: [linkedThread],
          focusThreadId: 12,
        },
      },
    });
    await flushPromises();
    expect(init.mock.calls[0][2]).toMatchObject({ skipInitialFit: true });
    expect(setCommentCounts).toHaveBeenLastCalledWith({}, true);
    wrapper.unmount();
  });

  it("keeps the normal initial fit for the server's unavailable-anchor deep-link contract", async () => {
    init.mockResolvedValue(undefined);
    const unavailable: FlowCommentThread = {
      ...linkedThread,
      source: { ...linkedThread.source, status: "unavailable" },
    };
    const wrapper = mount(FlowCanvas, {
      props: {
        ...props,
        flowData: JSON.stringify({
          nodes: [{ id: 50, type: "dialogue", data: {}, position: { x: 3000, y: 4000 } }],
          connections: [],
        }),
        comments: {
          state: { ...comments, open: true, presentation: "panel", thread: unavailable },
          pins: [],
          focusThreadId: null,
        },
      },
    });
    await flushPromises();
    expect(init.mock.calls[0][2]).toMatchObject({ skipInitialFit: false });
    wrapper.unmount();
  });

  it("leaves comments disabled in compact and version canvases", async () => {
    init.mockResolvedValue(undefined);
    const wrapper = mount(FlowCanvas, { props });
    await flushPromises();
    expect(setCommentCounts).toHaveBeenCalledWith({}, false);
    expect(init.mock.calls[0][2]).toMatchObject({ commentsEnabled: false });
    expect(wrapper.findComponent({ name: "FlowCanvasComments" }).exists()).toBe(false);
    wrapper.unmount();
  });

  it("projects in-place LiveVue changes without reinstalling the Rete bridge", async () => {
    init.mockResolvedValue(undefined);
    const surface: SurfaceData = {
      canvas: { ...props, key: "flow-7", comments, commentPins: [], commentFocusThreadId: null },
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
    liveProjection.vue.props.surface!.canvas.comments!.placing = true;
    liveProjection.vue.props.surface!.canvas.commentFocusThreadId = 12;
    await wrapper.vm.$nextTick();
    expect(wrapper.getComponent(FlowCanvas).props("comments")?.state.placing).toBe(true);
    expect(wrapper.getComponent(FlowCanvas).props("comments")?.focusThreadId).toBe(12);
    expect(setCommentCounts).not.toHaveBeenCalled();
    wrapper.unmount();
  });

  it("exposes node hit targets without duplicate legacy badges, including sequences", () => {
    const context = reactive({
      commentCounts: { 42: 3 },
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
      expect(node.attributes("data-flow-comment-node")).toBe("42");
      expect(node.find("#flow-node-comments-42").exists()).toBe(false);
      node.unmount();
    }
  });
});
