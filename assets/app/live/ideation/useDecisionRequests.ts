import { computed, onUnmounted, ref, watch } from "vue";
import { useLive } from "@shared/composables/useLive";
import type { DecisionsPanelState } from "./decisionTypes";

export function useDecisionRequests(
  state: () => DecisionsPanelState,
  sessionId: () => number,
  epoch: () => string,
) {
  const live = useLive();
  const pending = ref<string | null>(null);
  const failure = ref<string | null>(null);
  const notice = computed(() => failure.value ?? state().error);
  const identity = () => JSON.stringify([epoch(), sessionId(), state().context, state().open]);
  let token: symbol | null = null;
  const keys = new Map<string, string>();
  const invalidate = () => {
    token = null;
    pending.value = null;
    failure.value = null;
  };
  watch(identity, invalidate);
  watch(
    () => JSON.stringify([epoch(), sessionId(), state().open]),
    () => keys.clear(),
  );
  onUnmounted(() => {
    invalidate();
    keys.clear();
  });

  function request(
    action: string,
    payload: Record<string, unknown> = {},
    mutationKey?: string,
    onSuccess?: () => void,
  ) {
    if (pending.value) return;
    const at = Symbol();
    const context = identity();
    token = at;
    pending.value = action;
    failure.value = null;
    if (mutationKey && !keys.has(mutationKey)) keys.set(mutationKey, crypto.randomUUID());
    const requestKey = mutationKey ? keys.get(mutationKey) : undefined;
    const finish = (code: string | null) => {
      if (token !== at || context !== identity()) return;
      token = null;
      pending.value = null;
      failure.value = code;
      if (!code) {
        onSuccess?.();
      }
    };
    live.pushEvent(
      `decisions_${action}`,
      {
        ...payload,
        epoch: epoch(),
        session_id: sessionId(),
        decision_context: state().context,
        ...(mutationKey ? { request_key: requestKey } : {}),
      },
      (reply) => {
        // The successful server patch may replace the panel context before its
        // reply arrives. Retire that receipt without changing the newer UI.
        if (reply?.status === "ok" && mutationKey && keys.get(mutationKey) === requestKey)
          keys.delete(mutationKey);
        finish(reply?.status === "ok" ? null : String(reply?.code ?? "unavailable"));
      },
      () => finish("offline"),
    );
  }
  return { request, pending, notice };
}
