import { onMounted, onUnmounted, watch } from "vue";
import { useLive } from "@shared/composables/useLive";
import type {
  ImportAttemptStatus,
  ImportState,
} from "@modules/projects/settings/export-import/types";

/**
 * Owns everything about recovering a durable import after navigation.
 *
 * PubSub delivery is ephemeral, so the browser keeps a reference to the attempt
 * and re-asks the server for its state on the next mount. The reference is an
 * attempt id and nothing else: no filename, no source content, no error text.
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

type ImportStateRequestOutcome = "success" | "definitive_failure" | "transient_failure" | "stale";

interface StoredImportAttempt {
  version: typeof STORAGE_VERSION;
  attemptId: number;
  savedAt: number;
}

export interface UseImportResumeOptions {
  projectId: number;
  /**
   * Scopes the stored reference to whoever is signed in. The key used to be
   * per-project only, so on a shared browser the next member to open the page
   * inherited the previous one's in-flight attempt id.
   */
  currentUserId: number;
  canImport: () => boolean;
  importState: () => ImportState;
}

export interface UseImportResume {
  /**
   * Drops the given attempt's reference so a dismissed attempt is never
   * resumed again. Callers must invoke this only after the server confirmed
   * the reset: clearing first silently loses the completed-restore path when
   * the server refuses.
   */
  dismissAttempt: (attemptId: number | null) => void;
}

export function validAttemptId(value: unknown): value is number {
  return Number.isSafeInteger(value) && Number(value) > 0;
}

