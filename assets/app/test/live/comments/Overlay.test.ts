import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { flushPromises, mount } from "@vue/test-utils";
import { defineComponent, nextTick } from "vue";
import { createMockLive, setTestLocale } from "@app/test/setup";
import { openComments } from "@components/comments/commentsHubEvents";
import { paletteGroups, resetPaletteRegistry } from "@shared/command-palette/registry";
import CommentsHubButton from "@components/comments/CommentsHubButton.vue";
import type { HubState } from "@app/live/comments/types";

const live = createMockLive();
vi.mock("@shared/composables/useLive", () => ({ useLive: () => live }));
const { default: Overlay } = await import("@app/live/comments/Overlay.vue");
const state: HubState = {
  threads: [],
  nextCursor: null,
  workspaces: [],
  projects: [],
  filters: {
    workspace_id: "",
    project_id: "",
    tool: "",
    status: "all",
    personal: "all",
    unread: "",
    following: "",
    search: "",
  },
  selectedProjectId: null,
  selectedThreadId: null,
  contextUrl: null,
  error: null,
  conversation: {
    open: false,
    presentation: "workspace",
    threads: [],
    nextCursor: null,
    thread: null,
    messages: [],
    messageNextCursor: null,
    members: [],
    canComment: false,
    selectedSourceId: null,
    error: null,
  },
};
const HubStub = defineComponent({
  template:
    '<div><input id="comments-hub-search" /><button id="review-action">Reply</button></div>',
});
const wrappers: Array<{ unmount: () => void }> = [];

function mountReview() {
  const button = mount(CommentsHubButton, { attachTo: document.body });
  const overlay = mount(Overlay, {
    attachTo: document.body,
    props: { open: false, state, currentUserId: 9 },
    global: { stubs: { Hub: HubStub } },
  });
  wrappers.push(button, overlay);
  return { button, overlay };
}

describe("Comments review overlay", () => {
  beforeEach(() => {
    vi.mocked(live.pushEvent).mockClear();
    setTestLocale("en");
    resetPaletteRegistry();
  });
  afterEach(() => {
    wrappers.splice(0).forEach((wrapper) => wrapper.unmount());
    document.body.innerHTML = "";
  });

  it("opens from an icon action without changing the URL or loading while closed", async () => {
    const { button, overlay } = mountReview();
    const url = window.location.href;
    expect(live.pushEvent).not.toHaveBeenCalled();
    expect(button.find("a").exists()).toBe(false);
    expect(button.text()).toBe("");
    await button.trigger("click");
    expect(live.pushEvent).toHaveBeenCalledWith("hub_open", {}, undefined, expect.any(Function));
    await overlay.setProps({ open: true });
    await flushPromises();
    expect(document.querySelector('[role="dialog"][aria-modal="true"]')).not.toBeNull();
    expect(window.location.href).toBe(url);
    expect(button.attributes("aria-expanded")).toBe("true");
    expect(document.activeElement?.id).toBe("comments-hub-search");
  });

  it("the palette runs the same opening action without a navigation destination", async () => {
    mountReview();
    const command = paletteGroups.value
      .flatMap((group) => group.commands)
      .find((item) => item.id === "global.comments");
    expect(command).not.toHaveProperty("href");
    if (!command || !("run" in command)) throw new Error("Missing comments action");
    await command.run?.();
    expect(live.pushEvent).toHaveBeenCalledWith("hub_open", {}, undefined, expect.any(Function));
  });

  it("blocks background shortcuts and Escape closes while restoring launcher focus", async () => {
    const { button, overlay } = mountReview();
    (button.element as HTMLButtonElement).focus();
    await button.trigger("click");
    await overlay.setProps({ open: true });
    await flushPromises();
    const backgroundShortcut = vi.fn();
    document.addEventListener("keydown", backgroundShortcut);
    try {
      const action = document.getElementById("review-action")!;
      action.dispatchEvent(new KeyboardEvent("keydown", { key: "Delete", bubbles: true }));
      expect(backgroundShortcut).not.toHaveBeenCalled();
      action.dispatchEvent(
        new KeyboardEvent("keydown", { key: "Escape", bubbles: true, cancelable: true }),
      );
      await flushPromises();
      expect(live.pushEvent).toHaveBeenLastCalledWith("hub_close", {});
      expect(backgroundShortcut).not.toHaveBeenCalled();
      await vi.waitFor(() => expect(document.activeElement?.id).toBe("comments-hub-button"));
      expect(button.attributes("aria-expanded")).toBe("false");
    } finally {
      document.removeEventListener("keydown", backgroundShortcut);
    }
  });

  it("closes on a click outside it, and not on a click inside", async () => {
    const { button, overlay } = mountReview();
    await button.trigger("click");
    await overlay.setProps({ open: true });
    await flushPromises();
    vi.mocked(live.pushEvent).mockClear();
    const press = (target: Element) =>
      target.dispatchEvent(new PointerEvent("pointerdown", { bubbles: true, cancelable: true }));
    press(document.getElementById("review-action")!);
    await flushPromises();
    expect(live.pushEvent).not.toHaveBeenCalledWith("hub_close", {});
    // Reka listens for the outside press on the document after a tick.
    await new Promise((resolve) => setTimeout(resolve, 0));
    press(document.body);
    await flushPromises();
    expect(live.pushEvent).toHaveBeenCalledWith("hub_close", {});
    await vi.waitFor(() => expect(document.querySelector('[role="dialog"]')).toBeNull());
  });

  it("allows retrying a disconnected open and does not reopen after a late response", async () => {
    const { overlay } = mountReview();
    openComments();
    vi.mocked(live.pushEvent).mock.calls.at(-1)![3]!(new Error("offline"));
    await nextTick();
    await flushPromises();
    expect(document.body.textContent).toContain("Could not load comments");
    const retry = [...document.querySelectorAll("button")].find(
      (button) => button.textContent === "Retry",
    )!;
    retry.click();
    expect(live.pushEvent).toHaveBeenCalledTimes(2);
    document.querySelector<HTMLButtonElement>('[aria-label="Close comments"]')!.click();
    await overlay.setProps({ open: true });
    await flushPromises();
    expect(document.querySelector('[role="dialog"]')).toBeNull();
  });

  it("reloads an open review when the server reconnects with an idle overlay", async () => {
    const { button, overlay } = mountReview();
    await button.trigger("click");
    await overlay.setProps({ open: true });
    vi.mocked(live.pushEvent).mockClear();
    await overlay.setProps({ open: false });
    expect(live.pushEvent).toHaveBeenCalledWith("hub_open", {}, undefined, expect.any(Function));
  });
});
