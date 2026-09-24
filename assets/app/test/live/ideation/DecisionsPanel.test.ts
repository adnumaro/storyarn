import { afterEach, describe, expect, it, vi } from "vitest";
import { flushPromises, mount, type VueWrapper } from "@vue/test-utils";
import Panel from "@app/live/ideation/DecisionsPanel.vue";
import type { DecisionsPanelState } from "@app/live/ideation/decisionTypes";
import type { BrainstormingCommentsState } from "@modules/ideation/commentTypes";
import type { DecisionDiscussionState } from "@app/live/ideation/decisionTypes";
import { accepted, decision, decisions, revision, source, target } from "./decisionFixtures";

let wrapper: VueWrapper;
const passthrough = { template: "<div><slot /></div>" };
function panel(
  overrides: Partial<DecisionsPanelState> = {},
  disconnected = false,
  discussion?: DecisionDiscussionState,
) {
  const pushEvent = disconnected ? vi.fn().mockRejectedValue(new Error("Disconnected")) : vi.fn();
  wrapper = mount(Panel, {
    attachTo: document.body,
    props: {
      state: decisions(overrides),
      epoch: "epoch-1",
      sessionId: 12,
      ...(discussion ? { discussion } : {}),
    },
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
        Popover: {
          name: "Popover",
          props: ["open"],
          emits: ["update:open"],
          template: "<div><slot /></div>",
        },
        PopoverTrigger: passthrough,
        PopoverContent: passthrough,
        ConfirmDialog: {
          props: ["open", "title", "description"],
          emits: ["confirm", "update:open"],
          template:
            "<section v-if='open' role='dialog'><h2>{{ title }}</h2><p>{{ description }}</p><button id='discard-test' @click='$emit(\"confirm\")'>Discard</button></section>",
        },
      },
    },
  });
  return pushEvent;
}
async function fillProposal() {
  await wrapper.get("#decision-conclusion").setValue("The party takes the forest path. Tonight.");
  await wrapper.get("#decision-verb-change").trigger("click");
  await wrapper.get("#decision-reason").setValue("The road is too dangerous.");
}
afterEach(() => {
  wrapper?.unmount();
  vi.useRealTimers();
  vi.restoreAllMocks();
});

