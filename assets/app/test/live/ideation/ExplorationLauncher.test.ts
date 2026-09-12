import { afterEach, describe, expect, it, vi } from "vitest";
import { flushPromises, mount } from "@vue/test-utils";
import Launcher from "@app/live/ideation/ExplorationLauncher.vue";
import type { ExplorationLauncherState } from "@app/live/ideation/explorationTypes";
import { setTestLocale } from "../../setup";

const state: ExplorationLauncherState = {
  open: true,
  context: "preview-1",
  target: {
    id: 8,
    type: "sheet",
    name: "Hero",
    href: "/workspaces/team/projects/game/sheets/8",
    fields: [{ key: "description", value: "Current hero description", truncated: false }],
  },
  linked: [],
  available: [],
  linkedNext: null,
  availableNext: null,
  linkedPrevious: false,
  availablePrevious: false,
  linkedCursor: null,
  availableCursor: null,
  canEdit: true,
  error: null,
};

function launcher(
  overrides: Partial<ExplorationLauncherState> = {},
  disconnected = false,
  realDialog = false,
) {
  const pushEvent = disconnected ? vi.fn().mockRejectedValue(new Error("Disconnected")) : vi.fn();
  const wrapper = mount(Launcher, {
    props: { state: { ...state, ...overrides }, sourceKey: "sheet:8" },
    ...(realDialog ? { attachTo: document.body } : {}),
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
      stubs: realDialog
        ? {}
        : {
            Dialog: { props: ["open"], template: "<div v-if='open'><slot /></div>" },
            DialogContent: { template: "<section role='dialog'><slot /></section>" },
            DialogTitle: { template: "<h2><slot /></h2>" },
            DialogDescription: { template: "<p><slot /></p>" },
          },
    },
  });
  return { wrapper, pushEvent };
}

afterEach(() => setTestLocale("en"));

