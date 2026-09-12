import { beforeEach, describe, expect, it, vi } from "vitest";
import { mount } from "@vue/test-utils";
import { nextTick } from "vue";
import { createMockLive } from "@app/test/setup";
import type { CommentUiConfig } from "@components/comments/types";

const live = createMockLive();
vi.mock("@shared/composables/useLive", () => ({ useLive: () => live }));
const { default: CommentComposer } = await import("@components/comments/CommentComposer.vue");
const passthrough = { template: "<div><slot /></div>" };
const ui: CommentUiConfig = {
  domScope: "hub",
  i18nPrefix: "comments_hub",
  canvasSourceType: "sheet_canvas",
  scopeThreadsKey: "threads",
  selectedSourceFallbackKey: "source_label",
};
const key = "storyarn:comments-hub:draft:9:4:12";
const storageKey = `${key}:thread:12:parent:21`;

function composer(persistReplyDraft = true) {
  return mount(CommentComposer, {
    props: {
      threadId: 12,
      parentId: 21,
      members: [],
      ui: { ...ui, persistReplyDraft },
      draftStorageKey: key,
    },
    global: {
      stubs: { Popover: passthrough, PopoverContent: passthrough, PopoverTrigger: passthrough },
    },
  });
}

describe("Opt-in persisted reply drafts", () => {
  beforeEach(() => {
    window.sessionStorage.clear();
    vi.mocked(live.pushEvent).mockClear();
  });

  it("leaves editor reply persistence disabled unless explicitly enabled", async () => {
    const wrapper = composer(false);
    await wrapper.get("textarea").setValue("An editor reply.");
    wrapper.unmount();
    expect(window.sessionStorage.length).toBe(0);
    expect((composer(false).get("textarea").element as HTMLTextAreaElement).value).toBe("");
  });

  it("keeps replies to different parents separate", async () => {
    const wrapper = composer();
    await wrapper.get("textarea").setValue("Root reply.");
    await wrapper.setProps({ parentId: 22 });
    expect((wrapper.get("textarea").element as HTMLTextAreaElement).value).toBe("");
    await wrapper.get("textarea").setValue("Reply to another message.");
    await wrapper.setProps({ parentId: 21 });
    expect((wrapper.get("textarea").element as HTMLTextAreaElement).value).toBe("Root reply.");
    wrapper.unmount();
    const restored = composer();
    await restored.setProps({ parentId: 22 });
    expect((restored.get("textarea").element as HTMLTextAreaElement).value).toBe(
      "Reply to another message.",
    );
  });

  it("retries an unconfirmed reply after remount with the same request identity", async () => {
    const wrapper = composer();
    await wrapper.get("textarea").setValue("Check the passage.");
    await wrapper.get("form").trigger("submit");
    const first = vi.mocked(live.pushEvent).mock.calls.at(-1)!;
    first[3]!(new Error("Disconnected"));
    wrapper.unmount();
    const restored = composer();
    await restored.get("form").trigger("submit");
    const retry = vi.mocked(live.pushEvent).mock.calls.at(-1)!;
    expect(retry[1]).toEqual(first[1]);
    retry[2]!({ ok: true });
    await nextTick();
    expect(window.sessionStorage.getItem(storageKey)).toBeNull();
    await restored.get("textarea").setValue("A new reply after sending.");
    restored.unmount();
    expect((composer().get("textarea").element as HTMLTextAreaElement).value).toBe(
      "A new reply after sending.",
    );
  });

  it("does not erase a new draft when an old response arrives after navigation", async () => {
    const wrapper = composer();
    await wrapper.get("textarea").setValue("Old reply.");
    await wrapper.get("form").trigger("submit");
    const first = vi.mocked(live.pushEvent).mock.calls.at(-1)!;
    wrapper.unmount();
    const current = composer();
    await current.get("textarea").setValue("A newer draft.");
    first[2]!({ ok: true });
    current.unmount();
    expect((composer().get("textarea").element as HTMLTextAreaElement).value).toBe(
      "A newer draft.",
    );
  });
});