describe("proposing and registering", () => {
  it("registers by default, derives the title and keeps the retry identity after an uncertain reply", async () => {
    const pushEvent = panel({ mode: "create", sources: [source()] });
    expect(wrapper.get("#decision-save-proposal").text()).toContain("Register decision");
    expect(wrapper.get("#decision-save-proposal").attributes("disabled")).toBeDefined();
    await fillProposal();
    expect(wrapper.get<HTMLInputElement>("#decision-title").element.value).toBe(
      "The party takes the forest path",
    );
    await wrapper.get("#decision-proposal-form").trigger("submit");
    await wrapper.get("#decision-proposal-form").trigger("submit");
    expect(pushEvent).toHaveBeenCalledTimes(1);
    const [event, payload, reply] = pushEvent.mock.calls[0];
    expect(event).toBe("decisions_create");
    expect(payload).toEqual({
      epoch: "epoch-1",
      session_id: 12,
      decision_context: "decisions-1",
      title: "The party takes the forest path",
      conclusion: "The party takes the forest path. Tonight.",
      reason: "The road is too dangerous.",
      verb: "change",
      targets: [],
      next_action: null,
      next_action_owner_id: null,
      replaces_id: null,
      owner_id: 1,
      register: true,
      sources: [{ type: "idea", id: 10, identity: "idea-identity", version: 2 }],
      request_key: expect.any(String),
    });
    reply({ status: "error", code: "responsible_busy" });
    await flushPromises();
    expect(wrapper.get("[role=alert]").text()).toContain("Team permissions are being updated");
    await wrapper.setProps({
      state: decisions({ mode: "create", sources: [source({ changed: true, currentVersion: 3 })] }),
    });
    expect(wrapper.get<HTMLTextAreaElement>("#decision-conclusion").element.value).toBe(
      "The party takes the forest path. Tonight.",
    );
    await wrapper.get("#decision-proposal-form").trigger("submit");
    expect(pushEvent.mock.calls[1][1].request_key).toBe(payload.request_key);
  });

  it("proposes to someone else, or saves a registrable decision as a proposal on request", async () => {
    const pushEvent = panel({
      mode: "create",
      sources: [source()],
      viewerId: 9,
      defaultOwnerId: 2,
    });
    await fillProposal();
    expect(wrapper.get("#decision-save-proposal").text()).toContain("Propose");
    expect(wrapper.get("#decision-owner-preview").text()).toContain("Waiting for Noor to accept");
    expect(wrapper.find("#decision-save-as-proposal").exists()).toBe(false);
    await wrapper.get("#decision-proposal-form").trigger("submit");
    expect(pushEvent.mock.calls[0][1]).toMatchObject({ owner_id: 2, register: false });

    wrapper.unmount();
    const own = panel({ mode: "create", sources: [source()] });
    await fillProposal();
    await wrapper.get("#decision-save-as-proposal").trigger("click");
    expect(own.mock.calls[0][1]).toMatchObject({ owner_id: 1, register: false });
  });

  it("starts from a group's synthesis and title, and names free and existing affected content", async () => {
    const pushEvent = panel({
      mode: "create",
      sources: [
        source({ type: "group", title: "Keeper’s motives", preview: "Guilt, not ambition." }),
      ],
      prefill: {
        title: "Keeper’s motives",
        conclusion: "Guilt, not ambition.",
        fromGroup: "Keeper’s motives",
      },
      targetSuggestions: [{ type: "sheet", id: 7, name: "Mara", relation: "origin" }],
    });
    expect(wrapper.get<HTMLTextAreaElement>("#decision-conclusion").element.value).toBe(
      "Guilt, not ambition.",
    );
    expect(wrapper.get<HTMLInputElement>("#decision-title").element.value).toBe("Keeper’s motives");
    expect(wrapper.text()).toContain("From the synthesis of Keeper’s motives");
    await wrapper.get("#decision-verb-keep").trigger("click");
    expect(wrapper.get("#decision-affects-add").text()).toContain("Add affected content");
    await wrapper.get("#decision-target-option-sheet-7").trigger("click");
    await wrapper.get("#decision-target-new").trigger("click");
    await wrapper.get("#decision-target-new-label").setValue("The keeper's sister");
    await wrapper.get("#decision-target-new-label").trigger("submit");
    await wrapper.get("#decision-proposal-form").trigger("submit");
    expect(pushEvent.mock.calls.at(-1)?.[1]).toMatchObject({
      title: "Keeper’s motives",
      verb: "keep",
      targets: [
        { type: "sheet", id: 7 },
        { type: "sheet", id: null, label: "The keeper's sister" },
      ],
    });
  });

  it("preserves the agreement in force and typed text until the author reviews a concurrent change", async () => {
    const current = accepted();
    const pushEvent = panel({
      mode: "revise",
      selected: current,
      sources: [source({ changed: true })],
    });
    await wrapper.get("#decision-conclusion").setValue("My unsaved revision");
    await wrapper.get("#decision-refresh-sources").trigger("click");
    expect(pushEvent.mock.calls[0][0]).toBe("decisions_refresh_sources");
    pushEvent.mock.calls[0][2]({ status: "ok" });
    const newer = accepted({
      version: 3,
      status: "proposed",
      proposal: revision({ revision: 3, operation: "revise", conclusion: "Another author" }),
      canAssign: false,
    });
    await wrapper.setProps({
      state: decisions({ mode: "revise", selected: newer, sources: [source({ version: 3 })] }),
    });
    expect(wrapper.get<HTMLTextAreaElement>("#decision-conclusion").element.value).toBe(
      "My unsaved revision",
    );
    expect(wrapper.get("#decision-save-proposal").attributes("disabled")).toBeDefined();
    expect(wrapper.find("#decision-current-proposal").exists()).toBe(true);
    await wrapper.get("#decision-use-current-version").trigger("click");
    await wrapper.get("#decision-proposal-form").trigger("submit");
    expect(pushEvent.mock.calls[1][0]).toBe("decisions_revise");
    expect(pushEvent.mock.calls[1][1]).toMatchObject({
      decision_id: 4,
      revision: 3,
      conclusion: "My unsaved revision",
      sources: [{ identity: "idea-identity", version: 3 }],
    });
  });

  it("retires a successful receipt after its context changes so an identical proposal gets a new key", async () => {
    const pushEvent = panel({ mode: "create", sources: [source()] });
    await fillProposal();
    await wrapper.get("#decision-proposal-form").trigger("submit");
    const [, firstPayload, firstReply] = pushEvent.mock.calls[0];
    await wrapper.setProps({
      state: decisions({ mode: "detail", context: "saved-decision", selected: decision() }),
    });
    firstReply({ status: "ok" });
    await flushPromises();
    await wrapper.get("#decisions-back").trigger("click");
    await wrapper.setProps({ state: decisions({ context: "decision-list" }) });
    pushEvent.mock.calls[1][2]({ status: "ok" });
    await wrapper.get("#decision-new").trigger("click");
    await wrapper.setProps({
      state: decisions({ mode: "create", context: "next-proposal", sources: [source()] }),
    });
    pushEvent.mock.calls[2][2]({ status: "ok" });
    await fillProposal();
    await wrapper.get("#decision-proposal-form").trigger("submit");
    const nextPayload = pushEvent.mock.calls[3][1];
    expect(nextPayload).toEqual({
      ...firstPayload,
      decision_context: "next-proposal",
      request_key: expect.any(String),
    });
    expect(nextPayload.request_key).not.toBe(firstPayload.request_key);
  });

  it("offers an explicit refresh for a restored source whose saved preview remains unavailable", async () => {
    const restored = source({
      available: false,
      changed: true,
      currentVersion: 3,
      title: "Hidden old title",
      preview: "Hidden old preview",
    });
    const pushEvent = panel({ mode: "create", sources: [restored] });
    await fillProposal();
    expect(wrapper.text()).not.toContain("Hidden old");
    expect(wrapper.get("#decision-save-proposal").attributes("disabled")).toBeDefined();
    await wrapper.get("#decision-refresh-sources").trigger("click");
    expect(pushEvent.mock.calls[0][1]).toEqual({
      epoch: "epoch-1",
      session_id: 12,
      decision_context: "decisions-1",
    });
    await wrapper.setProps({
      state: decisions({ mode: "create", sources: [source({ version: 3 })] }),
    });
    pushEvent.mock.calls[0][2]({ status: "ok" });
    await flushPromises();
    expect(wrapper.get("#decision-save-proposal").attributes("disabled")).toBeUndefined();
  });

  it("removes inaccessible sources by opaque identity and sends only remaining valid sources", async () => {
    const pushEvent = panel({
      mode: "create",
      sources: [source(), source({ id: null, identity: "removed-a", available: false })],
    });
    await fillProposal();
    expect(wrapper.get("#decision-save-proposal").attributes("disabled")).toBeDefined();
    await wrapper.get('[data-decision-source="removed-a"] button').trigger("click");
    expect(pushEvent.mock.calls[0][0]).toBe("decisions_preview_sources");
    expect(pushEvent.mock.calls[0][1].sources).toEqual([
      { type: "idea", id: 10, identity: "idea-identity", version: 2 },
    ]);
  });
});