describe("Contextual exploration launcher", () => {
  it("opens explicitly with the current source and does not create or search on mount", async () => {
    const { wrapper, pushEvent } = launcher({ open: false, target: null });
    expect(pushEvent).not.toHaveBeenCalled();
    expect(wrapper.find("#exploration-dialog").exists()).toBe(false);
    await wrapper.get("#explore-changes").trigger("click");
    expect(pushEvent.mock.calls[0][0]).toBe("exploration_open");
    expect(pushEvent.mock.calls[0][1]).toEqual({
      source_key: "sheet:8",
      exploration_context: "preview-1",
    });
    expect(wrapper.get("#explore-changes").attributes("disabled")).toBeDefined();
    wrapper.unmount();
  });

  it("shows the bounded preview and creates only after the form is submitted", async () => {
    const { wrapper, pushEvent } = launcher();
    expect(wrapper.get("#exploration-context-preview").text()).toContain(
      "Current hero description",
    );
    expect(wrapper.text()).toContain("does not create an editable copy or a playable version");
    expect(wrapper.get<HTMLInputElement>("#exploration-title").element.value).toBe("Explore Hero");
    expect(pushEvent).not.toHaveBeenCalled();
    await wrapper.get("#exploration-title").setValue("  Another motive  ");
    await wrapper.get("#exploration-objective").setValue("  Why does the hero leave?  ");
    await wrapper.get("#exploration-create-form").trigger("submit");
    expect(pushEvent.mock.calls[0][0]).toBe("exploration_create");
    expect(pushEvent.mock.calls[0][1]).toEqual({
      title: "Another motive",
      objective: "Why does the hero leave?",
      source_key: "sheet:8",
      exploration_context: "preview-1",
      request_key: expect.any(String),
    });
    await wrapper.get("#exploration-create-form").trigger("submit");
    expect(pushEvent).toHaveBeenCalledTimes(1);
    expect(wrapper.get("#exploration-close").attributes("disabled")).toBeDefined();
    wrapper.unmount();
  });

  it("preserves the request identity on retry but gives changed input a new identity", async () => {
    const { wrapper, pushEvent } = launcher();
    await wrapper.get("#exploration-create-form").trigger("submit");
    const first = pushEvent.mock.calls[0];
    first[2]({ status: "error", code: "unavailable" });
    await wrapper.vm.$nextTick();
    await wrapper.get("#exploration-create-form").trigger("submit");
    expect(pushEvent.mock.calls[1][1].request_key).toBe(first[1].request_key);
    pushEvent.mock.calls[1][2]({ status: "error", code: "unavailable" });
    await wrapper.vm.$nextTick();
    await wrapper.get("#exploration-title").setValue("A different question");
    await wrapper.get("#exploration-create-form").trigger("submit");
    expect(pushEvent.mock.calls[2][1].request_key).not.toBe(first[1].request_key);
    wrapper.unmount();
  });

  it("preserves an uncertain create identity when its source overview changes before retry", async () => {
    const { wrapper, pushEvent } = launcher();
    await wrapper.get("#exploration-create-form").trigger("submit");
    const original = pushEvent.mock.calls[0][1];
    pushEvent.mock.calls[0][2]({ status: "error", code: "unavailable" });
    await wrapper.vm.$nextTick();

    await wrapper.setProps({
      state: {
        ...state,
        context: "preview-2",
        error: "stale_context",
        target: { ...state.target!, name: "Changed after the uncertain save" },
      },
    });
    await wrapper.get("#exploration-create-form").trigger("submit");
    expect(pushEvent.mock.calls[1][1]).toMatchObject({
      title: original.title,
      objective: original.objective,
      request_key: original.request_key,
      exploration_context: "preview-2",
    });
    wrapper.unmount();
  });

  it("retains edited input while the server refreshes a stale preview", async () => {
    const { wrapper, pushEvent } = launcher();
    await wrapper.get("#exploration-title").setValue("My exploration");
    await wrapper.get("#exploration-create-form").trigger("submit");
    await wrapper.setProps({
      state: {
        ...state,
        context: "preview-2",
        error: "stale_context",
        target: { ...state.target!, name: "Updated hero" },
      },
    });
    pushEvent.mock.calls[0][2]({ status: "error", code: "stale_context" });
    await wrapper.vm.$nextTick();
    expect(wrapper.get("#exploration-context-preview").text()).toContain("Updated hero");
    expect(wrapper.get<HTMLInputElement>("#exploration-title").element.value).toBe(
      "My exploration",
    );
    expect(wrapper.get("[role=alert]").text()).toContain("Review the current preview");
    await wrapper.get("#exploration-create-form").trigger("submit");
    expect(pushEvent.mock.calls[1][1].exploration_context).toBe("preview-2");
    wrapper.unmount();
  });

  it("searches and paginates existing sessions without linking until explicitly selected", async () => {
    const { wrapper, pushEvent } = launcher({
      linked: [{ id: 10, title: "Already exploring", status: "open" }],
      available: [
        { id: 10, title: "Already exploring", status: "open" },
        { id: 11, title: "Alternative ending", status: "open" },
        { id: 12, title: "Archived ideas", status: "archived" },
      ],
      availableNext: 13,
    });
    await wrapper.get("#exploration-link-existing").trigger("click");
    expect(pushEvent).not.toHaveBeenCalled();
    expect(wrapper.get("#exploration-link-10").attributes("disabled")).toBeDefined();
    expect(wrapper.get("#exploration-link-12").attributes("disabled")).toBeDefined();
    await wrapper.get("#exploration-search-query").setValue("ending");
    await wrapper.get("#exploration-search-form").trigger("submit");
    expect(pushEvent.mock.calls[0][0]).toBe("exploration_search");
    expect(pushEvent.mock.calls[0][1].search).toBe("ending");
    pushEvent.mock.calls[0][2]({ status: "ok" });
    await wrapper.vm.$nextTick();
    await wrapper.get("#exploration-available-more").trigger("click");
    expect(pushEvent.mock.calls[1][0]).toBe("exploration_load_more");
    expect(pushEvent.mock.calls[1][1]).toMatchObject({ list: "available", cursor: 13 });
    pushEvent.mock.calls[1][2]({ status: "ok" });
    await wrapper.vm.$nextTick();
    await wrapper.get("#exploration-link-11").trigger("click");
    expect(pushEvent.mock.calls[2][0]).toBe("exploration_link");
    expect(pushEvent.mock.calls[2][1]).toMatchObject({
      session_id: 11,
      request_key: expect.any(String),
    });
    expect(pushEvent.mock.calls[2][1]).not.toHaveProperty("target");
    wrapper.unmount();
  });

  it("offers readers linked sessions and reauthorizes resume through the server", async () => {
    const { wrapper, pushEvent } = launcher({
      canEdit: false,
      linked: [
        { id: 11, title: "Earlier alternatives", status: "archived", contextStatus: "changed" },
      ],
      linkedNext: 7,
    });
    expect(wrapper.get("#explore-changes").text()).toBe("Explorations");
    expect(wrapper.find("form").exists()).toBe(false);
    expect(wrapper.find("#exploration-link-existing").exists()).toBe(false);
    expect(wrapper.find("a").exists()).toBe(false);
    expect(wrapper.text()).toContain("Overview changed since linking");
    expect(wrapper.get("#exploration-resume-11").text()).toContain("View");
    await wrapper.get("#exploration-resume-11").trigger("click");
    expect(pushEvent.mock.calls[0][0]).toBe("exploration_resume");
    expect(pushEvent.mock.calls[0][1]).toMatchObject({ session_id: 11, source_key: "sheet:8" });
    pushEvent.mock.calls[0][2]({ status: "ok" });
    await wrapper.vm.$nextTick();
    await wrapper.get("#exploration-linked-more").trigger("click");
    expect(pushEvent.mock.calls[1][1]).toMatchObject({ list: "linked", cursor: 7 });
    wrapper.unmount();
  });

  it("returns from the final linked page without accumulating rows or losing the form", async () => {
    const firstPage: ExplorationLauncherState = {
      ...state,
      linked: [{ id: 30, title: "Recent exploration", status: "open" }],
      linkedNext: 20,
    };
    const { wrapper, pushEvent } = launcher(firstPage);
    await wrapper.get("#exploration-title").setValue("A new motivation");
    await wrapper.get("#exploration-objective").setValue("What changed?");
    await wrapper.get("#exploration-linked-more").trigger("click");
    await wrapper.setProps({
      state: {
        ...state,
        linked: [{ id: 10, title: "Older exploration", status: "open" }],
        linkedPrevious: true,
        linkedCursor: 20,
      },
    });
    pushEvent.mock.calls[0][2]({ status: "ok" });
    await wrapper.vm.$nextTick();
    expect(wrapper.find("#exploration-resume-30").exists()).toBe(false);
    expect(wrapper.find("#exploration-resume-10").exists()).toBe(true);
    expect(wrapper.find("#exploration-linked-more").exists()).toBe(false);
    await wrapper.get("#exploration-linked-previous").trigger("click");
    expect(pushEvent.mock.calls[1][0]).toBe("exploration_load_previous");
    expect(pushEvent.mock.calls[1][1]).toMatchObject({ list: "linked", cursor: 20 });
    expect(wrapper.get("#exploration-linked-previous").attributes("disabled")).toBeDefined();
    await wrapper.setProps({ state: firstPage });
    pushEvent.mock.calls[1][2]({ status: "ok" });
    await wrapper.vm.$nextTick();
    expect(wrapper.find("#exploration-linked-previous").exists()).toBe(false);
    expect(wrapper.find("#exploration-resume-10").exists()).toBe(false);
    expect(wrapper.get<HTMLInputElement>("#exploration-title").element.value).toBe(
      "A new motivation",
    );
    expect(wrapper.get<HTMLTextAreaElement>("#exploration-objective").element.value).toBe(
      "What changed?",
    );
    wrapper.unmount();
  });

  it("keeps the existing-session search while returning to its previous page", async () => {
    const { wrapper, pushEvent } = launcher({ availableNext: 20 });
    await wrapper.get("#exploration-link-existing").trigger("click");
    await wrapper.get("#exploration-search-query").setValue("ending");
    await wrapper.get("#exploration-search-form").trigger("submit");
    pushEvent.mock.calls[0][2]({ status: "ok" });
    await wrapper.vm.$nextTick();
    await wrapper.get("#exploration-available-more").trigger("click");
    await wrapper.setProps({
      state: { ...state, availablePrevious: true, availableCursor: 20 },
    });
    pushEvent.mock.calls[1][2]({ status: "ok" });
    await wrapper.vm.$nextTick();
    await wrapper.get("#exploration-available-previous").trigger("click");
    expect(pushEvent.mock.calls[2][0]).toBe("exploration_load_previous");
    expect(pushEvent.mock.calls[2][1]).toMatchObject({ list: "available", cursor: 20 });
    await wrapper.setProps({ state: { ...state, availableNext: 20 } });
    pushEvent.mock.calls[2][2]({ status: "ok" });
    await wrapper.vm.$nextTick();
    expect(wrapper.get<HTMLInputElement>("#exploration-search-query").element.value).toBe("ending");
    expect(wrapper.find("#exploration-available-previous").exists()).toBe(false);
    wrapper.unmount();
  });

  it.each([
    ["en", "Reopen this exploration before linking content to it."],
    ["es", "Reabre esta exploración antes de vincular contenido."],
  ] as const)("explains an archived-session race in %s", async (locale, message) => {
    setTestLocale(locale);
    const { wrapper, pushEvent } = launcher({
      available: [{ id: 11, title: "Alternative ending", status: "open" }],
    });
    await wrapper.get("#exploration-link-existing").trigger("click");
    await wrapper.get("#exploration-link-11").trigger("click");
    pushEvent.mock.calls[0][2]({ status: "error", code: "session_archived" });
    await wrapper.vm.$nextTick();
    expect(wrapper.get("[role=alert]").text()).toBe(message);
    expect(wrapper.get("#exploration-link-11").attributes("disabled")).toBeUndefined();
    wrapper.unmount();
  });

  it("removes mutation controls when the source is unavailable", () => {
    const { wrapper } = launcher({ target: null });
    expect(wrapper.find("form").exists()).toBe(false);
    expect(wrapper.find("#exploration-context-preview").exists()).toBe(false);
    expect(wrapper.text()).not.toContain("Current hero description");
    expect(wrapper.text()).toContain("This content is no longer available");
    wrapper.unmount();
  });

  it("rejects blank titles and resets draft state and old callbacks after source navigation", async () => {
    const { wrapper, pushEvent } = launcher();
    await wrapper.get("#exploration-title").setValue(" ");
    await wrapper.get("#exploration-create-form").trigger("submit");
    expect(pushEvent).not.toHaveBeenCalled();
    await wrapper.get("#exploration-title").setValue("Old draft");
    await wrapper.get("#exploration-create-form").trigger("submit");
    const late = pushEvent.mock.calls[0][2];
    await wrapper.setProps({
      sourceKey: "flow:9",
      state: {
        ...state,
        context: "preview-2",
        target: { ...state.target!, id: 9, type: "flow", name: "Ending" },
      },
    });
    late({ status: "error", code: "unavailable" });
    await wrapper.vm.$nextTick();
    expect(wrapper.find("[role=alert]").exists()).toBe(false);
    expect(wrapper.get<HTMLInputElement>("#exploration-title").element.value).toBe(
      "Explore Ending",
    );
    expect(wrapper.get("#exploration-create").attributes("disabled")).toBeUndefined();
    wrapper.unmount();
  });

  it("releases controls after an offline failure and reports opening failures outside the dialog", async () => {
    const warning = vi.spyOn(console, "warn").mockImplementation(() => {});
    const { wrapper, pushEvent } = launcher({ open: false }, true);
    await wrapper.get("#explore-changes").trigger("click");
    await flushPromises();
    expect(pushEvent.mock.calls[0][0]).toBe("exploration_open");
    expect(wrapper.get("[role=alert]").text()).toContain("Connection interrupted");
    expect(wrapper.get("#explore-changes").attributes("disabled")).toBeUndefined();
    wrapper.unmount();
    warning.mockRestore();
  });

  it("uses Spanish copy and remains inert when the feature is disabled", async () => {
    setTestLocale("es");
    const { wrapper, pushEvent } = launcher();
    expect(wrapper.get("#explore-changes").text()).toBe("Explorar cambios");
    expect(wrapper.get<HTMLInputElement>("#exploration-title").element.value).toBe("Explorar Hero");
    await wrapper.setProps({ enabled: false });
    expect(wrapper.find("#explore-changes").exists()).toBe(false);
    expect(wrapper.find("#exploration-dialog").exists()).toBe(false);
    expect(pushEvent).not.toHaveBeenCalled();
    wrapper.unmount();
  });

  it("keeps Escape fenced while saving and restores keyboard focus after the server closes the dialog", async () => {
    const { wrapper, pushEvent } = launcher({ open: false }, false, true);
    const trigger = wrapper.get<HTMLButtonElement>("#explore-changes");
    trigger.element.focus();
    await trigger.trigger("click");
    expect(pushEvent.mock.calls[0][0]).toBe("exploration_open");
    await wrapper.setProps({ state: { ...state, context: "opened-preview" } });
    pushEvent.mock.calls[0][2]({ status: "ok" });
    await flushPromises();

    const input = document.querySelector<HTMLInputElement>("#exploration-title")!;
    input.focus();
    document
      .querySelector("#exploration-create-form")!
      .dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }));
    await wrapper.vm.$nextTick();
    expect(pushEvent.mock.calls[1][0]).toBe("exploration_create");
    input.dispatchEvent(
      new KeyboardEvent("keydown", { key: "Escape", bubbles: true, cancelable: true }),
    );
    await flushPromises();
    expect(pushEvent).toHaveBeenCalledTimes(2);
    expect(document.querySelector("#exploration-dialog")).not.toBeNull();

    pushEvent.mock.calls[1][2]({ status: "error", code: "unavailable" });
    await wrapper.vm.$nextTick();
    input.focus();
    input.dispatchEvent(
      new KeyboardEvent("keydown", { key: "Escape", bubbles: true, cancelable: true }),
    );
    await flushPromises();
    expect(pushEvent.mock.calls[2][0]).toBe("exploration_close");
    await wrapper.setProps({ state: { ...state, open: false, context: "closed-preview" } });
    pushEvent.mock.calls[2][2]({ status: "ok" });
    await flushPromises();
    expect(document.querySelector("#exploration-dialog")).toBeNull();
    expect(document.activeElement).toBe(trigger.element);
    wrapper.unmount();
  });
});
