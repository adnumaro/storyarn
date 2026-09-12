import { describe, expect, it, vi } from "vitest";
import { flushPromises, mount } from "@vue/test-utils";
import Panel from "@app/live/ideation/ReferencesPanel.vue";
import type {
  BrainstormingReference,
  ReferenceTarget,
  ReferencesPanelState,
} from "@app/live/ideation/referenceTypes";

const target: ReferenceTarget = {
  id: 8,
  type: "sheet",
  name: "Current hero",
  href: "/workspaces/team/projects/game/sheets/8",
  fields: [{ key: "description", value: "Current context", truncated: false }],
};
const reference: BrainstormingReference = {
  id: 4,
  version: 2,
  relation: "origin",
  targetType: "sheet",
  targetId: 8,
  status: "changed",
  base: {
    name: "Original hero",
    fields: [{ key: "description", value: "Original context", truncated: false }],
  },
  current: target,
  capturedAt: "2026-09-12T10:00:00Z",
};
const state: ReferencesPanelState = {
  open: true,
  context: "reference-context-1",
  ideaId: null,
  focusedReferenceId: null,
  items: [],
  nextCursor: null,
  results: [],
  searched: false,
  historyReferenceId: null,
  history: [],
  canEdit: true,
  error: null,
};

function panel(overrides: Partial<ReferencesPanelState> = {}, disconnected = false) {
  const pushEvent = disconnected ? vi.fn().mockRejectedValue(new Error("Disconnected")) : vi.fn();
  const wrapper = mount(Panel, {
    attachTo: document.body,
    props: { state: { ...state, ...overrides }, epoch: "epoch-1", sessionId: 12 },
    global: {
      provide: {
        _live_vue: {
          pushEvent,
          handleEvent: vi.fn(),
          removeHandleEvent: vi.fn(),
          upload: vi.fn(),
          ...(disconnected ? { liveSocket: {} } : {}),
        },
      },
      stubs: {
        Sidebar: { template: "<aside><slot name='header'/><slot/></aside>" },
        ConfirmDialog: {
          props: ["open", "title", "description", "confirmText", "pending"],
          emits: ["confirm", "update:open"],
          template:
            "<section v-if='open' role='dialog'><h2>{{ title }}</h2><p>{{ description }}</p><button id='reference-confirm-test' :disabled='pending' @click='$emit(\"confirm\")'>{{ confirmText }}</button></section>",
        },
      },
    },
  });
  return { wrapper, pushEvent };
}

