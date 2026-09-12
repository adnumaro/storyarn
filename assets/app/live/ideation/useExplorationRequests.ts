import { onUnmounted, ref, watch } from "vue";
import { useLive } from "@shared/composables/useLive";
import type { ExplorationAction, ExplorationLauncherState } from "./explorationTypes";

interface ExplorationRequestContext {
  state: () => ExplorationLauncherState;
  sourceKey: () => string;
  enabled: () => boolean;
}

export function useExplorationRequests(context: ExplorationRequestContext) {
  const live = useLive();
  const pending = ref<string | null>(null);
  const failure = ref<string | null>(null);
  const requestKeys = new Map<string, string>();
  let token: symbol | null = null;

  function invalidate() {
    token = null;
    pending.value = null;
    failure.value = null;
  }

  function identity() {
    return JSON.stringify([
      context.sourceKey(),
      context.state().context,
      context.state().open,
      context.enabled(),
    ]);
  }

  watch(identity, invalidate);
  watch([context.sourceKey, () => context.state().open, context.enabled], () =>
    requestKeys.clear(),
  );
  onUnmounted(() => {
    invalidate();
    requestKeys.clear();
  });

  function request(action: ExplorationAction, payload: Record<string, unknown> = {}, key?: string) {
    if (pending.value || !context.enabled()) return;
    const at = Symbol();
    const source = identity();
    token = at;
    pending.value = key ?? action;
    failure.value = null;
    if (key && !requestKeys.has(key)) requestKeys.set(key, crypto.randomUUID());

    const finish = (code: string | null) => {
      if (token !== at || source !== identity()) return;
      token = null;
      pending.value = null;
      failure.value = code;
      if (!code && key) requestKeys.delete(key);
    };

    live.pushEvent(
      `exploration_${action}`,
      {
        ...payload,
        exploration_context: context.state().context,
        source_key: context.sourceKey(),
        ...(key ? { request_key: requestKeys.get(key) } : {}),
      },
      (reply) => finish(reply?.status === "ok" ? null : String(reply?.code ?? "unavailable")),
      () => finish("offline"),
    );
  }

  return { pending, failure, request };
}