describe("reading and acting on a decision", () => {
  it("orders what waits for the reader first and folds retired decisions away", async () => {
    panel({
      items: [
        accepted({ id: 1, application: { targets: [], decision: null, pending: 0, total: 0 } }),
        decision({ id: 2, canAccept: false }),
        accepted({ id: 3 }),
        decision({ id: 5 }),
        decision({ id: 6, status: "withdrawn", canAccept: false, withdrawnByName: "Alex" }),
      ],
    });
    const order = () =>
      wrapper.findAll("[data-decision-card]").map((card) => card.attributes("data-decision-card"));
    expect(order()).toEqual(["5", "3", "2", "1"]);
    expect(wrapper.get('[data-decision-card="5"]').text()).toContain("Waiting for you");
    expect(wrapper.get('[data-decision-card="3"]').text()).toContain("1 of 1 to apply");
    expect(wrapper.get('[data-decision-card="2"]').text()).toContain("Waiting for Alex");
    expect(wrapper.get("#decisions-retired").text()).toContain("Retired · 1");
    await wrapper.get("#decisions-retired").trigger("click");
    expect(order()).toEqual(["5", "3", "2", "1", "6"]);
    expect(wrapper.get('[data-decision-card="6"]').text()).toContain("by Alex");
  });

  it("accepts and withdraws the displayed version", async () => {
    const pushEvent = panel({ mode: "detail", selected: decision({ version: 5 }) });
    await wrapper.get("#decision-accept").trigger("click");
    expect(pushEvent.mock.calls[0][0]).toBe("decisions_accept");
    expect(pushEvent.mock.calls[0][1]).toMatchObject({
      decision_id: 4,
      revision: 5,
      request_key: expect.any(String),
    });
    expect(pushEvent.mock.calls[0][1]).not.toHaveProperty("sources");
    pushEvent.mock.calls[0][2]({ status: "ok" });
    await flushPromises();
    await wrapper.get("#decision-withdraw").trigger("click");
    expect(pushEvent.mock.calls[1][0]).toBe("decisions_withdraw");
    expect(pushEvent.mock.calls[1][1]).toMatchObject({ decision_id: 4, revision: 5 });
  });

  it("declares a target of the agreement in force with an optional note", async () => {
    const pushEvent = panel({ mode: "detail", selected: accepted() });
    expect(wrapper.get("#decision-application").text()).toContain("1 of 1 to apply");
    await wrapper.get("#decision-mark-target-mara-partially_applied").trigger("click");
    await wrapper.get("#decision-application textarea").setValue("Rewrote her motivation");
    await wrapper.get("#decision-mark-target-mara-confirm").trigger("click");
    expect(pushEvent.mock.calls[0][0]).toBe("decisions_declare");
    expect(pushEvent.mock.calls[0][1]).toMatchObject({
      decision_id: 4,
      agreement: 2,
      target_key: "target-mara",
      state: "partially_applied",
      note: "Rewrote her motivation",
    });
  });

  it("lets an editor correct an applied declaration back to not applied with a new note", async () => {
    const appliedTarget = target({
      application: {
        state: "applied",
        note: "Marked too early",
        actorName: "Alex",
        at: "2026-09-13T12:00:00Z",
      },
    });
    const pushEvent = panel({
      mode: "detail",
      selected: accepted({
        application: { targets: [appliedTarget], decision: null, pending: 0, total: 1 },
      }),
    });
    expect(wrapper.get("#decision-mark-target-mara").text()).toContain("Update declaration");
    wrapper.findComponent({ name: "Popover" }).vm.$emit("update:open", true);
    await wrapper.vm.$nextTick();
    expect(wrapper.get("#decision-mark-target-mara-applied").attributes("aria-checked")).toBe(
      "true",
    );
    expect(wrapper.get<HTMLTextAreaElement>("#decision-application textarea").element.value).toBe(
      "Marked too early",
    );
    await wrapper.get("#decision-mark-target-mara-not_applied").trigger("click");
    await wrapper.get("#decision-application textarea").setValue("Still waiting on the scene");
    await wrapper.get("#decision-mark-target-mara-confirm").trigger("click");
    expect(pushEvent.mock.calls[0][1]).toMatchObject({
      target_key: "target-mara",
      state: "not_applied",
      note: "Still waiting on the scene",
    });
  });

  it("declares that a decision without affected content needs no change", async () => {
    const pushEvent = panel({
      mode: "detail",
      selected: accepted({
        accepted: revision({ revision: 2, operation: "register", verb: "discard", targets: [] }),
        application: { targets: [], decision: null, pending: 0, total: 0 },
      }),
    });
    await wrapper.get("#decision-declare-no-change").trigger("click");
    expect(pushEvent.mock.calls[0][1]).toMatchObject({
      target_key: null,
      state: "no_change_needed",
    });
  });

  it("lets an editor retract a no-change declaration with an updated note", async () => {
    const pushEvent = panel({
      mode: "detail",
      selected: accepted({
        accepted: revision({ revision: 2, operation: "register", verb: "discard", targets: [] }),
        application: {
          targets: [],
          decision: {
            state: "no_change_needed",
            note: "Original reason",
            actorName: "Alex",
            at: "2026-09-13T12:00:00Z",
          },
          pending: 0,
          total: 0,
        },
      }),
    });
    expect(wrapper.get("#decision-edit-no-change").text()).toContain("Update declaration");
    expect(wrapper.get("#decision-application").text()).toContain("Original reason");
    wrapper.findComponent({ name: "Popover" }).vm.$emit("update:open", true);
    await wrapper.vm.$nextTick();
    expect(
      wrapper.get("#decision-edit-no-change-no_change_needed").attributes("aria-checked"),
    ).toBe("true");
    expect(wrapper.get<HTMLTextAreaElement>("#decision-application textarea").element.value).toBe(
      "Original reason",
    );
    await wrapper.get("#decision-edit-no-change-not_applied").trigger("click");
    expect(wrapper.get("#decision-edit-no-change-confirm").text()).toContain("Mark not applied");
    await wrapper
      .get("#decision-application textarea")
      .setValue("The discarded route was never built");
    await wrapper.get("#decision-edit-no-change-confirm").trigger("click");
    expect(pushEvent.mock.calls[0][1]).toMatchObject({
      target_key: null,
      state: "not_applied",
      note: "The discarded route was never built",
    });
  });

  it("shows the proposed next action when reviewing a revision of an accepted decision", () => {
    panel({
      mode: "detail",
      selected: accepted({
        version: 3,
        status: "proposed",
        accepted: revision({
          revision: 2,
          operation: "accept",
          nextAction: { text: "Write the old path", ownerId: 1, ownerName: "Alex" },
        }),
        proposal: revision({
          revision: 3,
          operation: "revise",
          nextAction: { text: "Test the forest route", ownerId: 2, ownerName: "Noor" },
        }),
      }),
    });
    expect(wrapper.get("#decision-next-action-line").text()).toContain("Test the forest route");
    expect(wrapper.get("#decision-next-action-line").text()).toContain("Noor");
    expect(wrapper.get("#decision-next-action-line").text()).not.toContain("Write the old path");
  });

  it("hides unauthorized mutations and never exposes inaccessible source text", () => {
    panel({
      canPropose: false,
      mode: "detail",
      selected: accepted({
        canRevise: false,
        canAssign: false,
        canDeclare: false,
        accepted: revision({
          revision: 2,
          sources: [
            source({ id: null, available: false, title: "Secret title", preview: "Secret body" }),
          ],
          targets: [target({ id: null, available: false, name: "Mara" })],
        }),
      }),
    });
    expect(wrapper.find("#decision-accept").exists()).toBe(false);
    expect(wrapper.find("#decision-revise").exists()).toBe(false);
    expect(wrapper.find("#decision-withdraw").exists()).toBe(false);
    expect(wrapper.find("[id^=decision-mark-]").exists()).toBe(false);
    expect(wrapper.find("form").exists()).toBe(false);
    expect(wrapper.text()).not.toContain("Secret");
    expect(wrapper.text()).toContain("Source unavailable");
  });
});

