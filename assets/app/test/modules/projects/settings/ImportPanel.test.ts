import { mount } from "@vue/test-utils";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import ConfirmDialog from "../../../../components/ConfirmDialog.vue";
import type { ImportState } from "../../../../modules/projects/settings/export-import/types";
import { createMockLive, setTestLocale } from "../../../setup";

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
    stage: null,
    attemptId: null,
    preview: null,
    conflictStrategy: "rename",
    importMode: "additive",
    replaceEligible: false,
    warningCodes: [],
    status: null,
  };
}

function stageForStatus(
  status: NonNullable<ImportState["status"]>,
): NonNullable<ImportState["stage"]> {
  switch (status) {
    case "ready":
      return "parsed";
    case "running":
      return "materializing";
    case "completed":
      return "completed";
    case "failed":
      return "failed";
    case "expired":
      return "expired";
    case "queued":
      return "queued";
    case "retrying":
      return "retrying";
  }
}

function attemptState(
  status: NonNullable<ImportState["status"]>,
  step: ImportState["step"] = "queued",
  attemptId = 42,
): ImportState {
  return {
    step,
    stage: stageForStatus(status),
    attemptId,
    preview: {
      counts: { flows: 2, nodes: 4 },
      conflicts: {},
      has_conflicts: false,
    },
    conflictStrategy: "rename",
    importMode: "additive",
    replaceEligible: false,
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
            allowed_actions: ["create_sheet", "preserve_literal", "map_to_sheet"],
            confidence: "medium",
            reasons: ["literal_character_name"],
          },
          {
            speaker: "Capsely",
            occurrences: 3,
            suggested_action: "create_sheet",
            allowed_actions: ["create_sheet", "preserve_literal", "map_to_sheet"],
            confidence: "low",
            reasons: ["literal_character_name"],
          },
          {
            speaker: "SlideImage",
            occurrences: 14,
            suggested_action: "preserve_literal",
            allowed_actions: ["create_sheet", "preserve_literal", "map_to_sheet"],
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

function replacementPreviewState(
  importMode: ImportState["importMode"] = "replace_project",
): ImportState {
  return {
    ...resolvedPreviewState(),
    importMode,
    replaceEligible: true,
  };
}

const RESUME_STORAGE_KEY = "storyarn:project-import:opaque-resume-token";
const OTHER_RESUME_STORAGE_KEY = "storyarn:project-import:other-opaque-token";

function mountPanel(
  importState: ImportState = uploadState(),
  resumeStorageKey = RESUME_STORAGE_KEY,
) {
  return mount(ImportPanel, {
    props: {
      canImport: true,
      resumeStorageKey,
      importState,
      uploadConfig: null,
    },
  });
}

function storageKey(attemptId = 42, namespace = RESUME_STORAGE_KEY) {
  return `${namespace}:attempt:${attemptId}`;
}

function storedAttempt(attemptId = 42, savedAt = Date.now()) {
  return JSON.stringify({ version: 1, attemptId, savedAt });
}

function dismissalKey(attemptId = 42, namespace = RESUME_STORAGE_KEY) {
  return `${namespace}:dismissed:${attemptId}`;
}

function storedDismissal(attemptId = 42, savedAt = Date.now()) {
  return JSON.stringify({
    version: 1,
    kind: "server_confirmed_reset",
    attemptId,
    savedAt,
  });
}

function dispatchStorageChange(
  oldValue: string | null,
  newValue: string | null,
  key = storageKey(),
) {
  window.dispatchEvent(
    new StorageEvent("storage", {
      key,
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
    setTestLocale("en");
    window.localStorage.clear();
    window.sessionStorage.clear();
  });

  afterEach(() => {
    window.localStorage.clear();
    window.sessionStorage.clear();
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
  ])("ignores a %s without contacting the server", (_label, buildStoredValue) => {
    window.localStorage.setItem(storageKey(), buildStoredValue());

    const wrapper = mountPanel();

    expect(mockLive.pushEvent).not.toHaveBeenCalled();
    expect(window.localStorage.getItem(storageKey())).not.toBeNull();

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

  it("stores only versioned non-content metadata under an opaque server key", () => {
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

  it("does not consume an attempt from another opaque storage namespace", () => {
    const otherKey = storageKey(81, OTHER_RESUME_STORAGE_KEY);
    window.localStorage.setItem(otherKey, storedAttempt(81));

    const wrapper = mountPanel();

    expect(mockLive.pushEvent).not.toHaveBeenCalled();
    expect(window.localStorage.getItem(otherKey)).not.toBeNull();

    wrapper.unmount();
  });

  it("resumes matching keys from the per-tab storage fallback", () => {
    const wrapper = mountPanel();
    const stored = storedAttempt();

    window.sessionStorage.setItem(storageKey(), stored);
    window.dispatchEvent(
      new StorageEvent("storage", {
        key: storageKey(),
        newValue: stored,
        storageArea: window.sessionStorage,
      }),
    );

    expect(reviewEventCalls("resume_import")).toHaveLength(1);
    expect(reviewEventCalls("resume_import")[0]?.[1]).toEqual({ attempt_id: 42 });

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

  it("does not restart reconciliation after the current attempt is definitively missing", () => {
    const wrapper = mountPanel(attemptState("queued"));
    vi.clearAllMocks();

    vi.advanceTimersByTime(3_000);
    const callback = reviewEventCalls("reconcile_import")[0]?.[2];
    callback?.({ ok: false, reason: "not_found" });
    vi.clearAllMocks();
    vi.advanceTimersByTime(60_000);

    expect(mockLive.pushEvent).not.toHaveBeenCalled();
    expect(window.localStorage.getItem(storageKey())).toBeNull();

    wrapper.unmount();
  });

  it("keeps a capped retry armed after the initial exponential backoff", () => {
    window.localStorage.setItem(storageKey(), storedAttempt());

    const wrapper = mountPanel();
    expect(mockLive.pushEvent).toHaveBeenCalledTimes(1);

    reviewEventCalls("resume_import").at(-1)?.[2]?.({ ok: false, reason: "unavailable" });
    vi.advanceTimersByTime(1_000);
    expect(mockLive.pushEvent).toHaveBeenCalledTimes(2);

    reviewEventCalls("resume_import").at(-1)?.[2]?.({ ok: false, reason: "unavailable" });
    vi.advanceTimersByTime(2_000);
    expect(mockLive.pushEvent).toHaveBeenCalledTimes(3);

    reviewEventCalls("resume_import").at(-1)?.[2]?.({ ok: false, reason: "unavailable" });
    vi.advanceTimersByTime(4_000);
    expect(mockLive.pushEvent).toHaveBeenCalledTimes(4);

    reviewEventCalls("resume_import").at(-1)?.[2]?.({ ok: false, reason: "unavailable" });
    vi.advanceTimersByTime(29_999);
    expect(mockLive.pushEvent).toHaveBeenCalledTimes(4);

    vi.advanceTimersByTime(1);
    expect(mockLive.pushEvent).toHaveBeenCalledTimes(5);
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

    const next = storedAttempt(43, Date.now() + 1);
    window.localStorage.setItem(storageKey(43), next);
    dispatchStorageChange(null, next, storageKey(43));

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
    expect(window.localStorage.getItem(storageKey(42))).not.toBeNull();
    expect(JSON.parse(window.localStorage.getItem(storageKey(43)) ?? "{}").attemptId).toBe(43);

    wrapper.unmount();
  });

  it("adopts a newer stored attempt when mounting with an older attempt displayed", () => {
    window.localStorage.setItem(storageKey(44), storedAttempt(44, Date.now() + 1));

    const wrapper = mountPanel(attemptState("queued"));

    expect(mockLive.pushEvent).toHaveBeenCalledWith(
      "resume_import",
      { attempt_id: 44 },
      expect.any(Function),
      expect.any(Function),
    );
    expect(window.localStorage.getItem(storageKey(42))).not.toBeNull();
    expect(window.localStorage.getItem(storageKey(44))).not.toBeNull();

    wrapper.unmount();
  });

  it("cancels an older pending resume when newer props become authoritative", async () => {
    const wrapper = mountPanel(attemptState("queued", "queued", 42));
    const pending = storedAttempt(43, Date.now() + 1);
    vi.clearAllMocks();

    window.localStorage.setItem(storageKey(43), pending);
    dispatchStorageChange(null, pending, storageKey(43));
    const staleReply = reviewEventCalls("resume_import")[0]?.[2];

    // C reaches LiveView props before its already-durable storage event. B is
    // now older and must not be allowed to retry or roll the panel backwards.
    window.localStorage.setItem(storageKey(44), storedAttempt(44, Date.now() + 2));
    await wrapper.setProps({ importState: attemptState("queued", "queued", 44) });
    staleReply?.({ ok: false, reason: "unavailable" });
    vi.advanceTimersByTime(60_000);

    expect(reviewEventCalls("resume_import")).toHaveLength(1);
    expect(window.localStorage.getItem(storageKey(42))).not.toBeNull();
    expect(window.localStorage.getItem(storageKey(43))).not.toBeNull();
    expect(window.localStorage.getItem(storageKey(44))).not.toBeNull();

    wrapper.unmount();
  });

  it("keeps a pending resume when it is newer than the props now rendered", async () => {
    const wrapper = mountPanel(attemptState("queued", "queued", 42));
    const pending = storedAttempt(45, Date.now() + 2);
    vi.clearAllMocks();

    window.localStorage.setItem(storageKey(45), pending);
    dispatchStorageChange(null, pending, storageKey(45));
    const pendingReply = reviewEventCalls("resume_import")[0]?.[2];

    await wrapper.setProps({ importState: attemptState("queued", "queued", 44) });
    pendingReply?.({ ok: false, reason: "unavailable" });
    vi.advanceTimersByTime(1_000);

    expect(reviewEventCalls("resume_import")).toHaveLength(2);
    expect(window.localStorage.getItem(storageKey(42))).not.toBeNull();
    expect(window.localStorage.getItem(storageKey(44))).not.toBeNull();
    expect(window.localStorage.getItem(storageKey(45))).not.toBeNull();

    wrapper.unmount();
  });

  it("does not treat ordinary cache eviction as cancellation", () => {
    const wrapper = mountPanel(attemptState("queued"));
    const current = window.localStorage.getItem(storageKey());
    vi.clearAllMocks();

    window.localStorage.removeItem(storageKey());
    dispatchStorageChange(current, null);
    vi.advanceTimersByTime(3_000);

    expect(mockLive.pushEvent).toHaveBeenCalledWith(
      "reconcile_import",
      { attempt_id: 42 },
      expect.any(Function),
      expect.any(Function),
    );

    wrapper.unmount();
  });

  it("adopts an explicit server-confirmed reset from another tab", () => {
    const wrapper = mountPanel();
    const next = storedAttempt();

    window.localStorage.setItem(storageKey(), next);
    dispatchStorageChange(null, next);
    expect(reviewEventCalls("resume_import")).toHaveLength(1);

    const dismissal = storedDismissal();
    window.localStorage.setItem(dismissalKey(), dismissal);
    dispatchStorageChange(null, dismissal, dismissalKey());
    vi.advanceTimersByTime(60_000);

    expect(reviewEventCalls("resume_import")).toHaveLength(1);
    expect(window.localStorage.getItem(storageKey())).toBeNull();
    expect(window.localStorage.getItem(dismissalKey())).toBe(dismissal);

    wrapper.unmount();
  });

  it("clears a terminal attempt after another tab confirms its reset", async () => {
    const wrapper = mountPanel(attemptState("completed", "done"));
    const dismissal = storedDismissal();
    vi.clearAllMocks();

    window.localStorage.setItem(dismissalKey(), dismissal);
    dispatchStorageChange(null, dismissal, dismissalKey());
    vi.advanceTimersByTime(3_000);

    expect(mockLive.pushEvent).toHaveBeenCalledWith(
      "reset_import",
      { attempt_id: 42 },
      expect.any(Function),
      expect.any(Function),
    );

    reviewEventCalls("reset_import")[0]?.[2]?.({ ok: true, attempt_id: 42 });
    await wrapper.setProps({ importState: uploadState() });
    vi.clearAllMocks();
    vi.advanceTimersByTime(30_000);

    expect(mockLive.pushEvent).not.toHaveBeenCalled();
    expect(window.localStorage.getItem(storageKey())).toBeNull();

    wrapper.unmount();
  });

  it("retries a transient ready-preview recovery conflict", () => {
    const state: ImportState = {
      ...attemptState("ready", "error"),
      errorCode: "import_state_changed",
    };
    const wrapper = mountPanel(state);
    vi.clearAllMocks();

    vi.advanceTimersByTime(3_000);

    expect(mockLive.pushEvent).toHaveBeenCalledWith(
      "reconcile_import",
      { attempt_id: 42 },
      expect.any(Function),
      expect.any(Function),
    );

    wrapper.unmount();
  });

  it.each([
    ["malformed", () => "not-json", dismissalKey()],
    [
      "wrong kind",
      () =>
        JSON.stringify({
          version: 1,
          kind: "cache_eviction",
          attemptId: 42,
          savedAt: Date.now(),
        }),
      dismissalKey(),
    ],
    ["mismatched id", () => storedDismissal(43), dismissalKey()],
    ["expired", () => storedDismissal(42, Date.now() - 7 * 86_400_000 - 1), dismissalKey()],
  ])("does not let a %s tombstone stop an active import", (_label, buildDismissal, key) => {
    const wrapper = mountPanel(attemptState("queued"));
    const dismissal = buildDismissal();
    vi.clearAllMocks();

    window.localStorage.setItem(key, dismissal);
    dispatchStorageChange(null, dismissal, key);
    vi.advanceTimersByTime(3_000);

    expect(mockLive.pushEvent).toHaveBeenCalledWith(
      "reconcile_import",
      { attempt_id: 42 },
      expect.any(Function),
      expect.any(Function),
    );

    wrapper.unmount();
  });

  it("preserves the displayed attempt when another tab clears only its newer attempt", () => {
    const wrapper = mountPanel(attemptState("queued"));
    const newer = storedAttempt(43, Date.now() + 1);
    vi.clearAllMocks();

    // Tab B publishes attempt 43 while this tab is still displaying attempt
    // 42, so 43 becomes the pending cross-tab resume.
    window.localStorage.setItem(storageKey(43), newer);
    dispatchStorageChange(null, newer, storageKey(43));
    expect(reviewEventCalls("resume_import")).toHaveLength(1);

    // Tab B then confirms a server-side reset for only 43. Attempt 42 must
    // regain both persistence and its reconciliation timer.
    const dismissal = storedDismissal(43, Date.now() + 2);
    window.localStorage.setItem(dismissalKey(43), dismissal);
    dispatchStorageChange(null, dismissal, dismissalKey(43));

    const restored = JSON.parse(window.localStorage.getItem(storageKey()) ?? "{}");
    expect(restored.attemptId).toBe(42);

    vi.clearAllMocks();
    vi.advanceTimersByTime(3_000);

    expect(mockLive.pushEvent).toHaveBeenCalledWith(
      "reconcile_import",
      { attempt_id: 42 },
      expect.any(Function),
      expect.any(Function),
    );

    wrapper.unmount();
  });

  it("restores the displayed attempt when the newer cross-tab attempt is missing", () => {
    const wrapper = mountPanel(attemptState("queued"));
    const newer = storedAttempt(43, Date.now() + 1);
    vi.clearAllMocks();

    window.localStorage.setItem(storageKey(43), newer);
    dispatchStorageChange(null, newer, storageKey(43));

    const resumeCall = reviewEventCalls("resume_import")[0];
    resumeCall?.[2]?.({ ok: false, reason: "not_found" });

    const restored = JSON.parse(window.localStorage.getItem(storageKey()) ?? "{}");
    expect(restored.attemptId).toBe(42);

    vi.clearAllMocks();
    vi.advanceTimersByTime(3_000);

    expect(mockLive.pushEvent).toHaveBeenCalledWith(
      "reconcile_import",
      { attempt_id: 42 },
      expect.any(Function),
      expect.any(Function),
    );

    wrapper.unmount();
  });

  it("keeps polling the active attempt when a terminal reference is superseded", () => {
    const wrapper = mountPanel(attemptState("queued"));
    const newerTerminal = storedAttempt(43, Date.now() + 1);
    vi.clearAllMocks();

    window.localStorage.setItem(storageKey(43), newerTerminal);
    dispatchStorageChange(null, newerTerminal, storageKey(43));
    reviewEventCalls("resume_import")[0]?.[2]?.({ ok: false, reason: "superseded" });

    expect(window.localStorage.getItem(storageKey(43))).toBe(newerTerminal);

    vi.clearAllMocks();
    vi.advanceTimersByTime(3_000);

    expect(mockLive.pushEvent).toHaveBeenCalledWith(
      "reconcile_import",
      { attempt_id: 42 },
      expect.any(Function),
      expect.any(Function),
    );
    expect(reviewEventCalls("resume_import")).toHaveLength(0);

    wrapper.unmount();
  });

  it("tries the next durable reference when the newest one is superseded", () => {
    window.localStorage.setItem(storageKey(42), storedAttempt(42, Date.now() - 1));
    window.localStorage.setItem(storageKey(43), storedAttempt(43, Date.now()));

    const wrapper = mountPanel();
    expect(reviewEventCalls("resume_import")[0]?.[1]).toEqual({ attempt_id: 43 });

    reviewEventCalls("resume_import")[0]?.[2]?.({ ok: false, reason: "superseded" });

    expect(reviewEventCalls("resume_import").map(([, payload]) => payload)).toEqual([
      { attempt_id: 43 },
      { attempt_id: 42 },
    ]);
    expect(window.localStorage.getItem(storageKey(43))).not.toBeNull();

    wrapper.unmount();
  });

  it("reconsiders a temporarily superseded terminal after the active blocker finishes", async () => {
    const wrapper = mountPanel(attemptState("queued", "queued", 42));
    const terminal = storedAttempt(43, Date.now() + 1);
    vi.clearAllMocks();

    window.localStorage.setItem(storageKey(43), terminal);
    dispatchStorageChange(null, terminal, storageKey(43));
    reviewEventCalls("resume_import")[0]?.[2]?.({ ok: false, reason: "superseded" });

    await wrapper.setProps({ importState: attemptState("completed", "done", 42) });

    expect(reviewEventCalls("resume_import").map(([, payload]) => payload)).toEqual([
      { attempt_id: 43 },
      { attempt_id: 43 },
    ]);
    expect(window.localStorage.getItem(storageKey(43))).toBe(terminal);

    wrapper.unmount();
  });

  it("does not overwrite a third-tab attempt when a pending resume fails", () => {
    const wrapper = mountPanel(attemptState("queued"));
    const pending = storedAttempt(43, Date.now() + 1);
    const newest = storedAttempt(44, Date.now() + 2);
    vi.clearAllMocks();

    window.localStorage.setItem(storageKey(43), pending);
    dispatchStorageChange(null, pending, storageKey(43));

    // Tab C writes attempt 44 before this tab receives its storage event.
    // The definitive reply for B arrives first.
    window.localStorage.setItem(storageKey(44), newest);
    reviewEventCalls("resume_import")[0]?.[2]?.({ ok: false, reason: "not_found" });

    expect(window.localStorage.getItem(storageKey(42))).not.toBeNull();
    expect(window.localStorage.getItem(storageKey(43))).toBeNull();
    expect(JSON.parse(window.localStorage.getItem(storageKey(44)) ?? "{}").attemptId).toBe(44);
    expect(reviewEventCalls("resume_import").map(([, payload]) => payload)).toEqual([
      { attempt_id: 43 },
      { attempt_id: 44 },
    ]);

    // The queued event for C must not start a duplicate request.
    dispatchStorageChange(null, newest, storageKey(44));
    expect(reviewEventCalls("resume_import")).toHaveLength(2);

    wrapper.unmount();
  });

  it("waits for the third tab's addition event after an unrelated cache eviction", () => {
    const wrapper = mountPanel(attemptState("queued"));
    const pending = storedAttempt(43, Date.now() + 1);
    const newest = storedAttempt(44, Date.now() + 2);
    vi.clearAllMocks();

    window.localStorage.setItem(storageKey(43), pending);
    dispatchStorageChange(null, pending, storageKey(43));

    // C is already durable, but its addition event is still queued when B's
    // removal event is handled.
    window.localStorage.setItem(storageKey(44), newest);
    window.localStorage.removeItem(storageKey(43));
    dispatchStorageChange(pending, null, storageKey(43));

    expect(window.localStorage.getItem(storageKey(42))).not.toBeNull();
    expect(window.localStorage.getItem(storageKey(43))).toBeNull();
    expect(JSON.parse(window.localStorage.getItem(storageKey(44)) ?? "{}").attemptId).toBe(44);
    expect(reviewEventCalls("resume_import").map(([, payload]) => payload)).toEqual([
      { attempt_id: 43 },
    ]);

    dispatchStorageChange(null, newest, storageKey(44));
    expect(reviewEventCalls("resume_import").map(([, payload]) => payload)).toEqual([
      { attempt_id: 43 },
      { attempt_id: 44 },
    ]);

    wrapper.unmount();
  });

  it("reconciles the displayed attempt after newer cross-tab resume retries are exhausted", () => {
    const wrapper = mountPanel(attemptState("queued"));
    const newer = storedAttempt(43, Date.now() + 1);
    vi.clearAllMocks();

    window.localStorage.setItem(storageKey(43), newer);
    dispatchStorageChange(null, newer, storageKey(43));

    for (const delay of [1_000, 2_000, 4_000]) {
      reviewEventCalls("resume_import").at(-1)?.[2]?.({ ok: false, reason: "unavailable" });
      vi.advanceTimersByTime(delay);
    }

    reviewEventCalls("resume_import").at(-1)?.[2]?.({ ok: false, reason: "unavailable" });
    expect(reviewEventCalls("resume_import")).toHaveLength(4);

    vi.clearAllMocks();
    vi.advanceTimersByTime(3_000);

    expect(mockLive.pushEvent).toHaveBeenCalledWith(
      "reconcile_import",
      { attempt_id: 42 },
      expect.any(Function),
      expect.any(Function),
    );
    expect(JSON.parse(window.localStorage.getItem(storageKey(43)) ?? "{}").attemptId).toBe(43);

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

    expect(JSON.parse(window.localStorage.getItem(storageKey(43)) ?? "{}").attemptId).toBe(43);
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

  it("falls back to per-tab storage when localStorage writes are disabled", () => {
    const originalSetItem = Storage.prototype.setItem;
    const storageSpy = vi.spyOn(Storage.prototype, "setItem").mockImplementation(function (
      this: Storage,
      key: string,
      value: string,
    ) {
      if (this === window.localStorage) {
        throw new DOMException("Storage disabled", "SecurityError");
      }

      return originalSetItem.call(this, key, value);
    });

    const wrapper = mountPanel(attemptState("queued"));

    expect(window.localStorage.getItem(storageKey())).toBeNull();
    expect(JSON.parse(window.sessionStorage.getItem(storageKey()) ?? "{}").attemptId).toBe(42);

    wrapper.unmount();
    storageSpy.mockRestore();
    vi.clearAllMocks();

    const remounted = mountPanel();
    expect(reviewEventCalls("resume_import")[0]?.[1]).toEqual({ attempt_id: 42 });

    remounted.unmount();
  });

  it("clears the persisted reference only after the server confirms the reset", async () => {
    const wrapper = mountPanel(attemptState("completed", "done"));
    expect(window.localStorage.getItem(storageKey())).not.toBeNull();

    await wrapper.get('[data-testid="yarn-import-reset"]').trigger("click");

    expect(mockLive.pushEvent).toHaveBeenCalledWith(
      "reset_import",
      { attempt_id: 42 },
      expect.any(Function),
    );

    // The durable reference must survive until the server has terminalized
    // the attempt — clearing first re-creates the original lost-progress bug.
    expect(window.localStorage.getItem(storageKey())).not.toBeNull();

    const resetCall = vi
      .mocked(mockLive.pushEvent)
      .mock.calls.find(([event]) => event === "reset_import");

    resetCall?.[2]?.({ ok: true, attempt_id: 42 });

    expect(window.localStorage.getItem(storageKey())).toBeNull();
    expect(JSON.parse(window.localStorage.getItem(dismissalKey()) ?? "{}")).toEqual({
      version: 1,
      kind: "server_confirmed_reset",
      attemptId: 42,
      savedAt: Date.now(),
    });

    wrapper.unmount();
  });

  it("preserves independent older attempts when resetting the current one", async () => {
    window.localStorage.setItem(storageKey(42), storedAttempt(42, Date.now() - 2));
    window.localStorage.setItem(storageKey(43), storedAttempt(43, Date.now() - 1));
    const wrapper = mountPanel(attemptState("completed", "done", 44));

    expect(window.localStorage.getItem(storageKey(42))).not.toBeNull();
    expect(window.localStorage.getItem(storageKey(43))).not.toBeNull();
    expect(window.localStorage.getItem(storageKey(44))).not.toBeNull();

    // A delayed write from an older tab remains independently recoverable. ID
    // order does not prove that its import has stopped materializing.
    const delayedOlder = storedAttempt(43, Date.now());
    window.localStorage.setItem(storageKey(43), delayedOlder);
    dispatchStorageChange(null, delayedOlder, storageKey(43));
    expect(window.localStorage.getItem(storageKey(43))).toBe(delayedOlder);

    await wrapper.get('[data-testid="yarn-import-reset"]').trigger("click");
    const resetCall = reviewEventCalls("reset_import")[0];
    resetCall?.[2]?.({ ok: true, attempt_id: 44 });

    expect(reviewEventCalls("resume_import").map(([, payload]) => payload)).toEqual([
      { attempt_id: 43 },
    ]);

    await wrapper.setProps({ importState: uploadState() });
    wrapper.unmount();

    vi.clearAllMocks();
    const remounted = mountPanel();

    expect(reviewEventCalls("resume_import").map(([, payload]) => payload)).toEqual([
      { attempt_id: 43 },
    ]);
    expect(window.localStorage.getItem(storageKey(42))).not.toBeNull();
    expect(window.localStorage.getItem(storageKey(43))).not.toBeNull();
    expect(window.localStorage.getItem(storageKey(44))).toBeNull();

    remounted.unmount();
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

  it("does not clear a newer cross-tab attempt when a local error has no attempt id", async () => {
    const state = Object.assign(
      {
        ...uploadState(),
        step: "error",
        status: "failed",
        errorCode: "unexpected_error",
      } satisfies ImportState,
      { error: "Server prose must never be rendered" },
    );
    const wrapper = mountPanel(state);

    const next = storedAttempt(43);
    window.localStorage.setItem(storageKey(43), next);
    dispatchStorageChange(null, next, storageKey(43));

    expect(mockLive.pushEvent).toHaveBeenCalledWith(
      "resume_import",
      { attempt_id: 43 },
      expect.any(Function),
      expect.any(Function),
    );

    await wrapper.get('[data-testid="yarn-import-reset"]').trigger("click");
    expect(mockLive.pushEvent).toHaveBeenCalledWith("reset_import", { attempt_id: null });

    expect(JSON.parse(window.localStorage.getItem(storageKey(43)) ?? "{}").attemptId).toBe(43);

    const resumeCall = reviewEventCalls("resume_import")[0];
    resumeCall?.[2]?.({ ok: false, reason: "unavailable" });
    vi.advanceTimersByTime(1_000);

    expect(reviewEventCalls("resume_import")).toHaveLength(2);
    wrapper.unmount();
  });

  it("renders terminal failures from a localized code instead of persisted prose", () => {
    const wrapper = mountPanel(
      Object.assign(
        {
          ...uploadState(),
          step: "error",
          status: "failed",
          errorCode: "project_already_has_main_flow",
        } satisfies ImportState,
        { error: "Persisted English prose with private details" },
      ),
    );

    const alert = wrapper.get('[data-testid="yarn-import-terminal-error"]');
    expect(alert.text()).toContain("already has a main flow");
    expect(alert.text()).not.toContain("Persisted English prose");
    expect(alert.text()).not.toContain("project_already_has_main_flow");

    wrapper.unmount();
  });

  it("renders terminal failure copy in the active locale", () => {
    setTestLocale("es");
    const wrapper = mountPanel(
      Object.assign(
        {
          ...uploadState(),
          step: "error",
          status: "failed",
          errorCode: "project_already_has_main_flow",
        } satisfies ImportState,
        { error: "This persisted message is deliberately English" },
      ),
    );

    const alert = wrapper.get('[data-testid="yarn-import-terminal-error"]');
    expect(alert.text()).toContain("ya tiene un flujo principal");
    expect(alert.text()).not.toContain("This persisted message");

    wrapper.unmount();
  });

  it("offers replacement only for an eligible Yarn project", () => {
    const ineligible = mountPanel(resolvedPreviewState());
    expect(ineligible.find('[data-testid="yarn-import-mode-selector"]').exists()).toBe(false);
    ineligible.unmount();

    const eligible = mountPanel(replacementPreviewState("additive"));
    const selector = eligible.get('[data-testid="yarn-import-mode-selector"]');
    const replaceRadio = selector.get('[data-testid="yarn-import-mode-replace"] [role="radio"]');

    expect(selector.text()).toContain("How should this project be imported?");
    expect(replaceRadio.attributes("disabled")).toBeUndefined();

    eligible.unmount();
  });

  it("persists an explicit replacement choice without exposing source metadata", async () => {
    const wrapper = mountPanel(replacementPreviewState("additive"));

    await wrapper.get('[data-testid="yarn-import-mode-replace"] [role="radio"]').trigger("click");

    expect(mockLive.pushEvent).toHaveBeenCalledWith("set_import_mode", {
      attempt_id: 42,
      import_mode: "replace_project",
    });
    expect(reviewEventCalls("set_import_mode")[0]?.[1]).toEqual({
      attempt_id: 42,
      import_mode: "replace_project",
    });

    wrapper.unmount();
  });

  it("hides additive conflict controls when replacement is selected", () => {
    const state = replacementPreviewState();
    if (!state.preview) throw new Error("preview fixture missing");
    state.preview.has_conflicts = true;
    state.preview.conflicts = { sheets: ["alice"] };

    const wrapper = mountPanel(state);

    expect(wrapper.find("#yarn-import-conflict-strategy-label").exists()).toBe(false);
    expect(wrapper.text()).not.toContain("alice");

    wrapper.unmount();
  });

  it("requires destructive confirmation and binds it to the replacement execution", async () => {
    const wrapper = mountPanel(replacementPreviewState());

    await wrapper.get("#yarn-import-confirm").trigger("click");

    expect(reviewEventCalls("execute_import")).toHaveLength(0);
    const confirmation = wrapper.getComponent(ConfirmDialog);
    expect(confirmation.props("open")).toBe(true);
    expect(confirmation.props("description")).toContain("If the snapshot cannot be prepared");

    confirmation.vm.$emit("confirm");
    await wrapper.vm.$nextTick();

    expect(mockLive.pushEvent).toHaveBeenCalledWith(
      "execute_import",
      {
        attempt_id: 42,
        review_confirmation_fingerprint: "resolution-fingerprint",
        import_mode: "replace_project",
        replace_acknowledged: true,
      },
      expect.any(Function),
      expect.any(Function),
    );

    wrapper.unmount();
  });

  it("closes replacement confirmation when cross-tab recovery swaps the attempt", async () => {
    const wrapper = mountPanel(replacementPreviewState());

    await wrapper.get("#yarn-import-confirm").trigger("click");
    const confirmation = wrapper.getComponent(ConfirmDialog);
    expect(confirmation.props("open")).toBe(true);

    const newerAttempt = replacementPreviewState();
    newerAttempt.attemptId = 43;
    await wrapper.setProps({ importState: newerAttempt });

    expect(confirmation.props("open")).toBe(false);
    confirmation.vm.$emit("confirm");
    await wrapper.vm.$nextTick();
    expect(reviewEventCalls("execute_import")).toHaveLength(0);

    wrapper.unmount();
  });

  it("closes replacement confirmation when the validated review fingerprint changes", async () => {
    const wrapper = mountPanel(replacementPreviewState());

    await wrapper.get("#yarn-import-confirm").trigger("click");
    const confirmation = wrapper.getComponent(ConfirmDialog);
    expect(confirmation.props("open")).toBe(true);

    const changedReview = replacementPreviewState();
    if (!changedReview.preview?.import_review_resolution) {
      throw new Error("review resolution fixture missing");
    }
    changedReview.preview.import_review_resolution.decision_fingerprint = "new-resolution";
    await wrapper.setProps({ importState: changedReview });

    expect(confirmation.props("open")).toBe(false);
    confirmation.vm.$emit("confirm");
    await wrapper.vm.$nextTick();
    expect(reviewEventCalls("execute_import")).toHaveLength(0);

    wrapper.unmount();
  });

  it.each([
    ["stale_import_mode", "changed in another tab"],
    ["replace_import_confirmation_required", "confirmation is no longer current"],
    ["import_replace_not_eligible", "is not eligible to replace"],
    ["invalid_import_snapshot_request", "cannot create a recovery snapshot"],
  ])("keeps recoverable preflight error %s on the preview", (errorCode, expectedCopy) => {
    const state = replacementPreviewState();
    state.errorCode = errorCode;
    const wrapper = mountPanel(state);

    expect(wrapper.get('[data-testid="yarn-import-preflight-error"]').text()).toContain(
      expectedCopy,
    );
    expect(wrapper.find('[data-testid="yarn-import-terminal-error"]').exists()).toBe(false);
    expect(wrapper.find("#yarn-import-confirm").exists()).toBe(true);

    wrapper.unmount();
  });

  it("uses the preview error instead of a generic transport error for recoverable preflight", async () => {
    const wrapper = mountPanel(replacementPreviewState());

    await wrapper.get("#yarn-import-confirm").trigger("click");
    wrapper.getComponent(ConfirmDialog).vm.$emit("confirm");
    await wrapper.vm.$nextTick();

    reviewEventCalls("execute_import")[0]?.[2]?.({ ok: false, reason: "recoverable" });

    const recovered = replacementPreviewState("additive");
    recovered.errorCode = "stale_import_mode";
    await wrapper.setProps({ importState: recovered });

    expect(wrapper.get('[data-testid="yarn-import-preflight-error"]').text()).toContain(
      "changed in another tab",
    );
    expect(wrapper.find('[data-testid="yarn-import-review-error"]').exists()).toBe(false);

    wrapper.unmount();
  });

  it("renders snapshot preparation as recoverable background work", () => {
    const state = {
      ...attemptState("queued"),
      stage: "awaiting_snapshot",
      importMode: "replace_project",
      replaceEligible: true,
    } satisfies ImportState;
    const wrapper = mountPanel(state);

    const notice = wrapper.get('[data-testid="yarn-import-awaiting-snapshot"]');
    expect(notice.text()).toContain("Creating a recovery snapshot");
    expect(notice.text()).toContain("Nothing changes until the snapshot is complete and verified");
    expect(wrapper.find('[data-testid="yarn-import-processing"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="yarn-import-reset"]').exists()).toBe(true);

    wrapper.unmount();
  });

  it.each([
    ["completed", "done"],
    ["failed", "error"],
  ] as const)(
    "links a %s replacement result to the server-derived recovery snapshot area",
    (status, step) => {
      const recoverySnapshotUrl =
        "/workspaces/opaque-workspace/projects/opaque-project/settings/snapshots#snapshot-91";
      const state = {
        ...attemptState(status, step),
        importMode: "replace_project",
        replaceEligible: true,
        recoverySnapshotUrl,
        errorCode: status === "failed" ? "import_project_replacement_failed" : null,
      } satisfies ImportState;
      const wrapper = mountPanel(state);

      const link = wrapper.get('[data-testid="yarn-import-recovery-snapshot-link"]');
      expect(link.attributes("href")).toBe(recoverySnapshotUrl);
      expect(link.text()).toContain("View recovery snapshot");

      wrapper.unmount();
    },
  );

  it("never renders a recovery snapshot link for an additive result", () => {
    const state = {
      ...attemptState("completed", "done"),
      recoverySnapshotUrl:
        "/workspaces/opaque-workspace/projects/opaque-project/settings/snapshots#snapshot-91",
    } satisfies ImportState;
    const wrapper = mountPanel(state);

    expect(wrapper.find('[data-testid="yarn-import-recovery-snapshot-link"]').exists()).toBe(false);

    wrapper.unmount();
  });

  it("renders the replacement safety contract in Spanish", () => {
    setTestLocale("es");
    const wrapper = mountPanel(replacementPreviewState());

    expect(wrapper.get('[data-testid="yarn-import-mode-replace"]').text()).toContain(
      "Reemplazar el contenido narrativo",
    );
    expect(wrapper.get("#yarn-import-confirm").text()).toContain(
      "Reemplazar contenido del proyecto",
    );

    wrapper.unmount();
  });

  it("localizes the recovery snapshot link in Spanish", () => {
    setTestLocale("es");
    const state = {
      ...attemptState("completed", "done"),
      importMode: "replace_project",
      replaceEligible: true,
      recoverySnapshotUrl:
        "/workspaces/opaque-workspace/projects/opaque-project/settings/snapshots#snapshot-91",
    } satisfies ImportState;
    const wrapper = mountPanel(state);

    expect(wrapper.get('[data-testid="yarn-import-recovery-snapshot-link"]').text()).toContain(
      "Ver snapshot de recuperación",
    );

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
        attempt_id: 42,
        review_decisions: [{ speaker: "Capsley", action: "create_sheet" }],
      },
      expect.any(Function),
      expect.any(Function),
    );

    wrapper.unmount();
  });

  it("gives every speaker decision radio group an accessible name", () => {
    const wrapper = mountPanel(reviewedPreviewState());
    const groups = wrapper.findAll('#yarn-import-review [role="radiogroup"]');

    expect(groups).toHaveLength(3);
    groups.forEach((group, index) => {
      const labelId = `yarn-speaker-${index}-label`;
      expect(group.attributes("aria-labelledby")).toBe(labelId);
      expect(wrapper.get(`#${labelId}`).text()).not.toBe("");
    });

    wrapper.unmount();
  });

  it("gives the conflict strategy radio group an accessible name", () => {
    const state = reviewedPreviewState();
    if (!state.preview) throw new Error("preview fixture missing");
    state.preview.has_conflicts = true;
    state.preview.conflicts = { sheets: ["alice"] };

    const wrapper = mountPanel(state);
    const group = wrapper.get(
      '[role="radiogroup"][aria-labelledby="yarn-import-conflict-strategy-label"]',
    );

    expect(group.attributes("aria-labelledby")).toBe("yarn-import-conflict-strategy-label");
    expect(wrapper.get("#yarn-import-conflict-strategy-label").text()).toContain(
      "When content already exists",
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
        attempt_id: 42,
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
        attempt_id: 42,
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
          allowed_actions: ["preserve_literal"],
          confidence: "high",
          // Action policy comes from the server, independently of the
          // explanatory evidence presented to the user.
          reasons: ["literal_character_name"],
        },
      ],
      possible_speaker_alias_count: 0,
      possible_speaker_aliases: [],
    });

    const wrapper = mountPanel(state);
    const decision = wrapper.get('[data-testid="yarn-import-speaker-decision"]');

    expect(decision.text()).toContain("literal Yarn character name");
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
        attempt_id: 42,
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
        attempt_id: 42,
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
        attempt_id: 42,
        review_confirmation_fingerprint: "resolution-fingerprint",
        import_mode: "additive",
        replace_acknowledged: false,
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
        attempt_id: 42,
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
      attempt_id: 42,
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
    window.localStorage.setItem(storageKey(43), storedAttempt(43));
    dispatchStorageChange(null, storedAttempt(43), storageKey(43));
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
    resetCall?.[2]?.({ ok: true, attempt_id: 42 });

    // The newer attempt reaches the panel; its reference must persist again.
    window.localStorage.removeItem(storageKey(43));
    await wrapper.setProps({ importState: attemptState("queued", "queued", 43) });

    const stored = window.localStorage.getItem(storageKey(43));
    expect(stored).not.toBeNull();
    expect(JSON.parse(stored!).attemptId).toBe(43);

    wrapper.unmount();
  });

  it("a confirmed reset does not cancel a newer cross-tab resume in flight", async () => {
    const wrapper = mountPanel(attemptState("completed", "done", 42));

    // Another tab starts a newer import while the old attempt is displayed.
    window.localStorage.setItem(storageKey(43), storedAttempt(43));
    dispatchStorageChange(null, storedAttempt(43), storageKey(43));

    expect(reviewEventCalls("resume_import")).toHaveLength(1);

    // Reset of the old attempt confirms and the server empties the panel —
    // the attempt-id transition used to invalidate the unrelated pending
    // resume right after the dismissal had deliberately preserved it.
    await wrapper.get('[data-testid="yarn-import-reset"]').trigger("click");
    const resetCall = vi
      .mocked(mockLive.pushEvent)
      .mock.calls.find(([event]) => event === "reset_import");
    resetCall?.[2]?.({ ok: true, attempt_id: 42 });
    await wrapper.setProps({ importState: uploadState() });

    // The newer resume is still alive: a transient failure schedules a retry.
    const resumeCall = vi
      .mocked(mockLive.pushEvent)
      .mock.calls.find(([event]) => event === "resume_import");
    resumeCall?.[2]?.({ ok: false, reason: "unavailable" });

    vi.advanceTimersByTime(1_000);
    expect(reviewEventCalls("resume_import")).toHaveLength(2);

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
