import { getCurrentScope, onScopeDispose, readonly, ref, type Ref } from "vue";
import { useLive, type LiveInterface } from "./useLive";

// Phoenix rejects a push after its own timeout; this is the last resort for a
// reply that never comes, so a button never stays busy.
const SETTLE_TIMEOUT_MS = 30_000;

export interface LiveActionHandlers {
  onReply?: (reply: Record<string, unknown>) => void;
  onError?: (error: unknown) => void;
}

export interface LiveAction {
  /** True from the push until its reply, its error or its timeout. */
  pending: Readonly<Ref<boolean>>;
  push: (event: string, payload?: Record<string, unknown>, handlers?: LiveActionHandlers) => void;
}

/**
 * Pushes a LiveView event whose pending state always settles: on the reply, on
 * a transport error (a dropped socket, a Phoenix timeout) or after
 * SETTLE_TIMEOUT_MS. Each call settles once; a late reply after an error or a
 * timeout is ignored.
 *
 * Pass `live` when the caller already holds one; otherwise it is resolved here,
 * which requires a component setup.
 */
export function useLiveAction(
  live: LiveInterface = useLive(),
  timeoutMs = SETTLE_TIMEOUT_MS,
): LiveAction {
  const pending = ref(false);
  const timers = new Set<ReturnType<typeof setTimeout>>();

  if (getCurrentScope()) {
    onScopeDispose(() => {
      for (const timer of timers) clearTimeout(timer);
      timers.clear();
    });
  }

  function push(
    event: string,
    payload: Record<string, unknown> = {},
    { onReply, onError }: LiveActionHandlers = {},
  ): void {
    let settled = false;
    const settle = (): boolean => {
      if (settled) return false;
      settled = true;
      clearTimeout(timer);
      timers.delete(timer);
      pending.value = false;
      return true;
    };

    pending.value = true;
    const timer = setTimeout(() => {
      if (settle()) onError?.(new Error(`${event} timed out`));
    }, timeoutMs);
    timers.add(timer);

    live.pushEvent(
      event,
      payload,
      (reply) => {
        if (settle()) onReply?.(reply);
      },
      (error) => {
        if (settle()) onError?.(error);
      },
    );
  }

  return { pending: readonly(pending), push };
}
