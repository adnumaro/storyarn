import { afterEach, describe, expect, it, vi } from "vitest";
import { flushPromises, mount, type VueWrapper } from "@vue/test-utils";
import Panel from "@app/live/ideation/DecisionsPanel.vue";
import type { DecisionsPanelState } from "@app/live/ideation/decisionTypes";
import { decision, decisions, source } from "./decisionFixtures";

let wrapper: VueWrapper;
function panel(overrides: Partial<DecisionsPanelState> = {}, disconnected = false) {
  const pushEvent = disconnected ? vi.fn().mockRejectedValue(new Error("Disconnected")) : vi.fn();
  wrapper = mount(Panel, {
    attachTo: document.body,
    props: { state: decisions(overrides), epoch: "epoch-1", sessionId: 12 },
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
  await wrapper.get("#decision-title").setValue("Choose the forest");
  await wrapper.get("#decision-conclusion").setValue("The party takes the forest path.");
  await wrapper.get("#decision-reason").setValue("The road is too dangerous.");
}
afterEach(() => {
  wrapper?.unmount();
  vi.restoreAllMocks();
});

describe("decision proposal workflow", () => {
  it("submits only consulted identities, blocks duplicate clicks and keeps the retry identity after an uncertain reply", async () => {
    const pushEvent = panel({ mode: "create", sources: [source()] });
    await fillProposal();
    await wrapper.get("#decision-proposal-form").trigger("submit");
    await wrapper.get("#decision-proposal-form").trigger("submit");
    expect(pushEvent).toHaveBeenCalledTimes(1);
    const [event, payload, reply] = pushEvent.mock.calls[0];
    expect(event).toBe("decisions_create");
    expect(payload).toEqual({
      epoch: "epoch-1",
      session_id: 12,
      decision_context: "decisions-1",
      title: "Choose the forest",
      conclusion: "The party takes the forest path.",
      reason: "The road is too dangerous.",
      owner_id: 1,
      sources: [{ type: "idea", id: 10, identity: "idea-identity", version: 2 }],
      request_key: expect.any(String),
    });
    reply({ status: "error", code: "responsible_busy" });
    await flushPromises();
    expect(wrapper.get("[role=alert]").text()).toContain("Team permissions are being updated");
    await wrapper.setProps({
      state: decisions({ mode: "create", sources: [source({ changed: true, currentVersion: 3 })] }),
    });
    expect(wrapper.get<HTMLInputElement>("#decision-title").element.value).toBe(
      "Choose the forest",
    );
    await wrapper.get("#decision-proposal-form").trigger("submit");
    expect(pushEvent.mock.calls[1][1].request_key).toBe(payload.request_key);
  });

  it("preserves the accepted agreement and typed revision until the author explicitly reviews a concurrent change", async () => {
    const accepted = decision({
      status: "accepted",
      acceptedAt: "2026-09-13T12:00:00Z",
      canAccept: false,
    });
    const pushEvent = panel({
      mode: "revise",
      selected: accepted,
      sources: [source({ changed: true })],
    });
    expect(wrapper.get("#decision-previous-agreement").text()).toContain(
      "The party avoids the road.",
    );
    await wrapper.get("#decision-conclusion").setValue("My unsaved revision");
    await wrapper.get("#decision-refresh-sources").trigger("click");
    expect(pushEvent.mock.calls[0][0]).toBe("decisions_refresh_sources");
    pushEvent.mock.calls[0][2]({ status: "ok" });
    const newer = decision({
      revision: 3,
      conclusion: "Another author proposes the bridge.",
      previousAgreement: accepted,
      canAssign: false,
    });
    await wrapper.setProps({
      state: decisions({ mode: "revise", selected: newer, sources: [source({ version: 3 })] }),
    });
    expect(wrapper.get<HTMLTextAreaElement>("#decision-conclusion").element.value).toBe(
      "My unsaved revision",
    );
    expect(wrapper.get("#decision-save-proposal").attributes("disabled")).toBeDefined();
    expect(wrapper.get("#decision-current-proposal").text()).toContain(
      "Another author proposes the bridge.",
    );
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

  it("retires a successful receipt after its context changes so an identical new proposal gets a new request key", async () => {
    const pushEvent = panel({ mode: "create", sources: [source()] });
    await fillProposal();
    await wrapper.get("#decision-proposal-form").trigger("submit");
    const [, firstPayload, firstReply] = pushEvent.mock.calls[0];

    await wrapper.setProps({
      state: decisions({ mode: "detail", context: "saved-decision", selected: decision() }),
    });
    firstReply({ status: "ok" });
    await flushPromises();
    expect(wrapper.find("[role=alert]").exists()).toBe(false);

    await wrapper.get("#decisions-back").trigger("click");
    expect(pushEvent.mock.calls[1][0]).toBe("decisions_open");
    await wrapper.setProps({ state: decisions({ context: "decision-list" }) });
    pushEvent.mock.calls[1][2]({ status: "ok" });
    await wrapper.get("#decision-new").trigger("click");
    expect(pushEvent.mock.calls[2][0]).toBe("decisions_new");
    await wrapper.setProps({
      state: decisions({ mode: "create", context: "next-proposal", sources: [source()] }),
    });
    pushEvent.mock.calls[2][2]({ status: "ok" });
    await fillProposal();
    await wrapper.get("#decision-proposal-form").trigger("submit");

    expect(pushEvent.mock.calls[3][0]).toBe("decisions_create");
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
    expect(pushEvent).not.toHaveBeenCalled();

    await wrapper.get("#decision-refresh-sources").trigger("click");
    expect(pushEvent.mock.calls[0][0]).toBe("decisions_refresh_sources");
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
    expect(wrapper.get<HTMLInputElement>("#decision-title").element.value).toBe(
      "Choose the forest",
    );
    expect(wrapper.get("#decision-save-proposal").attributes("disabled")).toBeUndefined();
    expect(wrapper.find("#decision-refresh-sources").exists()).toBe(false);
  });

  it("requires explicit acceptance and sends the displayed revision without refreshing frozen sources", async () => {
    const pushEvent = panel({
      mode: "detail",
      selected: decision({ revision: 5, sources: [source({ changed: true })] }),
    });
    expect(pushEvent).not.toHaveBeenCalled();
    await wrapper.get("#decision-accept").trigger("click");
    expect(pushEvent.mock.calls[0][0]).toBe("decisions_accept");
    expect(pushEvent.mock.calls[0][1]).toMatchObject({
      decision_id: 4,
      revision: 5,
      request_key: expect.any(String),
    });
    expect(pushEvent.mock.calls[0][1]).not.toHaveProperty("sources");
  });

  it("hides unauthorized mutations and never exposes inaccessible source text", () => {
    panel({
      canPropose: false,
      mode: "detail",
      selected: decision({
        canAccept: false,
        canRevise: false,
        canAssign: false,
        sources: [
          source({ id: null, available: false, title: "Secret title", preview: "Secret body" }),
        ],
      }),
    });
    expect(wrapper.find("#decision-accept").exists()).toBe(false);
    expect(wrapper.find("#decision-revise").exists()).toBe(false);
    expect(wrapper.find("form").exists()).toBe(false);
    expect(wrapper.text()).not.toContain("Secret");
    expect(wrapper.text()).toContain("Source unavailable");
  });

  it("removes inaccessible sources by opaque identity and sends only remaining valid sources", async () => {
    const pushEvent = panel({
      mode: "create",
      sources: [
        source(),
        source({ id: null, identity: "removed-a", available: false }),
        source({ id: null, identity: "removed-b", available: false }),
      ],
    });
    await fillProposal();
    expect(wrapper.get("#decision-save-proposal").attributes("disabled")).toBeDefined();
    await wrapper.get('[data-decision-source="removed-b"] button').trigger("click");
    expect(pushEvent.mock.calls[0][0]).toBe("decisions_preview_sources");
    expect(pushEvent.mock.calls[0][1].sources).toEqual([
      { type: "idea", id: 10, identity: "idea-identity", version: 2 },
    ]);
  });

  it("asks before discarding unsaved work through Escape", async () => {
    const pushEvent = panel({ mode: "create", sources: [source()] });
    await fillProposal();
    await wrapper.get("#decision-title").trigger("keydown", { key: "Escape" });
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
    expect(wrapper.get<HTMLInputElement>("#decision-title").element.value).toBe(
      "Choose the forest",
    );
    expect(wrapper.get("#decision-save-proposal").attributes("disabled")).toBeUndefined();
  });
});