export function useImportResume(options: UseImportResumeOptions): UseImportResume {
  const { projectId, currentUserId, canImport, importState } = options;
  const live = useLive();

  const dismissedAttemptIds = new Set<number>();
  const activeRequestCancels = new Set<() => void>();

  let reconcileTimer: ReturnType<typeof setTimeout> | null = null;
  let reconcileInFlightGeneration: number | null = null;
  let resumeRetryTimer: ReturnType<typeof setTimeout> | null = null;
  let resumeRequestInFlight = false;
  let resumeAttemptCount = 0;
  let requestGeneration = 0;
  let pendingAttemptId: number | null = null;
  let observedAttemptId = importState().attemptId;

  function storageKey() {
    return `storyarn:project-import:${projectId}:${currentUserId}`;
  }

  function clearStoredAttempt() {
    if (typeof window === "undefined") return;

    try {
      window.localStorage.removeItem(storageKey());
    } catch {
      // Storage can be disabled. Import execution must remain usable without it.
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

  function readStoredAttempt(): StoredImportAttempt | null {
    if (typeof window === "undefined") return null;

    try {
      const raw = window.localStorage.getItem(storageKey());
      if (!raw) return null;

      const stored = parseStoredAttempt(raw);
      if (!stored) clearStoredAttempt();
      return stored;
    } catch {
      clearStoredAttempt();
      return null;
    }
  }

  function storeAttempt(attemptId: number) {
    if (typeof window === "undefined" || dismissedAttemptIds.has(attemptId)) return;

    try {
      const stored: StoredImportAttempt = {
        version: STORAGE_VERSION,
        attemptId,
        savedAt: Date.now(),
      };
      window.localStorage.setItem(storageKey(), JSON.stringify(stored));
    } catch {
      // Keep the in-page workflow functional when storage is unavailable.
    }
  }

  function clearStoredAttemptIfMatching(attemptId: number) {
    const stored = readStoredAttempt();
    if (stored?.attemptId === attemptId) clearStoredAttempt();
  }

  function reconcileReply(
    attemptId: number,
    generation: number,
    reply: Record<string, unknown>,
  ): ImportStateRequestOutcome {
    if (generation !== requestGeneration) return "stale";

    if (reply.ok === true) return "success";

    const currentAttemptId = importState().attemptId;
    if (validAttemptId(currentAttemptId) && currentAttemptId !== attemptId) return "stale";

    const definitiveFailure = ["invalid", "not_found", "unauthorized"].includes(
      String(reply.reason),
    );

    if (definitiveFailure) {
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
      (reply) => finish(reconcileReply(attemptId, generation, reply)),
      () => {
        // A dropped socket is transient. Keep the reference for the next mount.
        finish("transient_failure");
      },
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
        !dismissedAttemptIds.has(attemptId)
      ) {
        requestResumeAttempt(attemptId, generation);
      }
    }, delayMs);
  }

  function requestResumeAttempt(attemptId: number, generation: number) {
    if (
      generation !== requestGeneration ||
      pendingAttemptId !== attemptId ||
      resumeRequestInFlight ||
      dismissedAttemptIds.has(attemptId)
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
        return;
      }

      if (outcome === "stale") return;

      if (resumeAttemptCount >= RESUME_MAX_ATTEMPTS) return;

      const retryDelay =
        outcome === "success"
          ? RESUME_RETRY_BASE_MS
          : RESUME_RETRY_BASE_MS * 2 ** (resumeAttemptCount - 1);

      scheduleResumeAttempt(attemptId, settledGeneration, retryDelay);
    });
  }

  function startResume(attemptId: number) {
    if (
      !canImport() ||
      dismissedAttemptIds.has(attemptId) ||
      importState().attemptId === attemptId ||
      (pendingAttemptId === attemptId && (resumeRequestInFlight || resumeRetryTimer !== null))
    ) {
      return;
    }

    invalidateRequests();
    pendingAttemptId = attemptId;
    resumeAttemptCount = 0;
    requestResumeAttempt(attemptId, requestGeneration);
  }

  // Polling backstop for the window between a broadcast being missed and the
  // attempt reaching a terminal state.
  function syncReconcileTimer() {
    stopReconcileTimer();

    const { attemptId, status } = importState();

    if (
      canImport() &&
      validAttemptId(attemptId) &&
      status &&
      PROCESSING_STATUSES.has(status) &&
      pendingAttemptId === null &&
      reconcileInFlightGeneration === null
    ) {
      reconcileTimer = setTimeout(() => {
        reconcileTimer = null;

        const current = importState();

        if (
          current.attemptId === attemptId &&
          current.status &&
          PROCESSING_STATUSES.has(current.status)
        ) {
          const generation = requestGeneration;
          reconcileInFlightGeneration = generation;

          requestImportState("reconcile_import", attemptId, (settledGeneration, outcome) => {
            if (reconcileInFlightGeneration !== settledGeneration) return;

            reconcileInFlightGeneration = null;
            if (outcome !== "definitive_failure" && outcome !== "stale") syncReconcileTimer();
          });
        }
      }, RECONCILE_INTERVAL_MS);
    }
  }

  function dismissAttempt(attemptId: number | null) {
    if (validAttemptId(attemptId)) {
      dismissedAttemptIds.add(attemptId);
      clearStoredAttemptIfMatching(attemptId);

      const dismissingCurrent = importState().attemptId === attemptId;
      const dismissingPending = pendingAttemptId === attemptId;

      // A late reply must not reach past its own attempt: when the panel and
      // the resume machinery both moved on, dropping the old reference is all
      // there is to do.
      if (!dismissingCurrent && !dismissingPending) return;

      // Only the machinery that belongs to the dismissed attempt is touched.
      // A newer cross-tab resume may be pending while the old attempt is
      // still displayed; invalidating it would cancel what the user just
      // started in the other tab.
      if (dismissingPending) {
        invalidateRequests();
        pendingAttemptId = null;
      }

      if (dismissingCurrent) stopReconcileTimer();
      return;
    }

    // No specific attempt was on screen; drop whatever reference remains.
    clearStoredAttempt();

    if (validAttemptId(pendingAttemptId)) {
      dismissedAttemptIds.add(pendingAttemptId);
    }

    invalidateRequests();
    pendingAttemptId = null;
    stopReconcileTimer();
  }

  // Another tab clearing the reference means the user dismissed the import
  // there. Adopt that decision rather than resuming what they just dropped.
  function handleStorageChange(event: StorageEvent) {
    if (event.key !== storageKey()) return;

    if (event.newValue === null) {
      try {
        if (window.localStorage.getItem(storageKey()) !== null) return;
      } catch {
        // Treat inaccessible storage as removed and keep the in-page flow usable.
      }

      const { attemptId } = importState();
      if (validAttemptId(attemptId)) dismissedAttemptIds.add(attemptId);
      if (validAttemptId(pendingAttemptId)) dismissedAttemptIds.add(pendingAttemptId);

      invalidateRequests();
      pendingAttemptId = null;
      stopReconcileTimer();
      return;
    }

    const stored = readStoredAttempt();
    if (stored) startResume(stored.attemptId);
  }

  watch(
    () => [importState().attemptId, importState().status] as const,
    ([attemptId, status]) => {
      if (attemptId !== observedAttemptId) {
        const previousAttemptId = observedAttemptId;
        observedAttemptId = attemptId;

        // The transition invalidates the machinery bound to the attempts it
        // involves. A pending resume for an UNRELATED attempt — a newer
        // cross-tab import arriving while this panel resets to empty — must
        // survive it, or a confirmed reset of the old attempt cancels what
        // the user just started in the other tab. Stragglers from the
        // previous attempt self-neutralize through the state guards in
        // reconcileReply and syncReconcileTimer.
        const pendingUnrelated =
          validAttemptId(pendingAttemptId) &&
          pendingAttemptId !== previousAttemptId &&
          pendingAttemptId !== attemptId;

        if (!pendingUnrelated) {
          invalidateRequests();
          pendingAttemptId = null;
          resumeAttemptCount = 0;
        }
      }

      if (
        validAttemptId(attemptId) &&
        status &&
        PERSISTED_STATUSES.has(status) &&
        pendingAttemptId === null
      ) {
        storeAttempt(attemptId);
      }

      syncReconcileTimer();
    },
    { immediate: true },
  );

  onMounted(() => {
    window.addEventListener("storage", handleStorageChange);

    if (!canImport() || validAttemptId(importState().attemptId)) return;

    const stored = readStoredAttempt();
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
