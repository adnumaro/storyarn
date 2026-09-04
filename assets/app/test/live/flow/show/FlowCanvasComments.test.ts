import { mount, flushPromises } from "@vue/test-utils";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { ref } from "vue";

const init = vi.fn();
const setToolbarProps = vi.fn();
const setCommentCounts = vi.fn();
const focusCommentNode = vi.fn();
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
});
