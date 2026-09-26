import { mount } from "@vue/test-utils";
import { describe, expect, it, vi } from "vitest";
import FlowCursors from "@modules/flows/editor/components/chrome/FlowCursors.vue";
import { createMockLive } from "../../../setup";

function cursorTransform(wrapper: ReturnType<typeof mount>): string | undefined {
  return wrapper.get("[style*='translate']").attributes("style");
}

describe("FlowCursors", () => {
  it("keeps a remote cursor on its canvas point when the local view pans and zooms", async () => {
    const live = createMockLive();
    const wrapper = mount(FlowCursors, {
      props: { areaTransform: { x: 0, y: 0, k: 1 }, currentUserId: 1, containerEl: null },
      global: { config: { globalProperties: { $live: live } as never } },
    });
    const onUpdate = vi
      .mocked(live.handleEvent)
      .mock.calls.find(([event]) => event === "cursor_update")?.[1];

    onUpdate?.({ user_id: 2, x: 100, y: 50, user_email: "ana@example.com" });
    await wrapper.vm.$nextTick();
    expect(cursorTransform(wrapper)).toContain("translate(100px, 50px)");

    // The local user pans by (20, 10) and zooms to 2x; the remote user does not move.
    await wrapper.setProps({ areaTransform: { x: 20, y: 10, k: 2 } });
    expect(cursorTransform(wrapper)).toContain("translate(220px, 110px)");
  });
});