describe("revising a replacement", () => {
  it("keeps the decision it already replaced as its choice", () => {
    const replacement = accepted({
      id: 4,
      accepted: revision({ revision: 2, operation: "accept", replacesId: 9 }),
      supersedes: { id: 9, title: "The old ending" },
    });
    // With no other decision in force, only the one it replaced keeps the row open.
    panel({ mode: "revise", selected: replacement, items: [replacement], sources: [source()] });
    expect(wrapper.find("#decision-replaces").exists()).toBe(true);
  });
});

describe("searching affected content", () => {
  it("sends the latest query even while another request is pending", async () => {
    vi.useFakeTimers();
    const pushEvent = panel({ mode: "create", sources: [source()] });
    await fillProposal();
    await wrapper.get("#decision-proposal-form").trigger("submit");
    const [saving] = pushEvent.mock.calls.map((call) => call[0]);
    expect(saving).toBe("decisions_create");

    const search = wrapper.get("input[aria-label='Search Sheets, Flows and Scenes…']");
    await search.setValue("Mara");
    vi.advanceTimersByTime(300);
    const searches = pushEvent.mock.calls.filter((call) => call[0] === "decisions_search_targets");
    expect(searches.at(-1)?.[1]).toMatchObject({ search: "Mara", decision_context: "decisions-1" });
    vi.useRealTimers();
  });
});

