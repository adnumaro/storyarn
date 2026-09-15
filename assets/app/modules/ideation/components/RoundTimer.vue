<script setup lang="ts">
import { computed, onMounted, ref, watch } from "vue";
import { Pause, Play, Plus, Square } from "@lucide/vue";
import { useBoardText } from "../composables/useBoardText";
import { useSessionTimer } from "../composables/useSessionTimer";
import { activeTimer, DEFAULT_TIMER_SECONDS, useTimerWrites } from "../composables/useTimerWrites";
import type { Session, SessionTimer } from "../types";
import TimerDigits from "./TimerDigits.vue";

// The timer zone of the round in progress. Everyone reads the digits; the
// facilitator types a duration into them and presses play, then pauses,
// extends or cancels beside them. Reaching 0:00 is the whole message: the
// digits stay, editable again for the facilitator. The line under the header
// fills as time passes and this reports the fraction.
const { session, epoch, timer, canManage, canEdit } = defineProps<{
  session: Session;
  epoch: string;
  timer: SessionTimer | null;
  canManage: boolean;
  canEdit: boolean;
}>();
const emit = defineEmits<{ progress: [fraction: number] }>();
const { t, error } = useBoardText();
const mayManage = computed(() => canManage && canEdit && session.status === "open");
const writes = useTimerWrites(
  () => session,
  () => epoch,
  () => timer,
  () => mayManage.value,
);
// The header chip keeps the elapsed sync; a second instance must not repeat it.
const { seconds, display } = useSessionTimer(
  () => timer,
  () => `${epoch}:${session.id}`,
  () => {},
);
const active = computed(() => activeTimer(timer));
const running = computed(() => timer?.status === "running");
const elapsed = computed(
  () => timer?.status === "elapsed" || (timer?.status === "running" && seconds.value === 0),
);
const fraction = computed(() => {
  if (elapsed.value) return 1;
  if (!active.value || !timer?.duration_seconds) return 0;
  return Math.min(1, Math.max(0, 1 - seconds.value / timer.duration_seconds));
});
watch(fraction, (value) => emit("progress", value));
onMounted(() => emit("progress", fraction.value));
// What the digits show while nothing runs: 00:00 once time is up, else the last duration.
const draft = ref(DEFAULT_TIMER_SECONDS);
const idle = computed(() => (elapsed.value ? 0 : draft.value));
watch([() => epoch, () => session.id], () => {
  draft.value = DEFAULT_TIMER_SECONDS;
});
// A stopped clock leaves its full duration in the digits, on every device.
watch(
  () => timer?.version,
  () => {
    if (timer?.status === "cancelled") draft.value = timer.duration_seconds;
  },
  { immediate: true },
);
function start(value: number) {
  draft.value = value;
  writes.start({ seconds: value, close_contributions_on_expiry: false });
}
</script>
<template>
  <div class="pointer-events-auto flex shrink-0 items-center gap-2">
    <template v-if="active && !elapsed">
      <span
        id="brainstorming-round-timer"
        class="text-[22px] font-semibold leading-none tabular-nums"
        :class="running ? 'text-foreground' : 'text-muted-foreground'"
        :aria-label="`${t('ideation.timer.title')}: ${display}`"
        >{{ display }}</span
      >
      <Pause
        v-if="!running && !mayManage"
        class="size-3.5 text-muted-foreground"
        :aria-label="t('ideation.timer.paused')"
      />
      <template v-if="mayManage && seconds > 0">
        <button
          :id="running ? 'brainstorming-round-timer-pause' : 'brainstorming-round-timer-resume'"
          type="button"
          class="toolbar-btn"
          :aria-label="t(running ? 'ideation.timer.pause' : 'ideation.timer.resume')"
          :aria-disabled="writes.pending.value"
          :class="writes.pending.value ? 'opacity-50' : ''"
          @click="writes.control(running ? 'pause_timer' : 'resume_timer', seconds)"
        >
          <Pause v-if="running" class="size-3.5" /><Play v-else class="size-3.5" />
        </button>
        <button
          id="brainstorming-round-timer-extend"
          type="button"
          class="toolbar-btn gap-1"
          :aria-label="t('ideation.timer.oneMinute')"
          :disabled="writes.pending.value || (timer?.duration_seconds ?? 0) + 60 > 86400"
          @click="writes.control('extend_timer', seconds)"
        >
          <Plus class="size-3.5" /><span class="max-md:hidden">{{
            t("ideation.timer.oneMinute")
          }}</span>
        </button>
      </template>
      <button
        v-if="mayManage"
        id="brainstorming-round-timer-cancel"
        type="button"
        class="toolbar-btn"
        :aria-label="t('ideation.timer.cancel')"
        :disabled="writes.pending.value"
        @click="writes.control('cancel_timer', seconds)"
      >
        <Square class="size-3.5" />
      </button>
    </template>
    <TimerDigits
      v-else-if="mayManage"
      :seconds="idle"
      :pending="writes.pending.value"
      id-prefix="brainstorming-round-timer"
      @update:seconds="draft = $event"
      @start="start"
    />
    <span
      v-else-if="elapsed"
      id="brainstorming-round-timer"
      role="status"
      class="text-[22px] font-semibold leading-none tabular-nums text-muted-foreground"
      :aria-label="`${t('ideation.timer.title')}: ${t('ideation.timer.elapsed')}`"
      >00:00</span
    >
    <p v-if="writes.failure.value" role="alert" class="text-xs text-destructive">
      {{ error(writes.failure.value) }}
    </p>
  </div>
</template>