describe("Brainstorming references", () => {
  it("focuses and expands the requested reference without changing focus on an ordinary refresh", async () => {
    const scroll = vi.spyOn(Element.prototype, "scrollIntoView");
    const focusedState = {
      ...state,
      focusedReferenceId: reference.id,
      items: [reference, { ...reference, id: 9, relation: "reference" as const }],
      nextCursor: 9,
    };
    const { wrapper, pushEvent } = panel(focusedState);
    await flushPromises();
    const article = wrapper.get("#brainstorming-reference-4");
    expect(wrapper.findAll("article")[0].element).toBe(article.element);
    expect(document.activeElement).toBe(article.element);
    expect(article.attributes("data-focused")).toBe("true");
    expect(
      article.findAll("details").every((details) => (details.element as HTMLDetailsElement).open),
    ).toBe(true);
    expect(wrapper.get("#brainstorming-reference-9 details").attributes("open")).toBeUndefined();
    expect(scroll).toHaveBeenCalledWith({ block: "nearest" });
    expect(pushEvent).not.toHaveBeenCalled();

    const search = wrapper.get<HTMLInputElement>("#brainstorming-reference-query");
    search.element.focus();
    (article.get("details").element as HTMLDetailsElement).open = false;
    await wrapper.setProps({ state: { ...focusedState, items: [{ ...reference, version: 3 }] } });
    await flushPromises();
    expect(document.activeElement).toBe(search.element);
    expect((article.get("details").element as HTMLDetailsElement).open).toBe(false);

    await wrapper.setProps({ state: { ...focusedState, context: "reopened-reference-context" } });
    await flushPromises();
    const reopened = wrapper.get("#brainstorming-reference-4");
    expect(document.activeElement).toBe(reopened.element);
    expect(
      reopened.findAll("details").every((details) => (details.element as HTMLDetailsElement).open),
    ).toBe(true);
    await wrapper.get("#brainstorming-reference-load-more").trigger("click");
    expect(pushEvent.mock.calls[0][0]).toBe("references_load_more");
    expect(pushEvent.mock.calls[0][1]).toMatchObject({
      reference_context: "reopened-reference-context",
    });
    wrapper.unmount();
    scroll.mockRestore();
  });

  it("removes expanded saved and current previews when the focused target becomes unavailable", async () => {
    const { wrapper } = panel({ items: [reference], focusedReferenceId: reference.id });
    await flushPromises();
    expect(wrapper.get("#brainstorming-reference-4").findAll("details[open]")).toHaveLength(2);
    await wrapper.setProps({
      state: {
        ...state,
        focusedReferenceId: reference.id,
        items: [
          { ...reference, status: "unavailable", base: null, current: null, capturedAt: null },
        ],
      },
    });
    expect(wrapper.find("details").exists()).toBe(false);
    expect(wrapper.find("a").exists()).toBe(false);
    expect(wrapper.text()).not.toContain("Original hero");
    expect(wrapper.text()).not.toContain("Current hero");
    expect(wrapper.text()).toContain("Content unavailable");
    wrapper.unmount();
  });

  it("searches explicitly using the current board and source context", async () => {
    const { wrapper, pushEvent } = panel();
    expect(pushEvent).not.toHaveBeenCalled();
    expect(wrapper.text()).toContain("not a full copy");
    await wrapper.get("#brainstorming-reference-query").setValue("Hero");
    await wrapper.get("#brainstorming-reference-search-form").trigger("submit");
    expect(pushEvent.mock.calls[0][0]).toBe("references_search");
    expect(pushEvent.mock.calls[0][1]).toMatchObject({
      type: "sheet",
      search: "Hero",
      epoch: "epoch-1",
      session_id: 12,
      reference_context: "reference-context-1",
    });
    pushEvent.mock.calls[0][2]({ status: "ok" });
    await wrapper.vm.$nextTick();
    expect(wrapper.get("#brainstorming-reference-search").attributes("disabled")).toBeUndefined();
    wrapper.unmount();
  });

  it("keeps an add request identity after an uncertain error and never copies target content", async () => {
    const { wrapper, pushEvent } = panel({ results: [target], searched: true });
    await wrapper.get("#brainstorming-reference-add-sheet-8").trigger("click");
    const [event, request, reply] = pushEvent.mock.calls[0];
    expect(event).toBe("references_add");
    expect(request).toMatchObject({ target_type: "sheet", target_id: 8, relation: "reference" });
    expect(request.request_key).toEqual(expect.any(String));
    expect(request).not.toHaveProperty("body");
    expect(request).not.toHaveProperty("context");
    reply({ status: "error", code: "unavailable" });
    await wrapper.vm.$nextTick();
    await wrapper.get("#brainstorming-reference-add-sheet-8").trigger("click");
    expect(pushEvent.mock.calls[1][1].request_key).toBe(request.request_key);
    wrapper.unmount();
  });

  it("shows saved and current metadata separately and only refreshes after confirmation", async () => {
    const { wrapper, pushEvent } = panel({ items: [reference] });
    expect(wrapper.text()).toContain("Original context");
    expect(wrapper.text()).toContain("Current context");
    expect(wrapper.get("a").attributes("href")).toBe(target.href);
    expect(pushEvent).not.toHaveBeenCalled();
    await wrapper.get("#brainstorming-reference-refresh-4").trigger("click");
    expect(pushEvent).not.toHaveBeenCalled();
    expect(wrapper.get("[role=dialog]").text()).toContain("does not change the original content");
    await wrapper.get("#reference-confirm-test").trigger("click");
    expect(pushEvent.mock.calls[0][0]).toBe("references_refresh");
    expect(pushEvent.mock.calls[0][1]).toMatchObject({ reference_id: 4, version: 2 });
    pushEvent.mock.calls[0][2]({ status: "ok" });
    await wrapper.vm.$nextTick();
    expect(wrapper.find("[role=dialog]").exists()).toBe(false);
    wrapper.unmount();
  });

  it("has no write controls for readers and no metadata or navigation for unavailable targets", () => {
    const { wrapper } = panel({
      canEdit: false,
      items: [
        {
          ...reference,
          status: "unavailable",
          current: null,
          base: null,
          targetId: null,
          capturedAt: null,
        },
      ],
    });
    expect(wrapper.find("form").exists()).toBe(false);
    expect(wrapper.find("#brainstorming-reference-remove-4").exists()).toBe(false);
    expect(wrapper.find("#brainstorming-reference-history-4").exists()).toBe(false);
    expect(wrapper.find("a").exists()).toBe(false);
    expect(wrapper.text()).not.toContain("Original context");
    expect(wrapper.text()).not.toContain("Current hero");
    expect(wrapper.text()).toContain("Content unavailable");
    wrapper.unmount();
  });

  it("discards callbacks and confirmation state when the selected source changes", async () => {
    const { wrapper, pushEvent } = panel({ items: [reference] });
    await wrapper.get("#brainstorming-reference-remove-4").trigger("click");
    await wrapper.get("#reference-confirm-test").trigger("click");
    const late = pushEvent.mock.calls[0][2];
    await wrapper.setProps({ state: { ...state, context: "reference-context-2", ideaId: 25 } });
    late({ status: "error", code: "stale_reference" });
    await wrapper.vm.$nextTick();
    expect(wrapper.find("[role=alert]").exists()).toBe(false);
    expect(wrapper.find("[role=dialog]").exists()).toBe(false);
    expect(wrapper.text()).not.toContain("Original hero");
    wrapper.unmount();
  });

  it("releases pending controls on disconnection without throwing or sending a write", async () => {
    const warning = vi.spyOn(console, "warn").mockImplementation(() => {});
    const { wrapper, pushEvent } = panel({}, true);
    await wrapper.get("#brainstorming-reference-search-form").trigger("submit");
    await flushPromises();
    expect(pushEvent.mock.calls[0][0]).toBe("references_search");
    expect(wrapper.get("[role=alert]").text()).toContain("Connection interrupted");
    expect(wrapper.get("#brainstorming-reference-search").attributes("disabled")).toBeUndefined();
    wrapper.unmount();
    warning.mockRestore();
  });
});