describe("discussing a decision", () => {
  function discussion(
    overrides: Partial<BrainstormingCommentsState> = {},
  ): BrainstormingCommentsState {
    return {
      open: true,
      presentation: "workspace",
      pins: [],
      threads: [],
      nextCursor: null,
      thread: null,
      messages: [],
      messageNextCursor: null,
      members: [],
      canComment: true,
      selectedSourceId: 4,
      error: null,
      ideaId: null,
      groupId: null,
      decisionId: 4,
      context: "discussion-1",
      ...overrides,
    };
  }

  it("counts each decision's discussion on its card", () => {
    panel({ items: [decision({ id: 4 }), accepted({ id: 5 })] }, false, {
      state: null,
      counts: { "4": 3 },
    });
    expect(wrapper.get("[data-decision-card='4'] [data-decision-comments]").text()).toBe("3");
    expect(wrapper.find("[data-decision-card='5'] [data-decision-comments]").exists()).toBe(false);
  });

  it("holds the shown decision's conversation between its application and its actions", async () => {
    const pushEvent = panel({ mode: "detail", selected: decision({ id: 4 }) }, false, {
      state: discussion(),
      counts: {},
    });
    const section = wrapper.get("#decision-discussion");
    expect(section.text()).toContain("Discussion");
    expect(section.text()).toContain("Resolving does not accept; accepting does not resolve.");
    await wrapper.get("#decision-discussion-comment-body").setValue("Does this hold in act two?");
    await wrapper.get("#decision-discussion-comment-send").trigger("click");
    await flushPromises();
    const [event, payload] = pushEvent.mock.calls.at(-1) ?? [];
    expect(event).toBe("comments_create");
    expect(payload).toMatchObject({
      body: "Does this hold in act two?",
      epoch: "epoch-1",
      session_id: 12,
      comment_context: "discussion-1",
      decision_id: 4,
    });
    expect(payload).not.toHaveProperty("position");
  });

  it("shows nothing of a conversation held for another decision", () => {
    panel({ mode: "detail", selected: decision({ id: 4 }) }, false, {
      state: discussion({ decisionId: 9 }),
      counts: {},
    });
    expect(wrapper.find("#decision-discussion").exists()).toBe(false);
  });
});

