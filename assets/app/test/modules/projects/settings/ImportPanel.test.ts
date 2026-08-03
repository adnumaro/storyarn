import { mount } from "@vue/test-utils";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { ImportState } from "../../../../modules/projects/settings/export-import/types";
import { createMockLive } from "../../../setup";

const mockLive = createMockLive();

const reviewEventCalls = (event: string) =>
  vi.mocked(mockLive.pushEvent).mock.calls.filter(([name]) => name === event);

vi.mock("@shared/composables/useLive", () => ({
  useLive: () => mockLive,
}));

const { default: ImportPanel } =
  await import("../../../../modules/projects/settings/export-import/components/ImportPanel.vue");

function uploadState(): ImportState {
  return {
    step: "upload",
    attemptId: null,
    preview: null,
    error: null,
    conflictStrategy: "rename",
    warningCodes: [],
    status: null,
  };
}

function attemptState(
  status: NonNullable<ImportState["status"]>,
  step: ImportState["step"] = "queued",
  attemptId = 42,
): ImportState {
  return {
    step,
    attemptId,
    preview: {
      counts: { flows: 2, nodes: 4 },
      conflicts: {},
      has_conflicts: false,
    },
    error: null,
    conflictStrategy: "rename",
    warningCodes: [],
    status,
  };
}

function reviewedPreviewState(): ImportState {
  return {
    ...attemptState("ready", "preview"),
    preview: {
      counts: { sheets: 2, flows: 1, nodes: 8 },
      conflicts: {},
      has_conflicts: false,
      issue_summary: {
        warning_count: 0,
        error_count: 0,
        issue_count: 0,
        issues_truncated: false,
        counts_by_code: {},
      },
      import_review: {
        variable_count: 0,
        sheet_speaker_count: 2,
        preserved_channel_count: 1,
        speaker_decision_count: 3,
        speaker_decisions: [
          {
            speaker: "Capsley",
            occurrences: 34,
            suggested_action: "create_sheet",
            confidence: "medium",
            reasons: ["literal_character_name"],
          },
          {
            speaker: "Capsely",
            occurrences: 3,
            suggested_action: "create_sheet",
            confidence: "low",
            reasons: ["literal_character_name"],
          },
          {
            speaker: "SlideImage",
            occurrences: 14,
            suggested_action: "preserve_literal",
            confidence: "high",
            reasons: ["repeated_scoped_presentation_channel"],
          },
        ],
        speaker_decisions_truncated: false,
        possible_speaker_alias_count: 1,
        possible_speaker_aliases: [
          {
            left: "Capsely",
            left_occurrences: 3,
            right: "Capsley",
            right_occurrences: 34,
            more_frequent: "Capsley",
            less_frequent: "Capsely",
            evidence: "single_adjacent_transposition_with_dominant_frequency",
            decision: "review",
          },
        ],
        possible_speaker_aliases_truncated: false,
        compatibility_warning_count: 0,
        compatibility_warning_counts_by_code: {},
        requires_acknowledgement: true,
      },
    },
  };
}

function draftPreviewState(
  decisions: NonNullable<NonNullable<ImportState["preview"]>["import_review_draft"]>["decisions"],
): ImportState {
  const state = reviewedPreviewState();
  if (!state.preview) throw new Error("preview fixture missing");

  state.preview.import_review_draft = {
    version: 1,
    decisions,
    decision_fingerprint: "draft-fingerprint",
  };

  return state;
}

function resolvedPreviewState(): ImportState {
  const state = reviewedPreviewState();
  if (!state.preview) throw new Error("preview fixture missing");

  state.preview.import_review_resolution = {
    version: 2,
    decisions: [
      { speaker: "Capsely", action: "map_to_sheet", target_speaker: "Capsley" },
      { speaker: "Capsley", action: "create_sheet" },
      { speaker: "SlideImage", action: "preserve_literal" },
    ],
    decision_fingerprint: "resolution-fingerprint",
  };

  return state;
}

const CURRENT_USER_ID = 42;

function mountPanel(importState: ImportState = uploadState(), projectId = 7) {
  return mount(ImportPanel, {
    props: {
      projectId,
      canEdit: true,
      canImport: true,
      currentUserId: CURRENT_USER_ID,
      importState,
      uploadConfig: null,
    },
  });
}

// The stored reference is scoped to the signed-in user as well as the project,
// so a shared browser cannot hand one member's in-flight attempt to the next.
function storageKey(projectId = 7, userId = CURRENT_USER_ID) {
  return `storyarn:project-import:${projectId}:${userId}`;
}

function storedAttempt(attemptId = 42, savedAt = Date.now()) {
  return JSON.stringify({ version: 1, attemptId, savedAt });
}

function dispatchStorageChange(
  projectId: number,
  oldValue: string | null,
  newValue: string | null,
) {
  window.dispatchEvent(
    new StorageEvent("storage", {
      key: storageKey(projectId),
      oldValue,
      newValue,
      storageArea: window.localStorage,
    }),
  );
}

