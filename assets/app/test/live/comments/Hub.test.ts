import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { mount } from "@vue/test-utils";
import { nextTick } from "vue";
import { createMockLive, setTestLocale } from "@app/test/setup";
import type { HubFilters, HubState, HubThread } from "@app/live/comments/types";

const live = createMockLive();
vi.mock("@shared/composables/useLive", () => ({ useLive: () => live }));
const { default: Hub } = await import("@app/live/comments/Hub.vue");
const passthrough = { template: "<div><slot /></div>" };
const stubs = { Popover: passthrough, PopoverContent: passthrough, PopoverTrigger: passthrough };
const filters: HubFilters = {
  workspace_id: "",
  project_id: "",
  tool: "",
  status: "all",
  personal: "all",
  search: "",
};
const author = { id: 3, display_name: "Ari", avatar_url: null };
const first: HubThread = {
  id: 12,
  project_id: 4,
  project_name: "Lierha",
  project_slug: "lierha",
  workspace_id: 2,
  workspace_name: "Studio",
  workspace_slug: "studio",
  status: "open",
  revision: 2,
  message_count: 2,
  created_at: "2026-09-11T11:00:00Z",
  last_activity_at: "2026-09-12T11:00:00Z",
  resolved_at: null,
  resolved_by: null,
  source: { type: "sheet_canvas", id: 30, label: "The guard", status: "available" },
  context: {
    type: "sheet_block",
    id: "55",
    label: "Motivation",
    status: "available",
    offset: null,
  },
  author,
  preview: "What does the guard know?",
  root_message_id: 21,
  unread: true,
};
const second: HubThread = {
  ...first,
  id: 13,
  project_id: 5,
  project_name: "Archive",
  workspace_id: 3,
  root_message_id: 23,
};

function hubState(thread: HubThread | null = null): HubState {
  return {
    threads: [first, second],
    nextCursor: null,
    filters: { ...filters },
    workspaces: [
      { id: 2, name: "Studio" },
      { id: 3, name: "Personal" },
    ],
    projects: [
      { id: 4, name: "Lierha", workspace_id: 2 },
      { id: 5, name: "Archive", workspace_id: 3 },
    ],
    selectedProjectId: thread?.project_id ?? null,
    selectedThreadId: thread?.id ?? null,
    contextUrl: thread ? "/workspaces/studio/projects/lierha/sheets/30?comment_thread=12" : null,
    error: null,
    conversation: {
      open: true,
      presentation: "workspace",
      threads: [],
      nextCursor: null,
      thread,
      messages: thread
        ? [
            {
              id: thread.root_message_id!,
              thread_id: thread.id,
              parent_id: null,
              body: thread.preview!,
              author,
              mentions: [],
              inserted_at: thread.created_at,
            },
          ]
        : [],
      messageNextCursor: null,
      members: [author],
      canComment: true,
      selectedSourceId: thread?.source.id ?? null,
      error: null,
    },
  };
}

function hub(state = hubState(), currentUserId = 9) {
  return mount(Hub, { props: { state, currentUserId }, global: { stubs } });
}

