import { computed, onMounted, onUnmounted, ref, watch } from "vue";
import type { SessionTimer } from "../types";

function remainingTime(timer: SessionTimer | null): number {
  if (!timer) return 0;
  if (timer.status === "paused") return timer.remaining_seconds;
  if (timer.status !== "running") return 0;
  if (!timer.deadline_at) return timer.remaining_seconds;
  const difference = (Date.parse(timer.deadline_at) - Date.parse(timer.server_now)) / 1000;
  return Number.isFinite(difference) ? difference : timer.remaining_seconds;
}

/** Anchor the server's remaining time to a monotonic clock, independent of
 * wall-clock skew. A refresh recalibrates it; ticks never fetch board data. */
export function useSessionTimer(
  timer: () => SessionTimer | null,
  context: () => string,
  onElapsed: () => void,
) {
  const seconds = ref(0);
  let anchor = 0;
  let remaining = 0;
  let mounted = false;
  let interval: ReturnType<typeof setInterval> | undefined;
  let synchronized: string | null = null;
  function tick() {
    const current = timer();
    seconds.value = Math.max(
      0,
      Math.ceil(
        remaining - (current?.status === "running" ? (performance.now() - anchor) / 1000 : 0),
      ),
    );
    if (mounted && current?.status === "running" && seconds.value === 0) {
      clearInterval(interval);
      interval = undefined;
      const key = `${context()}:${current.id}:${current.version}`;
      if (synchronized !== key) {
        synchronized = key;
        onElapsed();
      }
    }
  }
  function calibrate() {
    clearInterval(interval);
    interval = undefined;
    const current = timer();
    anchor = performance.now();
    remaining = remainingTime(current);
    tick();
    if (mounted && current?.status === "running" && seconds.value > 0)
      interval = setInterval(tick, 250);
  }
  // LiveVue applies nested prop patches in place. Watch the clock inputs rather
  // than the timer object's identity so every persisted update recalibrates it.
  watch(
    [
      context,
      () => timer()?.id,
      () => timer()?.version,
      () => timer()?.status,
      () => timer()?.deadline_at,
      () => timer()?.server_now,
      () => timer()?.remaining_seconds,
    ],
    calibrate,
    { immediate: true },
  );
  onMounted(() => {
    mounted = true;
    calibrate();
  });
  onUnmounted(() => {
    mounted = false;
    clearInterval(interval);
  });
  const display = computed(() => {
    const value = seconds.value;
    const minutes = Math.floor(value / 60);
    const tail = String(value % 60).padStart(2, "0");
    return value >= 3600
      ? `${Math.floor(value / 3600)}:${String(minutes % 60).padStart(2, "0")}:${tail}`
      : `${minutes}:${tail}`;
  });
  return { seconds, display };
}