describe("leaving and losing the connection", () => {
  it("asks before discarding unsaved work through Escape", async () => {
    const pushEvent = panel({ mode: "create", sources: [source()] });
    await fillProposal();
    await wrapper.get("#decision-conclusion").trigger("keydown", { key: "Escape" });
    expect(pushEvent).not.toHaveBeenCalled();
    expect(wrapper.get("[role=dialog]").text()).toContain("Leave this proposal?");
    await wrapper.get("#discard-test").trigger("click");
    expect(pushEvent.mock.calls[0][0]).toBe("decisions_close");
  });

  it("ignores stale replies after a session switch", async () => {
    const pushEvent = panel();
    await wrapper.get("#decision-new").trigger("click");
    const reply = pushEvent.mock.calls[0][2];
    await wrapper.setProps({
      epoch: "epoch-2",
      sessionId: 15,
      state: decisions({ context: "new-context" }),
    });
    reply({ status: "error", code: "stale_decision" });
    await flushPromises();
    expect(wrapper.find("[role=alert]").exists()).toBe(false);
    expect(wrapper.get("#decision-new").attributes("disabled")).toBeUndefined();
  });

  it("releases controls on disconnection and preserves the proposal", async () => {
    vi.spyOn(console, "warn").mockImplementation(() => {});
    panel({ mode: "create", sources: [source()] }, true);
    await fillProposal();
    await wrapper.get("#decision-proposal-form").trigger("submit");
    await flushPromises();
    expect(wrapper.get("[role=alert]").text()).toContain("Connection interrupted");
    expect(wrapper.get<HTMLTextAreaElement>("#decision-conclusion").element.value).toBe(
      "The party takes the forest path. Tonight.",
    );
    expect(wrapper.get("#decision-save-proposal").attributes("disabled")).toBeUndefined();
  });
});
