import { computed, onUnmounted, ref, shallowRef, watch } from "vue";
import { useLive } from "@shared/composables/useLive";
import type { Session, SessionTimer } from "../types";

interface TimerWriteReceipt {
  id: number;
  revision: number;
}
interface PendingWrite {
  epoch: string;
  sessionId: number;
  revision: number;
  timerVersion: number | null;
  acknowledgedRevision: number | null;
}
export type TimerControl = "pause_timer" | "resume_timer" | "cancel_timer" | "extend_timer";
export interface TimerStart {
  seconds: number;
  close_contributions_on_expiry: boolean;
}
export const DEFAULT_TIMER_SECONDS = 300;
export const MAX_TIMER_SECONDS = 86_400;

/** m:ss, or h:mm:ss from an hour up. */
export function formatSeconds(value: number): string {
  const total = Math.max(0, Math.floor(value));
  const minutes = Math.floor(total / 60);
  const tail = String(total % 60).padStart(2, "0");
  return total >= 3600
    ? `${Math.floor(total / 3600)}:${String(minutes % 60).padStart(2, "0")}:${tail}`
    : `${minutes}:${tail}`;
}

/** "5" is five minutes, "1:30" a minute and a half, "1:00:00" an hour; anything else is nothing. */
export function parseDuration(text: string): number | null {
  const parts = text.trim().split(":");
  if (parts.length > 3 || parts.some((part) => !/^\d{1,5}$/.test(part))) return null;
  const numbers = parts.map(Number);
  if (parts.length > 1 && numbers.slice(1).some((part) => part > 59)) return null;
  let seconds = numbers[0] * 60;
  if (parts.length === 2) seconds = numbers[0] * 60 + numbers[1];
  if (parts.length === 3) seconds = numbers[0] * 3600 + numbers[1] * 60 + numbers[2];
  return seconds >= 1 && seconds <= MAX_TIMER_SECONDS ? seconds : null;
}
export function activeTimer(timer: SessionTimer | null): boolean {
  return timer?.status === "running" || timer?.status === "paused";
}

/**
 * Timer writes for one session, shared by the header chip and the round bar:
 * one write in flight at a time, released once both the session revision and
 * the timer version the server reported have rendered.
 */
export function useTimerWrites(
  session: () => Session,
  epoch: () => string,
  timer: () => SessionTimer | null,
  mayManage: () => boolean,
) {
  const live = useLive();
  const pendingWrite = shallowRef<PendingWrite | null>(null);
  const pending = computed(() => pendingWrite.value !== null);
  const failure = ref<string | null>(null);
  function send(event: string, payload: Record<string, unknown>) {
    if (!mayManage() || pending.value) return;
    failure.value = null;
    const current = session();
    const attempt: PendingWrite = {
      epoch: epoch(),
      sessionId: current.id,
      revision: current.revision,
      timerVersion: event === "set_contributions_open" ? null : (timer()?.version ?? 0),
      acknowledgedRevision: null,
    };
    pendingWrite.value = attempt;
    live.pushEvent(
      event,
      {
        ...payload,
        epoch: attempt.epoch,
        session_id: attempt.sessionId,
        revision: attempt.revision,
      },
      (reply) => {
        if (!currentAttempt(attempt)) return;
        const revision = receiptRevision(reply?.value as TimerWriteReceipt | undefined, attempt);
        if (reply?.status !== "ok" || revision === null) {
          pendingWrite.value = null;
          const code = String(reply?.code ?? "unavailable");
          failure.value = code === "stale_revision" ? "stale_timer" : code;
          return;
        }
        attempt.acknowledgedRevision = revision;
        releaseAcknowledgedWrite();
      },
      () => {
        if (!currentAttempt(attempt)) return;
        pendingWrite.value = null;
        failure.value = "offline";
      },
    );
  }
  function receiptRevision(receipt: TimerWriteReceipt | undefined, attempt: PendingWrite) {
    if (
      !receipt ||
      receipt.id !== attempt.sessionId ||
      !Number.isInteger(receipt.revision) ||
      receipt.revision < attempt.revision
    )
      return null;
    return receipt.revision;
  }
  function currentAttempt(attempt: PendingWrite) {
    return (
      pendingWrite.value === attempt &&
      attempt.epoch === epoch() &&
      attempt.sessionId === session().id
    );
  }
  function releaseAcknowledgedWrite() {
    const attempt = pendingWrite.value;
    if (!attempt || !currentAttempt(attempt) || attempt.acknowledgedRevision === null) return;
    if (session().revision < attempt.acknowledgedRevision) return;
    // An effective timer write advances both counters. Wait for both props even
    // when LiveVue patches them in place or the reply arrives before the refresh.
    const changed = attempt.acknowledgedRevision > attempt.revision;
    if (
      attempt.timerVersion !== null &&
      (timer()?.version ?? 0) < attempt.timerVersion + Number(changed)
    )
      return;
    pendingWrite.value = null;
  }
  function start(options: TimerStart) {
    if (activeTimer(timer())) return;
    send("start_timer", { ...options });
  }
  function control(event: TimerControl, secondsLeft: number) {
    const current = timer();
    if (!current || !activeTimer(current) || (event !== "cancel_timer" && secondsLeft === 0))
      return;
    send(event, {
      timer_version: current.version,
      ...(event === "extend_timer" ? { seconds: 60 } : {}),
    });
  }
  function reset() {
    pendingWrite.value = null;
    failure.value = null;
  }
  function clearFailure() {
    failure.value = null;
  }
  /** Refresh the board once the countdown ends; the server owns the outcome. */
  function sync() {
    live.pushEvent("sync_board", { epoch: epoch(), session_id: session().id });
  }
  watch([() => session().revision, () => timer()?.version], releaseAcknowledgedWrite);
  watch([epoch, () => session().id], reset, { flush: "sync" });
  watch(
    mayManage,
    (allowed) => {
      if (!allowed) reset();
    },
    { flush: "sync" },
  );
  onUnmounted(() => {
    pendingWrite.value = null;
  });
  return { pending, failure, send, start, control, clearFailure, sync };
}
