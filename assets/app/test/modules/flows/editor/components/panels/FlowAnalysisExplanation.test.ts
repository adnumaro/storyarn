import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vitest";
import FlowAnalysisExplanation from "../../../../../../modules/flows/editor/components/panels/FlowAnalysisExplanation.vue";
import type {
  FlowExplanationState,
  ExplanationStatus,
} from "../../../../../../modules/flows/editor/components/panels/flowAnalysisTypes";

const FINDING_ID = "sf1_abc";
const FINDING_KEY = "no_outgoing_connection:1:node:42";

function state(overrides: Partial<FlowExplanationState> = {}): FlowExplanationState {
  return {
    available: true,
    findingId: FINDING_ID,
    findingKey: FINDING_KEY,
    status: "idle" as ExplanationStatus,
    error: null,
    stale: false,
    routes: [],
    blockedLanes: [],
    disclosure: null,
    retentionSeconds: null,
    result: null,
    ...overrides,
  };
}

function route(overrides = {}) {
  return {
    routeRef: "route-ref-1",
    lane: "managed",
    provider: "fake",
    model: "deterministic-v1",
    payer: "storyarn",
    priceUnits: 1,
    ...overrides,
  };
}

function disclosure(overrides = {}) {
  return {
    version: "storyarn-context-v1",
    context_version: "structural-finding-v1",
    scope: "structural_finding",
    serialized_bytes: 512,
    token_count: 128,
    included_count: 2,
    excluded_count: 0,
    truncated: false,
    warnings: [],
    ...overrides,
  };
}

function result(overrides = {}) {
  return {
    summary: "The dialogue node has no outgoing connection.",
    whyItTriggers: "Every non-terminal node needs an outgoing edge.",
    implications: ["Players reaching it cannot continue."],
    suggestedChecks: ["Check whether an exit node is missing."],
    ...overrides,
  };
}

function mountExplanation(
  explanation: FlowExplanationState,
  findingKey = FINDING_KEY,
  findingId = FINDING_ID,
) {
  return mount(FlowAnalysisExplanation, { props: { findingId, findingKey, explanation } });
}