describe("Comments hub", () => {
  beforeEach(() => {
    vi.mocked(live.pushEvent).mockClear();
    window.sessionStorage.clear();
    setTestLocale("en");
  });
  afterEach(() => vi.useRealTimers());

  it("offers selection and replies only inside an existing conversation", async () => {
    const wrapper = hub();
    expect(wrapper.get("h1").text()).toBe("Comments");
    expect(wrapper.find("textarea").exists()).toBe(false);
    expect(wrapper.text()).not.toContain("New thread");
    await wrapper.get("#comments-hub-thread-12").trigger("click");
    expect(live.pushEvent).toHaveBeenCalledWith(
      "hub_select",
      { thread_id: 12, project_id: 4 },
      expect.any(Function),
      expect.any(Function),
    );
    await wrapper.setProps({ state: hubState(first) });
    await wrapper.get("#hub-comment-body").setValue("She knows the route.");
    await wrapper.get("#hub-comment-send").trigger("submit");
    expect(live.pushEvent).toHaveBeenLastCalledWith(
      "comments_reply",
      expect.objectContaining({ thread_id: 12, parent_id: 21, body: "She knows the route." }),
      expect.any(Function),
      expect.any(Function),
    );
    expect(
      vi.mocked(live.pushEvent).mock.calls.some(([event]) => event === "comments_create"),
    ).toBe(false);
  });

  it("combines a pending search with changed filters and clears the dependent project", async () => {
    vi.useFakeTimers();
    const wrapper = hub({ ...hubState(), filters: { ...filters, project_id: "4" } });
    await wrapper.get("#comments-hub-search").setValue("guard");
    expect(live.pushEvent).not.toHaveBeenCalled();
    await wrapper.get("#comments-hub-workspace").setValue("3");
    expect(live.pushEvent).toHaveBeenLastCalledWith(
      "hub_filter",
      {
        ...filters,
        workspace_id: "3",
        search: "guard",
      },
      expect.any(Function),
      expect.any(Function),
    );
    expect(wrapper.get("#comments-hub-project").text()).toContain("Archive");
    expect(wrapper.get("#comments-hub-project").text()).not.toContain("Lierha");
    await vi.advanceTimersByTimeAsync(300);
    expect(live.pushEvent).toHaveBeenCalledTimes(1);
  });

  it("debounces search and includes tool, status and participation", async () => {
    vi.useFakeTimers();
    const wrapper = hub();
    await wrapper.get("#comments-hub-tool").setValue("flow");
    await wrapper.get("#comments-hub-status").setValue("open");
    await wrapper.get("#comments-hub-personal").setValue("mentioned");
    vi.mocked(live.pushEvent).mockClear();
    await wrapper.get("#comments-hub-search").setValue("guard");
    await vi.advanceTimersByTimeAsync(249);
    expect(live.pushEvent).not.toHaveBeenCalled();
    await vi.advanceTimersByTimeAsync(1);
    expect(live.pushEvent).toHaveBeenCalledWith(
      "hub_filter",
      {
        ...filters,
        tool: "flow",
        status: "open",
        personal: "mentioned",
        search: "guard",
      },
      expect.any(Function),
      expect.any(Function),
    );
  });

  it("uses existing context navigation and retains deleted optional context", () => {
    const thread = { ...first, context: { ...first.context!, status: "unavailable" as const } };
    const wrapper = hub(hubState(thread));
    expect(wrapper.get("#comments-hub-context").attributes("data-phx-link")).toBe("redirect");
    expect(wrapper.get("#comments-hub-context").attributes("href")).toContain("comment_thread=12");
    expect(wrapper.get("#hub-comment-context").text()).toContain("Context removed");
    expect(wrapper.get("#hub-comment-body").isVisible()).toBe(true);
  });

  it("keeps newer typed searches when an earlier server response arrives", async () => {
    vi.useFakeTimers();
    const wrapper = hub();
    await wrapper.get("#comments-hub-search").setValue("gu");
    await vi.advanceTimersByTimeAsync(250);
    const firstRequest = vi.mocked(live.pushEvent).mock.calls.at(-1)!;
    await wrapper.get("#comments-hub-search").setValue("guard");
    await vi.advanceTimersByTimeAsync(250);
    const latestRequest = vi.mocked(live.pushEvent).mock.calls.at(-1)!;
    await wrapper.setProps({ state: { ...hubState(), filters: { ...filters, search: "gu" } } });
    firstRequest[2]!({});
    await nextTick();
    expect((wrapper.get("#comments-hub-search").element as HTMLInputElement).value).toBe("guard");
    expect(wrapper.get("#comments-hub-list").attributes("aria-busy")).toBe("true");
    await wrapper.setProps({ state: { ...hubState(), filters: { ...filters, search: "guard" } } });
    latestRequest[2]!({});
    await nextTick();
    expect(wrapper.get("#comments-hub-list").attributes("aria-busy")).toBe("false");
    await wrapper.setProps({
      state: { ...hubState(), filters: { ...filters, search: "previous" } },
    });
    expect((wrapper.get("#comments-hub-search").element as HTMLInputElement).value).toBe(
      "previous",
    );
  });

  it("preserves a newer search before its debounce while the previous request completes", async () => {
    vi.useFakeTimers();
    const wrapper = hub();
    await wrapper.get("#comments-hub-search").setValue("gu");
    await vi.advanceTimersByTimeAsync(250);
    const request = vi.mocked(live.pushEvent).mock.calls.at(-1)!;
    await wrapper.get("#comments-hub-search").setValue("guardian");
    await wrapper.setProps({ state: { ...hubState(), filters: { ...filters, search: "gu" } } });
    request[2]!({});
    await nextTick();
    expect((wrapper.get("#comments-hub-search").element as HTMLInputElement).value).toBe(
      "guardian",
    );
  });

  it("waits for matching canonical filters when acknowledgement precedes the prop update", async () => {
    vi.useFakeTimers();
    const wrapper = hub();
    await wrapper.get("#comments-hub-search").setValue(" guard ");
    await vi.advanceTimersByTimeAsync(250);
    vi.mocked(live.pushEvent).mock.calls.at(-1)![2]!({});
    await nextTick();
    expect((wrapper.get("#comments-hub-search").element as HTMLInputElement).value).toBe(" guard ");
    await wrapper.setProps({ state: { ...hubState(), filters: { ...filters, search: "guard" } } });
    expect((wrapper.get("#comments-hub-search").element as HTMLInputElement).value).toBe("guard");
  });

  it("reports disconnected filtering and selection and permits retrying the same input", async () => {
    const wrapper = hub();
    await wrapper.get("#comments-hub-status").setValue("open");
    vi.mocked(live.pushEvent).mock.calls.at(-1)![3]!(new Error("Disconnected"));
    await nextTick();
    expect(wrapper.get('[role="alert"]').text()).toContain("Could not update the search");
    expect((wrapper.get("#comments-hub-status").element as HTMLSelectElement).value).toBe("open");
    expect(wrapper.get("#comments-hub-list").attributes("aria-busy")).toBe("false");
    await wrapper.get('form[role="search"]').trigger("submit");
    expect(vi.mocked(live.pushEvent).mock.calls.at(-1)![1]).toMatchObject({ status: "open" });
    await wrapper.get("#comments-hub-thread-12").trigger("click");
    expect(wrapper.get("#comments-hub-thread-12").attributes("aria-busy")).toBe("true");
    vi.mocked(live.pushEvent).mock.calls.at(-1)![3]!(new Error("Disconnected"));
    await nextTick();
    expect(wrapper.get('[role="alert"]').text()).toContain("Could not open the conversation");
    expect(wrapper.get("#comments-hub-thread-12").attributes("aria-busy")).toBe("false");
  });

  it("preserves overlong Unicode searches and explains the error without widening the query", async () => {
    vi.useFakeTimers();
    const wrapper = hub();
    const query = "á".repeat(101);
    await wrapper.get("#comments-hub-search").setValue(query);
    await vi.advanceTimersByTimeAsync(250);
    expect(live.pushEvent).not.toHaveBeenCalled();
    expect(wrapper.get('[role="alert"]').text()).toContain("This search is too long");
    await wrapper.setProps({ state: hubState() });
    expect((wrapper.get("#comments-hub-search").element as HTMLInputElement).value).toBe(query);
    await wrapper.get("#comments-hub-search").setValue("á".repeat(100));
    await vi.advanceTimersByTimeAsync(250);
    expect(vi.mocked(live.pushEvent).mock.calls.at(-1)![1]).toMatchObject({
      search: "á".repeat(100),
    });
  });

  it("keeps unavailable conversations readable without context or reply actions", () => {
    const thread = { ...first, source: { ...first.source, status: "unavailable" as const } };
    const wrapper = hub(hubState(thread));
    expect(wrapper.text()).toContain(first.preview);
    expect(wrapper.find("#comments-hub-context").exists()).toBe(false);
    expect(wrapper.find("#hub-comment-status").exists()).toBe(false);
    expect(wrapper.get("#hub-comment-body").attributes("disabled")).toBeDefined();
  });

  it("isolates reply drafts by user, project, thread and parent and restores them on return", async () => {
    const wrapper = hub(hubState(first));
    await wrapper.get("#hub-comment-body").setValue("Remember this detail.");
    await wrapper.setProps({ state: hubState(second) });
    expect((wrapper.get("textarea").element as HTMLTextAreaElement).value).toBe("");
    await wrapper.get("textarea").setValue("A different project.");
    await wrapper.setProps({ state: hubState(first) });
    expect((wrapper.get("textarea").element as HTMLTextAreaElement).value).toBe(
      "Remember this detail.",
    );
    await wrapper.setProps({ currentUserId: 10 });
    expect((wrapper.get("textarea").element as HTMLTextAreaElement).value).toBe("");
    wrapper.unmount();
    const restored = hub(hubState(first));
    expect((restored.get("textarea").element as HTMLTextAreaElement).value).toBe(
      "Remember this detail.",
    );
  });

  it("restores independent list and conversation scroll positions on returning", async () => {
    const wrapper = hub(hubState(first));
    const list = wrapper.get("#comments-hub-list");
    const detail = wrapper.get("#comments-hub-detail");
    list.element.scrollTop = 280;
    detail.element.scrollTop = 340;
    await list.trigger("scroll");
    await detail.trigger("scroll");
    wrapper.unmount();
    const restored = hub(hubState(first));
    await nextTick();
    expect(restored.get("#comments-hub-list").element.scrollTop).toBe(280);
    expect(restored.get("#comments-hub-detail").element.scrollTop).toBe(340);
    await restored.setProps({ state: hubState(second) });
    expect(restored.get("#comments-hub-detail").element.scrollTop).toBe(0);
  });

  it("restores an explicit reply target and its draft even when the older message is not loaded", async () => {
    const selectedState = hubState(first);
    selectedState.conversation.messages.push({
      id: 22,
      thread_id: first.id,
      parent_id: first.root_message_id!,
      body: "An earlier answer.",
      author,
      mentions: [],
      inserted_at: first.created_at,
    });
    const wrapper = hub(selectedState);
    await wrapper.get("#hub-comment-message-22 button").trigger("click");
    await wrapper.get("#hub-comment-body").setValue("A reply to the earlier answer.");
    await wrapper.setProps({ state: hubState(second) });
    expect((wrapper.get("#hub-comment-body").element as HTMLTextAreaElement).value).toBe("");
    await wrapper.setProps({ state: hubState(first) });
    expect(wrapper.text()).toContain("Reply to an earlier message");
    expect((wrapper.get("#hub-comment-body").element as HTMLTextAreaElement).value).toBe(
      "A reply to the earlier answer.",
    );
    wrapper.unmount();

    const restored = hub(hubState(first));
    expect(restored.text()).toContain("Reply to an earlier message");
    await restored.get("#hub-comment-send").trigger("submit");
    const request = vi.mocked(live.pushEvent).mock.calls.at(-1)!;
    expect(request[1]).toMatchObject({
      thread_id: 12,
      parent_id: 22,
      body: "A reply to the earlier answer.",
    });
    request[2]!({ ok: true });
    await nextTick();
    expect(restored.text()).not.toContain("Reply to an earlier message");
    expect(
      window.sessionStorage.getItem("storyarn:comments-hub:draft:9:4:12:reply-target"),
    ).toBeNull();
  });

  it("validates restored reply targets against the current thread and source", async () => {
    const marker = {
      parentId: 22,
      threadId: first.id,
      sourceId: first.source.id,
      sourceType: first.source.type,
    };
    for (const invalid of [
      { ...marker, parentId: -1 },
      { ...marker, parentId: 1.5 },
      { ...marker, threadId: second.id },
      { ...marker, sourceId: first.source.id + 1 },
      { ...marker, sourceType: "flow_canvas" },
    ]) {
      window.sessionStorage.clear();
      window.sessionStorage.setItem(
        "storyarn:comments-hub:draft:9:4:12:reply-target",
        JSON.stringify(invalid),
      );
      const wrapper = hub(hubState(first));
      expect(wrapper.text()).not.toContain("Reply to an earlier message");
      await wrapper.get("#hub-comment-body").setValue("A regular reply.");
      await wrapper.get("#hub-comment-send").trigger("submit");
      expect(vi.mocked(live.pushEvent).mock.calls.at(-1)![1]).toMatchObject({
        parent_id: first.root_message_id,
      });
      wrapper.unmount();
    }
  });

  it("shows a recoverable empty search without a creation action", async () => {
    const wrapper = hub({ ...hubState(), threads: [], filters: { ...filters, search: "missing" } });
    expect(wrapper.get("#comments-hub-empty").text()).toContain("No matching conversations");
    await wrapper.get("#comments-hub-reset").trigger("click");
    expect(live.pushEvent).toHaveBeenLastCalledWith(
      "hub_filter",
      filters,
      expect.any(Function),
      expect.any(Function),
    );
    expect(wrapper.find("textarea").exists()).toBe(false);
  });

  it("translates the complete hub in Spanish", () => {
    setTestLocale("es");
    const wrapper = hub(hubState(first));
    expect(wrapper.get("h1").text()).toBe("Comentarios");
    expect(wrapper.get("#comments-hub-context").text()).toBe("Ver en contexto");
    expect(wrapper.text()).not.toContain("comments_hub.");
  });
});
