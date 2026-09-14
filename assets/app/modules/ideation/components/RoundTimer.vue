<script setup lang="ts">
import { computed, onMounted, ref, watch } from "vue";
import { Pause, Play, Plus, Square, Timer } from "@lucide/vue";
import { Badge } from "@components/ui/badge";
import { Button } from "@components/ui/button";
import { Popover, PopoverContent, PopoverTrigger } from "@components/ui/popover";
import { useBoardText } from "../composables/useBoardText";
import { useSessionTimer } from "../composables/useSessionTimer";
import { activeTimer, timerDraft, useTimerWrites } from "../composables/useTimerWrites";
import type { TimerStart } from "../composables/useTimerWrites";
import type { Session, SessionTimer } from "../types";
import TimerStartForm from "./TimerStartForm.vue";

// The timer zone of the round in progress: big digits everyone reads, the
// facilitator's pause/resume/+1 min beside them, and "Start timer" while idle.
// The line under the header fills as time passes; this reports the fraction.
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
// The parent draws the line; it needs the first value once both are mounted.
onMounted(() => emit("progress", fraction.value));
const draft = ref(timerDraft());
const open = ref(false);
watch([() => epoch, () => session.id], () => {
  draft.value = timerDraft();
  open.value = false;
});
// The digits take the popover's place as soon as the timer runs.
watch(active, (value) => {
  if (value) open.value = false;
});
function onOpen(value: boolean) {
  open.value = value;
  if (!value) writes.clearFailure();
}
function start(options: TimerStart) {
  writes.start(options);
}
</script>
<template>
  <div class="pointer-events-auto flex shrink-0 items-center gap-2">
    <template v-if="elapsed">
      <span
        id="brainstorming-round-timer"
        class="text-[22px] font-semibold leading-none tabular-nums text-muted-foreground"
        :aria-label="`${t('ideation.timer.title')}: ${t('ideation.timer.elapsed')}`"
        >0:00</span
      >
      <Badge
        id="brainstorming-round-timer-elapsed"
        role="status"
        variant="outline"
        class="font-medium text-primary"
        >{{ t("ideation.timer.elapsed") }}</Badge
      >
    </template>
    <template v-else-if="active">
      <span
        id="brainstorming-round-timer"
        class="text-[22px] font-semibold leading-none tabular-nums"
        :class="running ? 'text-foreground' : 'text-muted-foreground'"
        :aria-label="`${t('ideation.timer.title')}: ${display}`"
        >{{ display }}</span
      >
      <Badge v-if="!running" variant="secondary" class="font-medium text-muted-foreground">{{
        t("ideation.timer.paused")
      }}</Badge>
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
          :disabled="writes.pending.value || (timer?.duration_seconds ?? 0) + 60 > 86400"
          @click="writes.control('extend_timer', seconds)"
        >
          <Plus class="size-3.5" />{{ t("ideation.timer.oneMinute") }}
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
    <Popover v-if="!active && mayManage" :open="open" @update:open="onOpen">
      <PopoverTrigger as-child>
        <Button id="brainstorming-round-timer-start" variant="ghost" size="sm"
          ><Timer class="size-3.5" />{{ t("ideation.timer.start") }}</Button
        >
      </PopoverTrigger>
      <PopoverContent
        align="end"
        class="w-80 space-y-4 p-4"
        :aria-label="t('ideation.timer.title')"
      >
        <div>
          <h2 class="text-sm font-semibold">{{ t("ideation.timer.title") }}</h2>
          <p class="mt-1 text-xs leading-relaxed text-muted-foreground">
            {{ t("ideation.timer.help") }}
          </p>
        </div>
        <p v-if="writes.failure.value" role="alert" class="text-xs text-destructive">
          {{ error(writes.failure.value) }}
        </p>
        <TimerStartForm
          v-model="draft"
          :private-mode="session.configuration.private_mode"
          :pending="writes.pending.value"
          @start="start"
        />
      </PopoverContent>
    </Popover>
  </div>
</template>