describe("ImportPanel resume state", () => {
  beforeEach(() => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-07-29T12:00:00.000Z"));
    vi.clearAllMocks();
    window.localStorage.clear();
  });

  afterEach(() => {
    window.localStorage.clear();
    vi.useRealTimers();
  });

  it("resumes a current project's stored attempt on mount", () => {
    window.localStorage.setItem(storageKey(), storedAttempt());

    const wrapper = mountPanel();

    expect(mockLive.pushEvent).toHaveBeenCalledWith(
      "resume_import",
      { attempt_id: 42 },
      expect.any(Function),
      expect.any(Function),
    );

    wrapper.unmount();
  });

  it.each([
    ["malformed JSON", () => "not-json"],
    ["unversioned values", () => JSON.stringify({ attemptId: 42, savedAt: Date.now() })],
    ["invalid values", () => JSON.stringify({ version: 1, attemptId: "42", savedAt: Date.now() })],
    [
      "unsafe attempt id",
      () =>
        JSON.stringify({
          version: 1,
          attemptId: Number.MAX_SAFE_INTEGER + 1,
          savedAt: Date.now(),
        }),
    ],
    [
      "unsupported version",
      () => JSON.stringify({ version: 2, attemptId: 42, savedAt: Date.now() }),
    ],
    [
      "timestamp too far in the future",
      () => JSON.stringify({ version: 1, attemptId: 42, savedAt: Date.now() + 5 * 60_000 + 1 }),
    ],
    [
      "expired timestamp",
      () => JSON.stringify({ version: 1, attemptId: 42, savedAt: Date.now() - 7 * 86_400_000 - 1 }),
    ],
  ])("discards a %s without contacting the server", (_label, buildStoredValue) => {
    window.localStorage.setItem(storageKey(), buildStoredValue());

    const wrapper = mountPanel();

    expect(mockLive.pushEvent).not.toHaveBeenCalled();
    expect(window.localStorage.getItem(storageKey())).toBeNull();

    wrapper.unmount();
  });

  it("clears a stored attempt when the server reports that it is missing", () => {
    window.localStorage.setItem(storageKey(), storedAttempt());

    const wrapper = mountPanel();
    const callback = vi.mocked(mockLive.pushEvent).mock.calls[0]?.[2];

    callback?.({ ok: false, reason: "not_found" });

    expect(window.localStorage.getItem(storageKey())).toBeNull();

    wrapper.unmount();
  });

  it("keeps a stored attempt when reconciliation is temporarily unavailable", () => {
    window.localStorage.setItem(storageKey(), storedAttempt());

    const wrapper = mountPanel();
    const callback = vi.mocked(mockLive.pushEvent).mock.calls[0]?.[2];

    callback?.({ ok: false, reason: "unavailable" });

    expect(window.localStorage.getItem(storageKey())).not.toBeNull();

    wrapper.unmount();
  });

  it("stores only versioned non-content metadata under a project-scoped key", () => {
    const wrapper = mountPanel(attemptState("queued"));
    const stored = JSON.parse(window.localStorage.getItem(storageKey()) ?? "{}");

    expect(stored).toEqual({
      version: 1,
      attemptId: 42,
      savedAt: Date.now(),
    });
    expect(Object.keys(stored)).toEqual(["version", "attemptId", "savedAt"]);

    wrapper.unmount();
  });

  it("does not consume another project's stored attempt", () => {
    window.localStorage.setItem(storageKey(8), storedAttempt(81));

    const wrapper = mountPanel(uploadState(), 7);

    expect(mockLive.pushEvent).not.toHaveBeenCalled();
    expect(window.localStorage.getItem(storageKey(8))).not.toBeNull();

    wrapper.unmount();
  });

  it("reconciles processing attempts until they become terminal", async () => {
    const wrapper = mountPanel(attemptState("queued"));
    vi.clearAllMocks();

    vi.advanceTimersByTime(3_000);

    expect(mockLive.pushEvent).toHaveBeenCalledWith(
      "reconcile_import",
      { attempt_id: 42 },
      expect.any(Function),
      expect.any(Function),
    );

    await wrapper.setProps({
      importState: attemptState("completed", "done"),
    });
    vi.clearAllMocks();
    vi.advanceTimersByTime(9_000);

    expect(mockLive.pushEvent).not.toHaveBeenCalled();
    expect(window.localStorage.getItem(storageKey())).not.toBeNull();

    wrapper.unmount();
  });

  it("waits for each reconcile reply before scheduling another request", () => {
    const wrapper = mountPanel(attemptState("queued"));
    vi.clearAllMocks();

    vi.advanceTimersByTime(3_000);
    const callback = vi.mocked(mockLive.pushEvent).mock.calls[0]?.[2];
    vi.advanceTimersByTime(4_999);

    expect(mockLive.pushEvent).toHaveBeenCalledTimes(1);

    callback?.({ ok: true, status: "queued" });
    vi.advanceTimersByTime(3_000);

    expect(mockLive.pushEvent).toHaveBeenCalledTimes(2);

    wrapper.unmount();
  });

  it("uses a watchdog to continue reconciliation when a reply is lost", () => {
    const wrapper = mountPanel(attemptState("queued"));
    vi.clearAllMocks();

    vi.advanceTimersByTime(3_000);
    expect(mockLive.pushEvent).toHaveBeenCalledTimes(1);

    vi.advanceTimersByTime(5_000);
    vi.advanceTimersByTime(3_000);

    expect(mockLive.pushEvent).toHaveBeenCalledTimes(2);

    wrapper.unmount();
  });

  it("retries a lost initial resume with bounded exponential backoff", () => {
    window.localStorage.setItem(storageKey(), storedAttempt());

    const wrapper = mountPanel();
    expect(mockLive.pushEvent).toHaveBeenCalledTimes(1);

    vi.advanceTimersByTime(5_000);
    vi.advanceTimersByTime(1_000);
    expect(mockLive.pushEvent).toHaveBeenCalledTimes(2);

    vi.advanceTimersByTime(5_000);
    vi.advanceTimersByTime(2_000);
    expect(mockLive.pushEvent).toHaveBeenCalledTimes(3);

    vi.advanceTimersByTime(5_000);
    vi.advanceTimersByTime(4_000);
    expect(mockLive.pushEvent).toHaveBeenCalledTimes(4);

    vi.advanceTimersByTime(60_000);
    expect(mockLive.pushEvent).toHaveBeenCalledTimes(4);
    expect(window.localStorage.getItem(storageKey())).not.toBeNull();

    wrapper.unmount();
  });

  it("stops confirmation retries once the resumed attempt reaches component props", async () => {
    window.localStorage.setItem(storageKey(), storedAttempt());

    const wrapper = mountPanel();
    const callback = vi.mocked(mockLive.pushEvent).mock.calls[0]?.[2];

    callback?.({ ok: true, status: "queued" });
    await wrapper.setProps({ importState: attemptState("queued") });
    vi.clearAllMocks();
    vi.advanceTimersByTime(60_000);

    expect(
      vi.mocked(mockLive.pushEvent).mock.calls.filter(([event]) => event === "resume_import"),
    ).toHaveLength(0);

    wrapper.unmount();
  });

  it("adopts a newer attempt written by another tab", async () => {
    const wrapper = mountPanel(attemptState("queued"));
    vi.clearAllMocks();

    const previous = window.localStorage.getItem(storageKey());
    const next = storedAttempt(43, Date.now() + 1);
    window.localStorage.setItem(storageKey(), next);
    dispatchStorageChange(7, previous, next);

    expect(mockLive.pushEvent).toHaveBeenCalledWith(
      "resume_import",
      { attempt_id: 43 },
      expect.any(Function),
      expect.any(Function),
    );

    const callback = vi.mocked(mockLive.pushEvent).mock.calls[0]?.[2];
    callback?.({ ok: true, status: "queued" });
    await wrapper.setProps({ importState: attemptState("queued", "queued", 43) });
    vi.clearAllMocks();
    vi.advanceTimersByTime(60_000);

    expect(
      vi.mocked(mockLive.pushEvent).mock.calls.filter(([event]) => event === "resume_import"),
    ).toHaveLength(0);
    expect(JSON.parse(window.localStorage.getItem(storageKey()) ?? "{}").attemptId).toBe(43);

    wrapper.unmount();
  });

  it("cancels a pending cross-tab resume when another tab clears it", () => {
    const wrapper = mountPanel();
    const next = storedAttempt();

    window.localStorage.setItem(storageKey(), next);
    dispatchStorageChange(7, null, next);
    expect(mockLive.pushEvent).toHaveBeenCalledTimes(1);

    window.localStorage.removeItem(storageKey());
    dispatchStorageChange(7, next, null);
    vi.advanceTimersByTime(60_000);

    expect(mockLive.pushEvent).toHaveBeenCalledTimes(1);
    expect(window.localStorage.getItem(storageKey())).toBeNull();

    wrapper.unmount();
  });

  it("ignores an old failure reply after a newer attempt starts", async () => {
    const wrapper = mountPanel(attemptState("queued"));
    vi.clearAllMocks();

    vi.advanceTimersByTime(3_000);
    const staleCallback = vi.mocked(mockLive.pushEvent).mock.calls[0]?.[2];

    await wrapper.setProps({
      importState: attemptState("queued", "queued", 43),
    });
    vi.clearAllMocks();

    staleCallback?.({ ok: false, reason: "not_found" });
    vi.advanceTimersByTime(3_000);

    expect(JSON.parse(window.localStorage.getItem(storageKey()) ?? "{}").attemptId).toBe(43);
    expect(mockLive.pushEvent).toHaveBeenCalledWith(
      "reconcile_import",
      { attempt_id: 43 },
      expect.any(Function),
      expect.any(Function),
    );

    wrapper.unmount();
  });

  it("continues without resume state when localStorage is disabled", () => {
    const storageSpy = vi.spyOn(Storage.prototype, "getItem").mockImplementation(() => {
      throw new DOMException("Storage disabled", "SecurityError");
    });

    const wrapper = mountPanel();

    expect(mockLive.pushEvent).not.toHaveBeenCalled();

    wrapper.unmount();
    storageSpy.mockRestore();
  });

  it("clears the persisted reference only after the server confirms the reset", async () => {
    const wrapper = mountPanel(attemptState("completed", "done"));
    expect(window.localStorage.getItem(storageKey())).not.toBeNull();

    await wrapper.get('[data-testid="yarn-import-reset"]').trigger("click");

    expect(mockLive.pushEvent).toHaveBeenCalledWith("reset_import", {}, expect.any(Function));

    // The durable reference must survive until the server has terminalized
    // the attempt — clearing first re-creates the original lost-progress bug.
    expect(window.localStorage.getItem(storageKey())).not.toBeNull();

    const resetCall = vi
      .mocked(mockLive.pushEvent)
      .mock.calls.find(([event]) => event === "reset_import");

    resetCall?.[2]?.({ ok: true });

    expect(window.localStorage.getItem(storageKey())).toBeNull();

    wrapper.unmount();
  });

  it("keeps the persisted reference when the server refuses the reset", async () => {
    const wrapper = mountPanel(attemptState("completed", "done"));
    expect(window.localStorage.getItem(storageKey())).not.toBeNull();

    await wrapper.get('[data-testid="yarn-import-reset"]').trigger("click");

    const resetCall = vi
      .mocked(mockLive.pushEvent)
      .mock.calls.find(([event]) => event === "reset_import");

    resetCall?.[2]?.({ ok: false, reason: "import_not_cancellable" });

    expect(window.localStorage.getItem(storageKey())).not.toBeNull();

    wrapper.unmount();
  });

  it("does not apply heuristic suggestions and debounces partial draft saves", async () => {
    const wrapper = mountPanel(reviewedPreviewState());

    expect(wrapper.get('[data-testid="yarn-import-variable-count"]').text()).toBe("0");

    const decisions = wrapper.findAll('[data-testid="yarn-import-speaker-decision"]');
    expect(decisions).toHaveLength(3);
    expect(decisions[0]!.text()).toContain("Capsley");
    expect(decisions[0]!.attributes("data-decision")).toBe("missing");
    expect(decisions[0]!.attributes("data-suggested-action")).toBe("create_sheet");
    expect(decisions[0]!.text()).toContain("Medium");
    expect(decisions[1]!.text()).toContain("Capsely");
    expect(decisions[1]!.attributes("data-decision")).toBe("missing");
    expect(decisions[2]!.text()).toContain("SlideImage");
    expect(decisions[2]!.attributes("data-decision")).toBe("missing");
    expect(decisions[2]!.attributes("data-suggested-action")).toBe("preserve_literal");
    expect(decisions[2]!.text()).toContain("High");
    expect(wrapper.get('[data-testid="yarn-import-sheet-speaker-count"]').text()).toBe("0");
    expect(wrapper.get('[data-testid="yarn-import-preserved-channel-count"]').text()).toBe("0");
    expect(wrapper.get('[data-testid="yarn-import-mapped-alias-count"]').text()).toBe("0");

    const alias = wrapper.get('[data-testid="yarn-import-speaker-alias"]');
    expect(alias.text()).toContain("Capsely");
    expect(alias.text()).toContain("3");
    expect(alias.text()).toContain("Capsley");
    expect(alias.text()).toContain("34");
    expect(
      wrapper
        .get('[data-testid="yarn-import-alias-mapping-status"]')
        .attributes("data-mapping-enabled"),
    ).toBe("false");
    expect(wrapper.findAll('[data-testid="yarn-import-action-map-to-sheet"]')).toHaveLength(0);

    const createActions = wrapper.findAll('[data-testid="yarn-import-action-create-sheet"]');
    await createActions[0]!.trigger("click");

    expect(decisions[0]!.attributes("data-decision")).toBe("create_sheet");
    expect(decisions[1]!.attributes("data-decision")).toBe("missing");
    expect(wrapper.findAll('[data-testid="yarn-import-action-map-to-sheet"]')).toHaveLength(1);
    expect(
      wrapper
        .get('[data-testid="yarn-import-alias-mapping-status"]')
        .attributes("data-mapping-enabled"),
    ).toBe("true");

    vi.advanceTimersByTime(499);
    expect(reviewEventCalls("save_import_review")).toHaveLength(0);
    vi.advanceTimersByTime(1);
    expect(mockLive.pushEvent).toHaveBeenCalledWith(
      "save_import_review",
      {
        review_decisions: [{ speaker: "Capsley", action: "create_sheet" }],
      },
      expect.any(Function),
      expect.any(Function),
    );

    wrapper.unmount();
  });

  it("maps a less frequent alias only while its canonical target creates a sheet", async () => {
    const wrapper = mountPanel(reviewedPreviewState());
    const decisions = wrapper.findAll('[data-testid="yarn-import-speaker-decision"]');
    const createActions = wrapper.findAll('[data-testid="yarn-import-action-create-sheet"]');

    await createActions[0]!.trigger("click");
    await wrapper.get('[data-testid="yarn-import-action-map-to-sheet"]').trigger("click");
    expect(decisions[1]!.attributes("data-decision")).toBe("map_to_sheet");
    expect(wrapper.get('[data-testid="yarn-import-mapped-alias-count"]').text()).toBe("1");

    vi.advanceTimersByTime(500);
    expect(mockLive.pushEvent).toHaveBeenCalledWith(
      "save_import_review",
      {
        review_decisions: [
          { speaker: "Capsley", action: "create_sheet" },
          { speaker: "Capsely", action: "map_to_sheet", target_speaker: "Capsley" },
        ],
      },
      expect.any(Function),
      expect.any(Function),
    );

    vi.clearAllMocks();
    const preserveActions = wrapper.findAll('[data-testid="yarn-import-action-preserve-literal"]');
    await preserveActions[0]!.trigger("click");

    expect(decisions[0]!.attributes("data-decision")).toBe("preserve_literal");
    expect(decisions[1]!.attributes("data-decision")).toBe("missing");
    expect(wrapper.findAll('[data-testid="yarn-import-action-map-to-sheet"]')).toHaveLength(0);
    expect(wrapper.get('[data-testid="yarn-import-mapped-alias-count"]').text()).toBe("0");

    vi.advanceTimersByTime(500);
    expect(mockLive.pushEvent).toHaveBeenCalledWith(
      "save_import_review",
      {
        review_decisions: [{ speaker: "Capsley", action: "preserve_literal" }],
      },
      expect.any(Function),
      expect.any(Function),
    );

    wrapper.unmount();
  });

  it("only offers the backend-supported literal action for dynamic speakers", () => {
    const state = reviewedPreviewState();
    const review = state.preview?.import_review;
    if (!review) throw new Error("review fixture missing");

    Object.assign(review, {
      sheet_speaker_count: 0,
      preserved_channel_count: 1,
      speaker_decision_count: 1,
      speaker_decisions: [
        {
          speaker: "{$currentSpeaker}",
          occurrences: 2,
          suggested_action: "preserve_literal",
          confidence: "high",
          reasons: ["dynamic_speaker_expression"],
        },
      ],
      possible_speaker_alias_count: 0,
      possible_speaker_aliases: [],
    });

    const wrapper = mountPanel(state);
    const decision = wrapper.get('[data-testid="yarn-import-speaker-decision"]');

    expect(decision.text()).toContain("computed from a Yarn variable");
    expect(wrapper.findAll('[data-testid="yarn-import-action-create-sheet"]')).toHaveLength(0);
    expect(wrapper.findAll('[data-testid="yarn-import-action-map-to-sheet"]')).toHaveLength(0);
    expect(wrapper.findAll('[data-testid="yarn-import-action-preserve-literal"]')).toHaveLength(1);

    wrapper.unmount();
  });

  it("restores a partial draft without filling missing decisions from suggestions", () => {
    const wrapper = mountPanel(
      draftPreviewState([
        { speaker: "Capsley", action: "create_sheet" },
        { speaker: "SlideImage", action: "preserve_literal" },
      ]),
    );

    const decisions = wrapper.findAll('[data-testid="yarn-import-speaker-decision"]');
    expect(decisions[0]?.attributes("data-decision")).toBe("create_sheet");
    expect(decisions[1]?.attributes("data-decision")).toBe("missing");
    expect(decisions[2]?.attributes("data-decision")).toBe("preserve_literal");
    expect(wrapper.get("#yarn-import-validate").attributes("disabled")).toBeDefined();
    expect(wrapper.get("#yarn-import-confirm").attributes("disabled")).toBeDefined();

    vi.advanceTimersByTime(5_000);
    expect(reviewEventCalls("save_import_review")).toHaveLength(0);

    wrapper.unmount();
  });

  it("validates an acknowledged complete selection before enabling import", async () => {
    const wrapper = mountPanel(
      draftPreviewState([
        { speaker: "Capsley", action: "create_sheet" },
        { speaker: "Capsely", action: "create_sheet" },
        { speaker: "SlideImage", action: "preserve_literal" },
      ]),
    );

    const validate = wrapper.get("#yarn-import-validate");
    const confirm = wrapper.get("#yarn-import-confirm");
    expect(validate.attributes("disabled")).toBeDefined();
    expect(confirm.attributes("disabled")).toBeDefined();

    await wrapper.get("#yarn-import-review-acknowledgement").trigger("click");
    expect(validate.attributes("disabled")).toBeUndefined();
    expect(confirm.attributes("disabled")).toBeDefined();

    await validate.trigger("click");
    expect(mockLive.pushEvent).toHaveBeenCalledWith(
      "validate_import_review",
      {
        review_acknowledged: true,
        review_decisions: [
          { speaker: "Capsley", action: "create_sheet" },
          { speaker: "Capsely", action: "create_sheet" },
          { speaker: "SlideImage", action: "preserve_literal" },
        ],
      },
      expect.any(Function),
      expect.any(Function),
    );

    wrapper.unmount();
  });

  it("shows only aggregate compatibility counts and requires warning acknowledgement", async () => {
    const state = reviewedPreviewState();
    const review = state.preview?.import_review;
    if (!state.preview || !review) throw new Error("review fixture missing");

    Object.assign(review, {
      sheet_speaker_count: 0,
      preserved_channel_count: 0,
      speaker_decision_count: 0,
      speaker_decisions: [],
      possible_speaker_alias_count: 0,
      possible_speaker_aliases: [],
      compatibility_warning_count: 2,
      compatibility_warning_counts_by_code: {
        unreachable_yarn_code: 1,
        dynamic_text_preserved: 1,
      },
      requires_acknowledgement: true,
    });
    state.preview.issue_summary = {
      warning_count: 2,
      error_count: 0,
      issue_count: 2,
      issues_truncated: true,
      counts_by_code: {
        unreachable_yarn_code: 1,
        dynamic_text_preserved: 1,
      },
    };

    const wrapper = mountPanel(state);
    const summary = wrapper.get('[data-testid="yarn-import-issue-summary"]');
    const validate = wrapper.get("#yarn-import-validate");

    expect(summary.text()).toContain("2");
    expect(wrapper.get('[data-testid="yarn-import-warning-count"]').text()).toBe("2");
    expect(wrapper.get('[data-testid="yarn-import-error-count"]').text()).toBe("0");
    expect(wrapper.get('[data-testid="yarn-import-issue-count"]').text()).toBe("2");
    // Known codes render their catalog label; unknown ones fall back to a
    // generic, still-localized label — raw codes never reach the screen.
    const codeCounts = wrapper.get('[data-testid="yarn-import-issue-code-counts"]').text();
    expect(codeCounts).toContain("Unreachable text discarded");
    expect(codeCounts).toContain("Compatibility issue");
    expect(codeCounts).not.toContain("dynamic text preserved");
    expect(summary.text()).not.toContain("private dialogue");
    expect(validate.attributes("disabled")).toBeDefined();

    await wrapper.get("#yarn-import-review-acknowledgement").trigger("click");
    expect(validate.attributes("disabled")).toBeUndefined();
    await validate.trigger("click");

    expect(mockLive.pushEvent).toHaveBeenCalledWith(
      "validate_import_review",
      {
        review_acknowledged: true,
        review_decisions: [],
      },
      expect.any(Function),
      expect.any(Function),
    );

    wrapper.unmount();
  });

  it("restores a resolution and executes only its exact decisions and fingerprint", async () => {
    const wrapper = mountPanel(resolvedPreviewState());
    const decisions = wrapper.findAll('[data-testid="yarn-import-speaker-decision"]');
    const validate = wrapper.get("#yarn-import-validate");
    const confirm = wrapper.get("#yarn-import-confirm");

    expect(decisions[0]?.attributes("data-decision")).toBe("create_sheet");
    expect(decisions[1]?.attributes("data-decision")).toBe("map_to_sheet");
    expect(decisions[2]?.attributes("data-decision")).toBe("preserve_literal");
    expect(wrapper.find('[data-testid="yarn-import-review-validated"]').exists()).toBe(true);
    expect(wrapper.find("#yarn-import-review-acknowledgement").exists()).toBe(false);
    expect(validate.attributes("disabled")).toBeDefined();
    expect(confirm.attributes("disabled")).toBeUndefined();

    await confirm.trigger("click");
    expect(mockLive.pushEvent).toHaveBeenCalledWith(
      "execute_import",
      {
        review_confirmation_fingerprint: "resolution-fingerprint",
      },
      expect.any(Function),
      expect.any(Function),
    );

    vi.clearAllMocks();
    const createActions = wrapper.findAll('[data-testid="yarn-import-action-create-sheet"]');
    await createActions[2]?.trigger("click");

    expect(wrapper.find('[data-testid="yarn-import-review-validated"]').exists()).toBe(false);
    expect(confirm.attributes("disabled")).toBeDefined();
    await confirm.trigger("click");
    expect(reviewEventCalls("execute_import")).toHaveLength(0);

    vi.advanceTimersByTime(500);
    expect(mockLive.pushEvent).toHaveBeenCalledWith(
      "save_import_review",
      {
        review_decisions: [
          { speaker: "Capsley", action: "create_sheet" },
          { speaker: "Capsely", action: "map_to_sheet", target_speaker: "Capsley" },
          { speaker: "SlideImage", action: "create_sheet" },
        ],
      },
      expect.any(Function),
      expect.any(Function),
    );

    wrapper.unmount();
  });

  it("does not revert newer selections when an older save reply echoes back", async () => {
    const wrapper = mountPanel(reviewedPreviewState());
    const decisions = wrapper.findAll('[data-testid="yarn-import-speaker-decision"]');

    await wrapper.findAll('[data-testid="yarn-import-action-create-sheet"]')[0]!.trigger("click");
    vi.advanceTimersByTime(500);

    const firstSave = reviewEventCalls("save_import_review")[0];
    expect(firstSave).toBeDefined();

    // A newer edit lands while the first save is still in flight.
    await wrapper.findAll('[data-testid="yarn-import-action-create-sheet"]')[1]!.trigger("click");

    // The first save round-trips and its older state echoes back through
    // props. Restoring from it here would silently revert the newer edit and
    // cancel its pending save.
    firstSave?.[2]?.({ ok: true });
    await wrapper.setProps({
      importState: draftPreviewState([{ speaker: "Capsley", action: "create_sheet" }]),
    });

    expect(decisions[1]?.attributes("data-decision")).toBe("create_sheet");

    vi.advanceTimersByTime(500);

    const secondSave = reviewEventCalls("save_import_review")[1];
    expect(secondSave?.[1]).toEqual({
      review_decisions: [
        { speaker: "Capsley", action: "create_sheet" },
        { speaker: "Capsely", action: "create_sheet" },
      ],
    });

    wrapper.unmount();
  });

  it("keeps the acknowledgement through a clean echo of the current selections", async () => {
    const wrapper = mountPanel(reviewedPreviewState());

    await wrapper.findAll('[data-testid="yarn-import-action-create-sheet"]')[0]!.trigger("click");
    await wrapper.get('[data-testid="yarn-import-action-map-to-sheet"]').trigger("click");
    await wrapper
      .findAll('[data-testid="yarn-import-action-preserve-literal"]')
      .at(-1)!
      .trigger("click");

    // The draft save round-trips, so the review is clean and props echoes
    // reach restoreDecisions instead of being skipped by the dirty guard.
    vi.advanceTimersByTime(500);
    const saveCall = reviewEventCalls("save_import_review")[0];
    saveCall?.[2]?.({ ok: true });

    await wrapper.get("#yarn-import-review-acknowledgement").trigger("click");

    const validate = wrapper.get("#yarn-import-validate");
    expect(validate.attributes("disabled")).toBeUndefined();

    // The echo carries exactly what is on screen; the tick routinely lands
    // inside the save's round-trip, and losing it here meant a silently
    // re-disabled Validate with no explanation.
    await wrapper.setProps({
      importState: draftPreviewState([
        { speaker: "Capsley", action: "create_sheet" },
        { speaker: "Capsely", action: "map_to_sheet", target_speaker: "Capsley" },
        { speaker: "SlideImage", action: "preserve_literal" },
      ]),
    });

    expect(validate.attributes("disabled")).toBeUndefined();

    // A draft that differs from the screen is not an echo: selections are
    // adopted and the acknowledgement resets.
    await wrapper.setProps({
      importState: draftPreviewState([{ speaker: "Capsley", action: "create_sheet" }]),
    });

    expect(wrapper.get("#yarn-import-validate").attributes("disabled")).toBeDefined();

    wrapper.unmount();
  });

  it("an old reset reply does not permanently dismiss a newer cross-tab attempt", async () => {
    const wrapper = mountPanel(attemptState("completed", "done", 42));

    // Another tab starts a newer import; its reference lands via storage and
    // this tab begins resuming it while still displaying the old attempt.
    window.localStorage.setItem(storageKey(), storedAttempt(43));
    dispatchStorageChange(7, null, storedAttempt(43));
    expect(mockLive.pushEvent).toHaveBeenCalledWith(
      "resume_import",
      { attempt_id: 43 },
      expect.any(Function),
      expect.any(Function),
    );

    // The reset of the OLD attempt round-trips afterwards. Dismissing the
    // pending newer attempt here marked it dismissed forever: it could never
    // be stored or resumed again in this session.
    await wrapper.get('[data-testid="yarn-import-reset"]').trigger("click");
    const resetCall = vi
      .mocked(mockLive.pushEvent)
      .mock.calls.find(([event]) => event === "reset_import");
    resetCall?.[2]?.({ ok: true });

    // The newer attempt reaches the panel; its reference must persist again.
    window.localStorage.removeItem(storageKey());
    await wrapper.setProps({ importState: attemptState("queued", "queued", 43) });

    const stored = window.localStorage.getItem(storageKey());
    expect(stored).not.toBeNull();
    expect(JSON.parse(stored!).attemptId).toBe(43);

    wrapper.unmount();
  });

  it("a delayed save reply from a previous attempt cannot corrupt the new review", async () => {
    const wrapper = mountPanel(reviewedPreviewState());

    // Three edits on attempt A; the save goes out and stays unanswered.
    await wrapper.findAll('[data-testid="yarn-import-action-create-sheet"]')[0]!.trigger("click");
    await wrapper.get('[data-testid="yarn-import-action-map-to-sheet"]').trigger("click");
    await wrapper
      .findAll('[data-testid="yarn-import-action-preserve-literal"]')
      .at(-1)!
      .trigger("click");
    vi.advanceTimersByTime(500);

    const oldSave = reviewEventCalls("save_import_review")[0];
    expect(oldSave).toBeDefined();

    // The panel moves to a different attempt and the user makes ONE edit.
    const nextAttempt = reviewedPreviewState();
    nextAttempt.attemptId = 43;
    await wrapper.setProps({ importState: nextAttempt });

    const decisions = wrapper.findAll('[data-testid="yarn-import-speaker-decision"]');
    await wrapper.findAll('[data-testid="yarn-import-action-create-sheet"]')[0]!.trigger("click");
    expect(decisions[0]?.attributes("data-decision")).toBe("create_sheet");

    // Attempt A's save reply lands late. If it advanced the new attempt's
    // syncedRevision past localRevision, the next props echo would restore
    // over the unsaved local edit.
    oldSave?.[2]?.({ ok: true });

    const echo = reviewedPreviewState();
    echo.attemptId = 43;
    if (echo.preview) {
      echo.preview.import_review_draft = {
        version: 1,
        decisions: [],
        decision_fingerprint: "other-draft",
      };
    }
    await wrapper.setProps({ importState: echo });

    expect(decisions[0]?.attributes("data-decision")).toBe("create_sheet");

    wrapper.unmount();
  });

  it("a late validate success does not erase a newer retry's failure", async () => {
    const wrapper = mountPanel(reviewedPreviewState());

    await wrapper.findAll('[data-testid="yarn-import-action-create-sheet"]')[0]!.trigger("click");
    await wrapper.get('[data-testid="yarn-import-action-map-to-sheet"]').trigger("click");
    await wrapper
      .findAll('[data-testid="yarn-import-action-preserve-literal"]')
      .at(-1)!
      .trigger("click");
    await wrapper.get("#yarn-import-review-acknowledgement").trigger("click");

    const validate = wrapper.get("#yarn-import-validate");
    await validate.trigger("click");

    // The first validate times out; its watchdog surfaces a failure and
    // re-enables the button.
    vi.advanceTimersByTime(10_000);
    await wrapper.vm.$nextTick();
    expect(wrapper.find('[data-testid="yarn-import-review-error"]').exists()).toBe(true);

    // The user retries; the retry is rejected and owns the banner now.
    await validate.trigger("click");
    const [firstValidate, retryValidate] = reviewEventCalls("validate_import_review");
    retryValidate?.[2]?.({ ok: false, reason: "stale" });
    await wrapper.vm.$nextTick();
    expect(wrapper.find('[data-testid="yarn-import-review-error"]').exists()).toBe(true);

    // The FIRST validate's success arrives after everything. It is stale:
    // clearing the retry's failure would leave the panel reporting nothing.
    firstValidate?.[2]?.({ ok: true });
    await wrapper.vm.$nextTick();
    expect(wrapper.find('[data-testid="yarn-import-review-error"]').exists()).toBe(true);

    wrapper.unmount();
  });

  it("surfaces a draft save whose reply never arrives", async () => {
    const wrapper = mountPanel(reviewedPreviewState());

    await wrapper.findAll('[data-testid="yarn-import-action-create-sheet"]')[0]!.trigger("click");
    vi.advanceTimersByTime(500);
    expect(reviewEventCalls("save_import_review")).toHaveLength(1);

    // The push was accepted and went silent: no reply, no error callback.
    // This is the exact case only a watchdog can voice.
    vi.advanceTimersByTime(10_000);
    await wrapper.vm.$nextTick();

    const banner = wrapper.get('[data-testid="yarn-import-review-error"]');
    expect(banner.text().length).toBeGreaterThan(0);

    wrapper.unmount();
  });

  it("surfaces a rejected validate instead of failing silently", async () => {
    const wrapper = mountPanel(reviewedPreviewState());

    await wrapper.findAll('[data-testid="yarn-import-action-create-sheet"]')[0]!.trigger("click");
    await wrapper.get('[data-testid="yarn-import-action-map-to-sheet"]').trigger("click");
    await wrapper
      .findAll('[data-testid="yarn-import-action-preserve-literal"]')
      .at(-1)!
      .trigger("click");
    await wrapper.get("#yarn-import-review-acknowledgement").trigger("click");

    const validate = wrapper.get("#yarn-import-validate");
    expect(validate.attributes("disabled")).toBeUndefined();
    await validate.trigger("click");

    // Locked while the reply is outstanding; no double-push.
    expect(validate.attributes("disabled")).toBeDefined();

    const call = reviewEventCalls("validate_import_review")[0];
    call?.[2]?.({ ok: false, reason: "stale" });
    await wrapper.vm.$nextTick();

    const banner = wrapper.get('[data-testid="yarn-import-review-error"]');
    expect(banner.text().length).toBeGreaterThan(0);
    expect(validate.attributes("disabled")).toBeUndefined();

    wrapper.unmount();
  });

  it("blocks truncated reviews even after acknowledgement", async () => {
    const state = reviewedPreviewState();
    const review = state.preview?.import_review;
    if (!review) throw new Error("review fixture missing");

    review.sheet_speaker_count = 2_400;
    review.preserved_channel_count = 100;
    review.speaker_decision_count = 2_500;
    review.speaker_decisions = [review.speaker_decisions[0]!];
    review.speaker_decisions_truncated = true;
    review.possible_speaker_alias_count = 25;
    review.possible_speaker_aliases = [];
    review.possible_speaker_aliases_truncated = true;
    review.requires_acknowledgement = false;

    const wrapper = mountPanel(state);

    expect(wrapper.get('[data-testid="yarn-import-sheet-speaker-count"]').text()).toBe("2400");
    expect(wrapper.get('[data-testid="yarn-import-preserved-channel-count"]').text()).toBe("100");
    expect(wrapper.get('[data-testid="yarn-import-speaker-review-truncated"]').text()).toContain(
      "2500",
    );
    expect(wrapper.get('[data-testid="yarn-import-alias-review-truncated"]').text()).toContain(
      "25",
    );
    expect(wrapper.get('[data-testid="yarn-import-review-incomplete"]').text()).toContain(
      "truncated",
    );

    const confirm = wrapper.get("#yarn-import-confirm");
    expect(confirm.attributes("disabled")).toBeDefined();
    expect(wrapper.find("#yarn-import-review-acknowledgement").exists()).toBe(false);
    await confirm.trigger("click");
    expect(reviewEventCalls("execute_import")).toHaveLength(0);

    wrapper.unmount();
  });

  it("blocks an incomplete decision contract", async () => {
    const state = reviewedPreviewState();
    const review = state.preview?.import_review;
    if (!review) throw new Error("review fixture missing");

    review.speaker_decisions[0] = {
      ...review.speaker_decisions[0]!,
      reasons: [],
    };

    const wrapper = mountPanel(state);
    const confirm = wrapper.get("#yarn-import-confirm");

    expect(wrapper.find('[data-testid="yarn-import-review-incomplete"]').exists()).toBe(true);
    expect(confirm.attributes("disabled")).toBeDefined();
    await confirm.trigger("click");
    expect(reviewEventCalls("execute_import")).toHaveLength(0);

    wrapper.unmount();
  });

  it("fails closed when a Yarn preview has no prefix review", async () => {
    const wrapper = mountPanel(attemptState("ready", "preview"));

    expect(wrapper.find("#yarn-import-review").exists()).toBe(false);
    expect(wrapper.find('[data-testid="yarn-import-review-missing"]').exists()).toBe(true);
    expect(wrapper.find("#yarn-import-review-acknowledgement").exists()).toBe(false);

    const confirm = wrapper.get("#yarn-import-confirm");
    expect(confirm.attributes("disabled")).toBeDefined();
    await confirm.trigger("click");

    expect(reviewEventCalls("execute_import")).toHaveLength(0);

    wrapper.unmount();
  });
});
