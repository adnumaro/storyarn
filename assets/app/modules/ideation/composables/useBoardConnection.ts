import { onMounted, onUnmounted, ref, watch } from "vue";
import { useLive } from "@shared/composables/useLive";
import type { Board, BoardContext, Reply, Request } from "../types";

export function useBoardConnection(board: () => Board, reset: (reason: string) => void) {
  const live = useLive();
  const online = ref(true);
  let disposed = false;
  let interval: ReturnType<typeof setInterval> | undefined;
  let eventRef: number | undefined;
  let generation = 0;
  const context = (): BoardContext => ({
    epoch: board().epoch,
    session_id: board().session?.id ?? null,
  });

  const request: Request = <T>(event: string, payload: Record<string, unknown>, at = context()) => {
    const started = generation;
    return new Promise<Reply<T>>((resolve) => {
      live.pushEvent(
        event,
        { ...payload, ...at },
        (raw) => {
          if (disposed || started !== generation || at.epoch !== board().epoch) {
            resolve({ status: "error", code: "stale_board" });
            return;
          }
          online.value = true;
          // LiveView resolves a push that carried no reply (e.g. a redirect) as null.
          resolve((raw ?? { status: "error", code: "unavailable" }) as unknown as Reply<T>);
        },
        () => {
          online.value = false;
          resolve({ status: "error", code: "offline" });
        },
      );
    });
  };

  function invalidate(reason: string) {
    generation++;
    reset(reason);
  }

  function sync() {
    void request("sync_board", {});
  }

  watch(
    () => board().epoch,
    () => invalidate("reconnected"),
  );
  onMounted(() => {
    eventRef = live.handleEvent("brainstorming_reset", (payload) => {
      invalidate(String(payload.reason));
    });
    interval = setInterval(sync, 20_000);
    window.addEventListener("online", sync);
  });
  onUnmounted(() => {
    disposed = true;
    clearInterval(interval);
    window.removeEventListener("online", sync);
    if (eventRef !== undefined) live.removeHandleEvent(eventRef);
  });
  return { request, online, context, sync };
}
