import { beforeEach, describe, expect, it, vi } from "vitest";
import { mount } from "@vue/test-utils";
import { createMockLive } from "@app/test/setup";
import type {
  CommentContextReference,
  CommentPosition,
  CommentsPanelState,
  CommentUiConfig,
} from "@components/comments/types";

const live = createMockLive();
vi.mock("@shared/composables/useLive", () => ({ useLive: () => live }));
const { default: CommentComposer } = await import("@components/comments/CommentComposer.vue");
const { default: CommentConversation } =
  await import("@components/comments/CommentConversation.vue");

const passthrough = { template: "<div><slot /></div>" };
const stubs = { Popover: passthrough, PopoverContent: passthrough, PopoverTrigger: passthrough };
const ui: CommentUiConfig = {
  domScope: "flow",
  i18nPrefix: "flows.comments",
  canvasSourceType: "flow_canvas",
  scopeThreadsKey: "flow_threads",
  selectedSourceFallbackKey: "node_label",
  createSourceKey: "node_id",
};
const context: CommentContextReference = {
  type: "flow_node",
  id: "42",
  offset: { x: 25, y: 30 },
};

function composer(
  overrides: {
    context?: CommentContextReference | null;
    position?: CommentPosition | null;
    threadId?: number | null;
    parentId?: number | null;
  } = {},
) {
  return mount(CommentComposer, {
    props: {
      sourceId: null,
      position: { x: 400, y: 200 },
      draftId: "draft-a",
      members: [],
      ui,
      ...overrides,
    },
    global: { stubs },
  });
}

function lastRequest() {
  return vi.mocked(live.pushEvent).mock.calls.at(-1)!;
}

describe("Comment composer contextual drafts", () => {
  beforeEach(() => vi.mocked(live.pushEvent).mockClear());

  it("retries the same position and context with the same identity, and rotates it when context changes", async () => {
    const wrapper = composer({ context });
    await wrapper.get("textarea").setValue("Keep this note near the guard.");
    await wrapper.get("form").trigger("submit");
    const first = lastRequest();
    expect(first[1]).toMatchObject({
      node_id: null,
      position: { x: 400, y: 200 },
      context,
    });
    first[3]!(new Error("Response lost"));
    await wrapper.setProps({
      context: { id: "42", offset: { y: 30, x: 25 }, type: "flow_node" },
    });
    await wrapper.get("form").trigger("submit");
    expect(lastRequest()[1]).toEqual(first[1]);
    lastRequest()[2]!({ ok: false });

    await wrapper.setProps({ context: { ...context, id: "43" } });
    await wrapper.get("form").trigger("submit");
    const changed = lastRequest();
    expect(changed[1]?.client_request_id).not.toBe(first[1]?.client_request_id);
    expect(changed[1]?.context).toMatchObject({ id: "43" });
    changed[2]!({ ok: false });

    await wrapper.setProps({ context: null });
    await wrapper.get("form").trigger("submit");
    expect(lastRequest()[1]?.context).toBeNull();
    expect(lastRequest()[1]?.client_request_id).not.toBe(changed[1]?.client_request_id);
    expect(lastRequest()[1]?.body).toBe("Keep this note near the guard.");
  });

  it("does not add context to legacy creation or to replies", async () => {
    const wrapper = composer();
    await wrapper.get("textarea").setValue("A free note");
    await wrapper.get("form").trigger("submit");
    expect(lastRequest()[1]).not.toHaveProperty("context");
    lastRequest()[2]!({ ok: false });

    await wrapper.setProps({ threadId: 12, parentId: 21, context });
    await wrapper.get("textarea").setValue("A reply");
    await wrapper.get("form").trigger("submit");
    const reply = lastRequest();
    expect(reply[0]).toBe("comments_reply");
    expect(reply[1]).not.toHaveProperty("context");
    expect(reply[1]).not.toHaveProperty("position");
    reply[3]!(new Error("Disconnected"));
    await wrapper.setProps({ context: null });
    await wrapper.get("form").trigger("submit");
    expect(lastRequest()[1]).toEqual(reply[1]);
  });

  it("keeps the draft mounted while a position update is pending and sends its confirmed context", async () => {
    const state: CommentsPanelState = {
      open: true,
      presentation: "canvas",
      draftPosition: { x: 400, y: 200 },
      draftContext: context,
      draftId: "draft-a",
      threads: [],
      nextCursor: null,
      thread: null,
      messages: [],
      messageNextCursor: null,
      members: [],
      canComment: true,
      selectedSourceId: null,
      error: null,
    };
    const wrapper = mount(CommentConversation, {
      props: { state, embedded: true, ui },
      global: { stubs },
    });
    await wrapper.get("textarea").setValue("The draft survives dragging.");
    await wrapper.setProps({ state: { ...state, draftPending: true } });
    expect(wrapper.get("textarea").attributes("disabled")).toBeDefined();
    await wrapper.get("form").trigger("submit");
    expect(live.pushEvent).not.toHaveBeenCalled();

    await wrapper.setProps({ state: { ...state, draftContext: null, draftPending: false } });
    expect((wrapper.get("textarea").element as HTMLTextAreaElement).value).toBe(
      "The draft survives dragging.",
    );
    await wrapper.get("form").trigger("submit");
    expect(lastRequest()[1]).toMatchObject({
      node_id: null,
      position: state.draftPosition,
      context: null,
      body: "The draft survives dragging.",
    });
  });
});
