import { onMounted, onUnmounted, watch } from "vue";
import { useLive } from "@shared/composables/useLive";
import type {
  ImportAttemptStatus,
  ImportState,
} from "@modules/projects/settings/export-import/types";

/**
 * Owns everything about recovering a durable import after navigation.
 *
 * PubSub delivery is ephemeral, so the browser keeps a reference to each
 * attempt and re-asks the server for its state on the next mount. References
 * contain an attempt id and nothing else: no filename, source content, or
 * error text. Each attempt has its own key because localStorage has no
 * compare-and-swap operation; separate records prevent concurrent tabs from
 * overwriting an unrelated import while both remain recoverable.
 *
 * The server is the only authority. Every outcome here either adopts what the
 * server returned or drops the reference; nothing is reconstructed locally.
 */

const STORAGE_VERSION = 1;
const STORAGE_TTL_MS = 7 * 24 * 60 * 60 * 1_000;
const STORAGE_CLOCK_SKEW_MS = 5 * 60 * 1_000;
const RECONCILE_INTERVAL_MS = 3_000;
const REQUEST_WATCHDOG_MS = 5_000;
const RESUME_RETRY_BASE_MS = 1_000;
const RESUME_MAX_ATTEMPTS = 4;
const RESUME_RETRY_MAX_MS = 30_000;

const PERSISTED_STATUSES = new Set<ImportAttemptStatus>([
  "ready",
  "queued",
  "running",
  "retrying",
  "completed",
  "failed",
  "expired",
]);
const PROCESSING_STATUSES = new Set<ImportAttemptStatus>(["queued", "running", "retrying"]);

function activeImportStatus(status: ImportState["status"]): boolean {
  return (
    status === "ready" ||
    (status !== null && status !== undefined && PROCESSING_STATUSES.has(status))
  );
}

function terminalImportStatus(status: ImportState["status"]): boolean {
  return (
    status !== null &&
    status !== undefined &&
    PERSISTED_STATUSES.has(status) &&
    !activeImportStatus(status)
  );
}

type ImportStateRequestOutcome =
  | "success"
  | "superseded"
  | "definitive_failure"
  | "transient_failure"
  | "stale";

interface StoredImportAttempt {
  version: typeof STORAGE_VERSION;
  attemptId: number;
  savedAt: number;
}

interface StoredImportDismissal extends StoredImportAttempt {
  kind: "server_confirmed_reset";
}

export interface UseImportResumeOptions {
  /**
   * Opaque namespace supplied by the server. It scopes the reference without
   * persisting raw project or user identifiers in the browser.
   */
  resumeStorageKey: string;
  canImport: () => boolean;
  importState: () => ImportState;
}

export interface UseImportResume {
  /**
   * Drops the given attempt's reference so a dismissed attempt is never
   * resumed again. A null id is deliberately a no-op: without an exact
   * identity, the caller cannot safely clear a newer attempt written by
   * another tab. Callers must invoke this only after the server confirmed the
   * reset: clearing first silently loses the completed-restore path when the
   * server refuses.
   */
  dismissAttempt: (attemptId: number | null) => void;
}

export function validAttemptId(value: unknown): value is number {
  return Number.isSafeInteger(value) && Number(value) > 0;
}

