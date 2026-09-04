import { mount } from "@vue/test-utils";
import { describe, expect, it, vi } from "vitest";
import { createMockLive } from "@app/test/setup";

const mockLive = createMockLive();
vi.mock("@shared/composables/useLive", () => ({ useLive: () => mockLive }));
const { default: NodeCommentBadge } =
  await import("@modules/flows/editor/components/entities/node-shell/NodeCommentBadge.vue");

describe("NodeCommentBadge", () => {
  it("opens node comments without selecting or editing the node", async () => {
    vi.mocked(mockLive.pushEvent).mockClear();
    const wrapper = mount(NodeCommentBadge, { props: { nodeId: "42", count: 2, zoom: 0.5 } });
    await wrapper.get("button").trigger("click");
    expect(mockLive.pushEvent).toHaveBeenCalledExactlyOnceWith("comments_open", { node_id: 42 });
    expect(wrapper.get("button").attributes("aria-label")).toBe("2 open threads");
    expect(wrapper.get("button").attributes("style")).toContain("scale(2)");
  });

  it("provides an accessible entry point when a node has no comments", () => {
    const wrapper = mount(NodeCommentBadge, { props: { nodeId: 42, count: 0, revealed: false } });
    expect(wrapper.get("button").attributes("aria-label")).toBe("New thread");
    expect(wrapper.get("button").attributes("disabled")).toBeUndefined();
  });
});