describe("FlowAnalysisExplanation", () => {
  it("renders nothing when the actor cannot use AI", () => {
    const wrapper = mountExplanation(state({ available: false }));

    expect(wrapper.find("[data-testid='explanation-open']").exists()).toBe(false);
  });

  it("stays idle on every card except the selected finding", () => {
    const wrapper = mountExplanation(
      state({ status: "succeeded", result: result() }),
      "isolated_node:1:node:99",
    );

    expect(wrapper.find("[data-testid='explanation-result']").exists()).toBe(false);
    expect(wrapper.find("[data-testid='explanation-open']").exists()).toBe(true);
  });

  it("emits explain for its own finding", async () => {
    const wrapper = mountExplanation(state());

    await wrapper.find("[data-testid='explanation-open']").trigger("click");

    expect(wrapper.emitted("explain")).toEqual([[FINDING_ID]]);
  });

  it("discloses payer, price and sent data before running", () => {
    const wrapper = mountExplanation(
      state({ status: "preflight", routes: [route()], disclosure: disclosure() }),
    );

    const text = wrapper.text();
    expect(text).toContain("storyarn");
    expect(text).toContain("fake/deterministic-v1");
    expect(wrapper.find("[data-testid='explanation-preflight']").exists()).toBe(true);
    // The Slice-6 disclosure is reused, not re-implemented.
    expect(wrapper.findComponent({ name: "ContextDisclosure" }).exists()).toBe(true);
  });

  it("emits execute with the issued route reference", async () => {
    const wrapper = mountExplanation(state({ status: "preflight", routes: [route()] }));

    await wrapper.find("[data-testid='explanation-execute']").trigger("click");

    expect(wrapper.emitted("execute")).toEqual([["route-ref-1"]]);
  });

  it("shows a blocked lane as unavailable instead of hiding it", () => {
    const wrapper = mountExplanation(
      state({
        status: "preflight",
        routes: [],
        blockedLanes: [{ lane: "managed", reason: "allowance_exhausted" }],
      }),
    );

    const blocked = wrapper.find("[data-testid='explanation-blocked-lane']");
    expect(blocked.exists()).toBe(true);
    expect(blocked.text()).toContain("no AI units left");
    expect(wrapper.find("[data-testid='explanation-execute']").exists()).toBe(false);
  });

  it("separates generated narrative from deterministic facts", () => {
    const wrapper = mountExplanation(state({ status: "succeeded", result: result() }));

    const generated = wrapper.find("[data-testid='explanation-result']");
    expect(generated.exists()).toBe(true);
    expect(generated.text()).toContain("AI-generated");
    expect(generated.text()).toContain("not a Storyarn finding");
    expect(generated.text()).toContain("The dialogue node has no outgoing connection.");
    expect(generated.text()).toContain("Players reaching it cannot continue.");
  });

  it("marks an obsolete result and offers an explicit rerun", async () => {
    const wrapper = mountExplanation(state({ status: "succeeded", result: result(), stale: true }));

    expect(wrapper.find("[data-testid='explanation-stale']").exists()).toBe(true);

    await wrapper.find("[data-testid='explanation-rerun']").trigger("click");
    expect(wrapper.emitted("rerun")).toHaveLength(1);
  });

  it("distinguishes waiting for a slot from generating", () => {
    const queued = mountExplanation(state({ status: "queued" }));
    expect(queued.find("[data-testid='explanation-queued']").exists()).toBe(true);
    expect(queued.find("[data-testid='explanation-running']").exists()).toBe(false);
    expect(queued.text()).toContain("Waiting for a free slot");
  });

  it("offers to keep waiting when the panel stopped watching a live run", async () => {
    // `detached` is not a failure: the run is alive and already paid for, so the
    // affordance must be "keep waiting", never a rerun that buys a second unit.
    const wrapper = mountExplanation(state({ status: "detached" }));

    expect(wrapper.find("[data-testid='explanation-detached']").exists()).toBe(true);
    expect(wrapper.find("[data-testid='explanation-rerun']").exists()).toBe(false);
    expect(wrapper.text()).toContain("nothing extra will be charged");

    await wrapper.find("[data-testid='explanation-resume']").trigger("click");
    expect(wrapper.emitted("resume")).toHaveLength(1);
  });

  it("discloses how long a result is kept, before it is bought", () => {
    const wrapper = mountExplanation(
      state({ status: "preflight", routes: [route()], retentionSeconds: 86400 }),
    );

    const retention = wrapper.find("[data-testid='explanation-retention']");
    expect(retention.exists()).toBe(true);
    // The shipped TTL. "1440 minutes" would be correct and unreadable.
    expect(retention.text()).toContain("24 hours");
  });

  it("still reads naturally for a retention shorter than an hour", () => {
    const wrapper = mountExplanation(
      state({ status: "preflight", routes: [route()], retentionSeconds: 1800 }),
    );

    expect(wrapper.find("[data-testid='explanation-retention']").text()).toContain("30 minutes");
  });

  it("shows a running state while the operation is in flight", () => {
    const wrapper = mountExplanation(state({ status: "running" }));

    expect(wrapper.find("[data-testid='explanation-running']").exists()).toBe(true);
    expect(wrapper.find("[data-testid='explanation-result']").exists()).toBe(false);
  });

  it("explains a blocked or failed run in the actor's terms", () => {
    const blocked = mountExplanation(state({ status: "blocked", error: "allowance_paused" }));
    expect(blocked.find("[data-testid='explanation-error']").text()).toContain(
      "paused AI spending",
    );

    const failed = mountExplanation(state({ status: "failed", error: "provider_error" }));
    expect(failed.find("[data-testid='explanation-error']").text()).toContain(
      "could not complete the request",
    );

    // An error class with no copy still says something useful.
    const unknown = mountExplanation(state({ status: "failed", error: "brand_new_class" }));
    expect(unknown.find("[data-testid='explanation-error']").text()).toContain(
      "could not be produced",
    );
  });

  it("survives a rerun that rotates the occurrence id", () => {
    // Same rule+target, new evidence fingerprint: the card is a different
    // findingId but the same findingKey, and the narrative stays visible —
    // marked obsolete rather than vanishing.
    const wrapper = mountExplanation(
      state({ status: "succeeded", result: result(), stale: true }),
      FINDING_KEY,
      "sf1_rotated_occurrence",
    );

    expect(wrapper.find("[data-testid='explanation-result']").exists()).toBe(true);
    expect(wrapper.find("[data-testid='explanation-stale']").exists()).toBe(true);
  });

  it("offers a rerun after the result TTL elapsed", () => {
    const wrapper = mountExplanation(state({ status: "expired" }));

    expect(wrapper.find("[data-testid='explanation-error']").text()).toContain(
      "no longer available",
    );
    expect(wrapper.find("[data-testid='explanation-rerun']").exists()).toBe(true);
  });
});