export function useImportResume(options: UseImportResumeOptions): UseImportResume {
  const { resumeStorageKey, canImport, importState } = options;
  const live = useLive();

  const dismissedAttemptIds = new Set<number>();
  const supersededAttemptIds = new Set<number>();
  const activeRequestCancels = new Set<() => void>();

  let reconcileTimer: ReturnType<typeof setTimeout> | null = null;
  let reconcileInFlightGeneration: number | null = null;
  let resumeRetryTimer: ReturnType<typeof setTimeout> | null = null;
  let resumeRequestInFlight = false;
  let resumeAttemptCount = 0;
  let requestGeneration = 0;
  let pendingAttemptId: number | null = null;
  let observedAttemptId = importState().attemptId;
  let observedStatus = importState().status;

  function attemptStoragePrefix() {
    return `${resumeStorageKey}:attempt:`;
  }

  function attemptStorageKey(attemptId: number) {
    return `${attemptStoragePrefix()}${attemptId}`;
  }

  function dismissalStoragePrefix() {
    return `${resumeStorageKey}:dismissed:`;
  }

  function dismissalStorageKey(attemptId: number) {
    return `${dismissalStoragePrefix()}${attemptId}`;
  }

  function browserStorageAreas(): Storage[] {
    if (typeof window === "undefined") return [];

    const areas: Storage[] = [];

    try {
      areas.push(window.localStorage);
    } catch {
      // Access itself can be disabled by browser privacy settings.
    }

    try {
      areas.push(window.sessionStorage);
    } catch {
      // Keep the import usable even when every browser store is unavailable.
    }

    return areas;
  }

  function attemptIdFromStorageKey(key: string | null): number | null {
    if (!key?.startsWith(attemptStoragePrefix())) return null;

    const attemptId = Number(key.slice(attemptStoragePrefix().length));
    return validAttemptId(attemptId) && attemptStorageKey(attemptId) === key ? attemptId : null;
  }

  function dismissalIdFromStorageKey(key: string | null): number | null {
    if (!key?.startsWith(dismissalStoragePrefix())) return null;

    const attemptId = Number(key.slice(dismissalStoragePrefix().length));
    return validAttemptId(attemptId) && dismissalStorageKey(attemptId) === key ? attemptId : null;
  }

  function removeStorageKey(key: string) {
    for (const storage of browserStorageAreas()) {
      try {
        storage.removeItem(key);
      } catch {
        // One store can fail while the other still preserves navigation recovery.
      }
    }
  }

  function writeStorageValue(key: string, value: string) {
    for (const storage of browserStorageAreas()) {
      try {
        storage.setItem(key, value);
      } catch {
        // Best effort per store. The server remains authoritative.
      }
    }
  }

  function parseStoredAttempt(raw: string): StoredImportAttempt | null {
    const parsed: unknown = JSON.parse(raw);
    if (!parsed || typeof parsed !== "object") return null;

    const { version, attemptId, savedAt } = parsed as Partial<StoredImportAttempt>;
    const now = Date.now();

    if (
      version !== STORAGE_VERSION ||
      !validAttemptId(attemptId) ||
      typeof savedAt !== "number" ||
      !Number.isSafeInteger(savedAt) ||
      savedAt <= 0 ||
      savedAt > now + STORAGE_CLOCK_SKEW_MS ||
      now - savedAt > STORAGE_TTL_MS
    ) {
      return null;
    }

    return { version, attemptId, savedAt };
  }

  function parseStoredDismissal(raw: string): StoredImportDismissal | null {
    const parsed: unknown = JSON.parse(raw);
    if (!parsed || typeof parsed !== "object") return null;

    const { kind } = parsed as Partial<StoredImportDismissal>;
    if (kind !== "server_confirmed_reset") return null;

    const stored = parseStoredAttempt(raw);
    return stored ? { ...stored, kind } : null;
  }

  function storageKeyMatchesAttempt(key: string, attemptId: number) {
    return attemptIdFromStorageKey(key) === attemptId;
  }

  function storageKeyMatchesDismissal(key: string, attemptId: number) {
    return dismissalIdFromStorageKey(key) === attemptId;
  }

  function readStoredDismissal(attemptId: number): StoredImportDismissal | null {
    const key = dismissalStorageKey(attemptId);
    const candidates: StoredImportDismissal[] = [];

    for (const storage of browserStorageAreas()) {
      try {
        const raw = storage.getItem(key);
        if (!raw) continue;

        const stored = parseStoredDismissal(raw);
        if (stored && storageKeyMatchesDismissal(key, stored.attemptId)) candidates.push(stored);
      } catch {
        // Try the next browser store.
      }
    }

    return candidates.sort((left, right) => right.savedAt - left.savedAt)[0] ?? null;
  }

  function attemptDismissed(attemptId: number) {
    if (dismissedAttemptIds.has(attemptId)) return true;
    if (!readStoredDismissal(attemptId)) return false;

    dismissedAttemptIds.add(attemptId);
    return true;
  }

  function readStoredAttemptAt(key: string): StoredImportAttempt | null {
    const candidates: StoredImportAttempt[] = [];

    for (const storage of browserStorageAreas()) {
      try {
        const raw = storage.getItem(key);
        if (!raw) continue;

        const stored = parseStoredAttempt(raw);
        if (stored && storageKeyMatchesAttempt(key, stored.attemptId)) candidates.push(stored);
      } catch {
        // Try the next browser store.
      }
    }

    return candidates.sort((left, right) => right.savedAt - left.savedAt)[0] ?? null;
  }

  function storedAttemptKeys() {
    const keys = new Set<string>();

    for (const storage of browserStorageAreas()) {
      try {
        for (let index = 0; index < storage.length; index += 1) {
          const key = storage.key(index);
          if (key && attemptIdFromStorageKey(key) !== null) keys.add(key);
        }
      } catch {
        // Try the next browser store.
      }
    }

    return [...keys];
  }

  function readLatestStoredAttempt(): StoredImportAttempt | null {
    return (
      storedAttemptKeys()
        .map((key) => readStoredAttemptAt(key))
        .filter(
          (stored): stored is StoredImportAttempt =>
            stored !== null &&
            !attemptDismissed(stored.attemptId) &&
            !supersededAttemptIds.has(stored.attemptId),
        )
        .sort(
          (left, right) => right.attemptId - left.attemptId || right.savedAt - left.savedAt,
        )[0] ?? null
    );
  }

  function storeAttempt(attemptId: number) {
    if (attemptDismissed(attemptId)) return;

    const stored: StoredImportAttempt = {
      version: STORAGE_VERSION,
      attemptId,
      savedAt: Date.now(),
    };
    writeStorageValue(attemptStorageKey(attemptId), JSON.stringify(stored));
  }

  function clearStoredAttemptIfMatching(attemptId: number) {
    removeStorageKey(attemptStorageKey(attemptId));
  }

  function storeConfirmedDismissal(attemptId: number) {
    const stored: StoredImportDismissal = {
      version: STORAGE_VERSION,
      kind: "server_confirmed_reset",
      attemptId,
      savedAt: Date.now(),
    };
    writeStorageValue(dismissalStorageKey(attemptId), JSON.stringify(stored));
  }

  function reconcileReply(
    event: "resume_import" | "reconcile_import",
    attemptId: number,
    generation: number,
    reply: Record<string, unknown>,
  ): ImportStateRequestOutcome {
    if (generation !== requestGeneration) return "stale";

    if (reply.ok === true) return "success";

    const currentAttemptId = importState().attemptId;
    if (
      event === "reconcile_import" &&
      validAttemptId(currentAttemptId) &&
      currentAttemptId !== attemptId
    ) {
      return "stale";
    }

    const definitiveFailure = ["invalid", "not_found", "unauthorized"].includes(
      String(reply.reason),
    );

    if (reply.reason === "superseded") {
      // The requested terminal attempt is valid, but the server kept another
      // attempt that is still materializing. Suppress this reference only
      // until that blocker changes: deleting it globally, or treating it as a
      // confirmed reset, would lose its terminal result in this same tab.
      supersededAttemptIds.add(attemptId);
      return "superseded";
    }

    if (definitiveFailure) {
      dismissedAttemptIds.add(attemptId);
      clearStoredAttemptIfMatching(attemptId);
      stopReconcileTimer();
      return "definitive_failure";
    }

    return "transient_failure";
  }

  function requestImportState(
    event: "resume_import" | "reconcile_import",
    attemptId: number,
    settled?: (generation: number, outcome: ImportStateRequestOutcome) => void,
  ) {
    const generation = requestGeneration;
    let finished = false;

    const cancel = () => {
      if (finished) return;

      finished = true;
      clearTimeout(watchdog);
      activeRequestCancels.delete(cancel);
    };

    const finish = (outcome: ImportStateRequestOutcome) => {
      if (finished) return;

      cancel();
      settled?.(generation, outcome);
    };

    const watchdog = setTimeout(() => finish("transient_failure"), REQUEST_WATCHDOG_MS);
    activeRequestCancels.add(cancel);

    live.pushEvent(
      event,
      { attempt_id: attemptId },
      (reply) => finish(reconcileReply(event, attemptId, generation, reply)),
      () => {
        // A dropped socket is transient. Keep the reference for the next mount.
        finish("transient_failure");
      },
    );
  }

  function requestConfirmedDismissalReset(
    attemptId: number,
    settled: (generation: number, outcome: ImportStateRequestOutcome) => void,
  ) {
    const generation = requestGeneration;
    let finished = false;

    const cancel = () => {
      if (finished) return;

      finished = true;
      clearTimeout(watchdog);
      activeRequestCancels.delete(cancel);
    };

    const finish = (outcome: ImportStateRequestOutcome) => {
      if (finished) return;

      cancel();
      settled(generation, outcome);
    };

    const watchdog = setTimeout(() => finish("transient_failure"), REQUEST_WATCHDOG_MS);
    activeRequestCancels.add(cancel);

    live.pushEvent(
      "reset_import",
      { attempt_id: attemptId },
      (reply) => {
        if (generation !== requestGeneration) {
          finish("stale");
        } else if (reply.ok === true && reply.attempt_id === attemptId) {
          finish("success");
        } else if (importState().attemptId !== attemptId) {
          finish("stale");
        } else {
          finish("transient_failure");
        }
      },
      () => finish("transient_failure"),
    );
  }

  function cancelOutstandingRequests() {
    for (const cancel of activeRequestCancels) cancel();
  }

  function stopResumeRetryTimer() {
    if (resumeRetryTimer !== null) {
      clearTimeout(resumeRetryTimer);
      resumeRetryTimer = null;
    }
  }

  function stopReconcileTimer() {
    if (reconcileTimer !== null) {
      clearTimeout(reconcileTimer);
      reconcileTimer = null;
    }
  }

  function invalidateRequests() {
    requestGeneration += 1;
    cancelOutstandingRequests();
    reconcileInFlightGeneration = null;
    resumeRequestInFlight = false;
    stopResumeRetryTimer();
    stopReconcileTimer();
  }

  function scheduleResumeAttempt(attemptId: number, generation: number, delayMs: number) {
    stopResumeRetryTimer();

    resumeRetryTimer = setTimeout(() => {
      resumeRetryTimer = null;

      if (
        generation === requestGeneration &&
        pendingAttemptId === attemptId &&
        !attemptDismissed(attemptId)
      ) {
        requestResumeAttempt(attemptId, generation);
      }
    }, delayMs);
  }

  function storedAttemptCanReplaceCurrent(
    storedAttemptId: number,
    removedAttemptId: number,
    current: ImportState,
  ) {
    if (storedAttemptId === removedAttemptId) return false;
    if (!validAttemptId(current.attemptId)) return true;
    if (current.attemptId === removedAttemptId || attemptDismissed(current.attemptId)) return true;
    if (!activeImportStatus(current.status)) return true;

    return storedAttemptId > current.attemptId;
  }

  function currentAttemptCanReconcile(removedAttemptId: number, current: ImportState) {
    return (
      current.attemptId !== removedAttemptId &&
      (!validAttemptId(current.attemptId) || !attemptDismissed(current.attemptId))
    );
  }

  function continueAfterStoredAttemptGone(removedAttemptId: number) {
    const latest = readLatestStoredAttempt();
    const current = importState();

    if (latest && storedAttemptCanReplaceCurrent(latest.attemptId, removedAttemptId, current)) {
      startResume(latest.attemptId);
      return;
    }

    // A displayed attempt owns a separate durable record, so resuming its
    // polling never needs to rewrite the record that another tab just added.
    if (currentAttemptCanReconcile(removedAttemptId, current)) syncReconcileTimer();
  }

  function requestResumeAttempt(attemptId: number, generation: number) {
    if (
      generation !== requestGeneration ||
      pendingAttemptId !== attemptId ||
      resumeRequestInFlight ||
      attemptDismissed(attemptId)
    ) {
      return;
    }

    if (importState().attemptId === attemptId) {
      pendingAttemptId = null;
      resumeAttemptCount = 0;
      return;
    }

    resumeAttemptCount += 1;
    resumeRequestInFlight = true;

    requestImportState("resume_import", attemptId, (settledGeneration, outcome) => {
      if (settledGeneration !== requestGeneration || pendingAttemptId !== attemptId) return;

      resumeRequestInFlight = false;

      if (outcome === "definitive_failure") {
        pendingAttemptId = null;
        resumeAttemptCount = 0;
        continueAfterStoredAttemptGone(attemptId);
        return;
      }

      if (outcome === "superseded") {
        pendingAttemptId = null;
        resumeAttemptCount = 0;
        continueAfterStoredAttemptGone(attemptId);
        return;
      }

      if (outcome === "stale") return;

      if (resumeAttemptCount >= RESUME_MAX_ATTEMPTS) {
        // Keep the newer attempt's durable browser reference, but stop letting
        // an unreachable tab B suspend reconciliation of the processing
        // attempt A that this tab still displays. A capped slow retry remains
        // armed so network recovery also works when no attempt is visible.
        syncReconcileTimer();
        scheduleResumeAttempt(attemptId, settledGeneration, RESUME_RETRY_MAX_MS);
        return;
      }

      const retryDelay =
        outcome === "success"
          ? RESUME_RETRY_BASE_MS
          : RESUME_RETRY_BASE_MS * 2 ** (resumeAttemptCount - 1);

      scheduleResumeAttempt(attemptId, settledGeneration, retryDelay);
    });
  }

  function startResume(attemptId: number) {
    const current = importState();

    if (!resumeMayStart(attemptId, current)) return;

    invalidateRequests();
    pendingAttemptId = attemptId;
    resumeAttemptCount = 0;
    requestResumeAttempt(attemptId, requestGeneration);
  }

  function resumeMayStart(attemptId: number, current: ImportState) {
    if (!canImport() || attemptDismissed(attemptId) || supersededAttemptIds.has(attemptId)) {
      return false;
    }

    if (current.attemptId === attemptId || currentBlocksOlderResume(attemptId, current)) {
      return false;
    }

    return !(
      pendingAttemptId === attemptId &&
      (resumeRequestInFlight || resumeRetryTimer !== null)
    );
  }

  function currentBlocksOlderResume(attemptId: number, current: ImportState) {
    return (
      validAttemptId(current.attemptId) &&
      attemptId < current.attemptId &&
      !attemptDismissed(current.attemptId) &&
      activeImportStatus(current.status)
    );
  }

  // Polling backstop for the window between a broadcast being missed and the
  // attempt reaching a terminal state.
  function pendingResumeExhausted() {
    return (
      validAttemptId(pendingAttemptId) &&
      resumeAttemptCount >= RESUME_MAX_ATTEMPTS &&
      !resumeRequestInFlight
    );
  }

  function shouldReconcile(state: ImportState) {
    if (!state.status || !validAttemptId(state.attemptId)) return false;

    return (
      PROCESSING_STATUSES.has(state.status) ||
      (state.status === "ready" &&
        (attemptDismissed(state.attemptId) ||
          (state.step === "error" && state.errorCode === "import_state_changed")))
    );
  }

  function syncReconcileTimer() {
    stopReconcileTimer();

    const state = importState();
    const { attemptId, status } = state;
    const clearingConfirmedDismissal = validAttemptId(attemptId) && attemptDismissed(attemptId);
    const pollingCurrentAttempt =
      status !== null &&
      shouldReconcile(state) &&
      (pendingAttemptId === null || pendingResumeExhausted());

    if (
      canImport() &&
      validAttemptId(attemptId) &&
      (clearingConfirmedDismissal || pollingCurrentAttempt) &&
      reconcileInFlightGeneration === null
    ) {
      reconcileTimer = setTimeout(() => {
        reconcileTimer = null;

        const current = importState();

        if (current.attemptId === attemptId && attemptDismissed(attemptId)) {
          const generation = requestGeneration;
          reconcileInFlightGeneration = generation;

          requestConfirmedDismissalReset(attemptId, (settledGeneration, outcome) => {
            if (reconcileInFlightGeneration !== settledGeneration) return;

            reconcileInFlightGeneration = null;

            if (outcome === "success") continueAfterStoredAttemptGone(attemptId);
            if (outcome !== "stale") syncReconcileTimer();
          });
        } else if (current.attemptId === attemptId && current.status && shouldReconcile(current)) {
          const generation = requestGeneration;
          reconcileInFlightGeneration = generation;

          requestImportState("reconcile_import", attemptId, (settledGeneration, outcome) => {
            if (reconcileInFlightGeneration !== settledGeneration) return;

            reconcileInFlightGeneration = null;
            if (outcome === "definitive_failure") {
              continueAfterStoredAttemptGone(attemptId);
            } else if (outcome !== "stale") {
              syncReconcileTimer();
            }
          });
        }
      }, RECONCILE_INTERVAL_MS);
    }
  }

  function dismissAttempt(attemptId: number | null) {
    if (validAttemptId(attemptId)) {
      // Only a server-confirmed reset writes this explicit tombstone. Ordinary
      // attempt-key removals are cache eviction and carry no cancellation
      // authority across tabs.
      storeConfirmedDismissal(attemptId);
      adoptConfirmedDismissal(attemptId);
      return;
    }

    // The reset did not identify an attempt, so it has no authority to clear
    // the durable reference. Another tab may have created it while this tab
    // was showing a local (pre-attempt) validation error.
  }

  function adoptConfirmedDismissal(attemptId: number) {
    dismissedAttemptIds.add(attemptId);
    supersededAttemptIds.delete(attemptId);
    clearStoredAttemptIfMatching(attemptId);

    const dismissingCurrent = importState().attemptId === attemptId;
    const dismissingPending = pendingAttemptId === attemptId;

    // A late reply must not reach past its own attempt: when the panel and
    // the resume machinery both moved on, dropping the old reference is all
    // there is to do.
    // Only the machinery that belongs to the dismissed attempt is touched.
    // A newer cross-tab resume may be pending while the old attempt is
    // still displayed; invalidating it would cancel what the user just
    // started in the other tab.
    if (dismissingPending) {
      invalidateRequests();
      pendingAttemptId = null;
    }

    // Callback delivery and the LiveView prop diff are not ordered. Scanning
    // here covers the case where props were already cleared; the watcher also
    // scans the inverse order. A current tombstone additionally schedules an
    // exact reset so another tab's terminal result disappears from this socket.
    continueAfterStoredAttemptGone(attemptId);
    if (dismissingCurrent) syncReconcileTimer();
  }

  function dismissalFromStorageEvent(
    key: string,
    raw: string | null,
  ): StoredImportDismissal | null {
    if (!raw) return null;

    try {
      const stored = parseStoredDismissal(raw);
      return stored && storageKeyMatchesDismissal(key, stored.attemptId) ? stored : null;
    } catch {
      // Malformed storage never authorizes dismissing an import.
      return null;
    }
  }

  function handleStorageChange(event: StorageEvent) {
    if (event.storageArea && !browserStorageAreas().includes(event.storageArea)) return;
    if (!event.key) return;

    const dismissalId = dismissalIdFromStorageKey(event.key);
    if (dismissalId !== null) {
      const dismissal = dismissalFromStorageEvent(event.key, event.newValue);
      if (!dismissal) return;

      adoptConfirmedDismissal(dismissal.attemptId);
      return;
    }

    if (attemptIdFromStorageKey(event.key) === null) return;

    // Removing an attempt record is cache eviction, including pruning done by
    // another tab after it adopts a newer attempt. Only the explicit dismissal
    // tombstone above can stop polling or suppress a live import.
    if (event.newValue === null) return;

    // Storage events can be queued behind another tab's later write. Always
    // scan the namespace and select the newest attempt, rather than trusting
    // the event payload to still be the newest durable reference.
    const stored = readLatestStoredAttempt();
    if (stored) startResume(stored.attemptId);
  }

  function pendingResumeSurvivesStateChange(
    attemptId: ImportState["attemptId"],
    previousAttemptId: ImportState["attemptId"],
  ) {
    return (
      validAttemptId(pendingAttemptId) &&
      pendingAttemptId !== previousAttemptId &&
      (!validAttemptId(attemptId) || pendingAttemptId > attemptId)
    );
  }

  function handleAttemptIdentityChange(
    attemptId: ImportState["attemptId"],
    previousAttemptId: ImportState["attemptId"],
  ) {
    if (attemptId === previousAttemptId) return;

    observedAttemptId = attemptId;

    // A pending resume survives only when it is newer than the state now
    // rendered, or while a reset briefly renders no attempt.
    if (pendingResumeSurvivesStateChange(attemptId, previousAttemptId)) return;

    invalidateRequests();
    pendingAttemptId = null;
    resumeAttemptCount = 0;
  }

  function persistObservedAttempt(
    attemptId: ImportState["attemptId"],
    status: ImportState["status"],
  ) {
    if (validAttemptId(attemptId) && status && PERSISTED_STATUSES.has(status)) {
      storeAttempt(attemptId);
    }
  }

  function storedAttemptToScan(
    attemptId: ImportState["attemptId"],
    status: ImportState["status"],
    previousAttemptId: ImportState["attemptId"],
    previousStatus: ImportState["status"],
  ): number | null {
    if (validAttemptId(previousAttemptId) && !validAttemptId(attemptId)) {
      return previousAttemptId;
    }

    if (
      validAttemptId(attemptId) &&
      terminalImportStatus(status) &&
      activeImportStatus(previousStatus)
    ) {
      return attemptId;
    }

    return null;
  }

  function handleObservedImportState([attemptId, status]: readonly [
    ImportState["attemptId"],
    ImportState["status"],
  ]) {
    const previousAttemptId = observedAttemptId;
    const previousStatus = observedStatus;

    handleAttemptIdentityChange(attemptId, previousAttemptId);
    observedStatus = status;

    const blockerChanged =
      attemptId !== previousAttemptId ||
      (activeImportStatus(previousStatus) && !activeImportStatus(status));

    if (blockerChanged) supersededAttemptIds.clear();

    persistObservedAttempt(attemptId, status);

    const scanAfterAttemptId = storedAttemptToScan(
      attemptId,
      status,
      previousAttemptId,
      previousStatus,
    );
    if (scanAfterAttemptId !== null) continueAfterStoredAttemptGone(scanAfterAttemptId);

    syncReconcileTimer();
  }

  watch(() => [importState().attemptId, importState().status] as const, handleObservedImportState, {
    immediate: true,
  });

  onMounted(() => {
    window.addEventListener("storage", handleStorageChange);

    if (!canImport()) return;

    const stored = readLatestStoredAttempt();
    if (stored) startResume(stored.attemptId);
  });

  onUnmounted(() => {
    invalidateRequests();
    pendingAttemptId = null;
    stopReconcileTimer();
    window.removeEventListener("storage", handleStorageChange);
  });

  return { dismissAttempt };
}
