<script setup lang="ts">
import { computed, ref, watch } from "vue";
import { Timer, Play, Pause, Plus, Square, LockKeyhole } from "@lucide/vue";
import { Button } from "@components/ui/button";
import { Popover, PopoverContent, PopoverTrigger } from "@components/ui/popover";
import { useBoardText } from "./composables/useBoardText";
import { useSessionTimer } from "./composables/useSessionTimer";
import { activeTimer, DEFAULT_TIMER_SECONDS, useTimerWrites } from "./composables/useTimerWrites";
import type { TimerControl } from "./composables/useTimerWrites";
import TimerDigits from "./components/TimerDigits.vue";
import type { Session, SessionTimer } from "./types";

const { session, epoch, timer, canManage, canEdit } = defineProps<{
  session: Session;
  epoch: string;
  timer: SessionTimer | null;
  canManage: boolean;
  canEdit: boolean;
}>();
const { t, error } = useBoardText();
const mayManage = computed(() => canManage && canEdit && session.status === "open");
const writes = useTimerWrites(
  () => session,
  () => epoch,
  () => timer,
  () => mayManage.value,
);
const { pending, failure } = writes;
const active = computed(() => activeTimer(timer));
const { seconds, display } = useSessionTimer(
  () => timer,
  () => `${epoch}:${session.id}`,
  () => writes.sync(),
);
const elapsed = computed(
  () => timer?.status === "elapsed" || (timer?.status === "running" && seconds.value === 0),
);
const label = computed(() => {
  if (active.value || elapsed.value) return display.value;
  return t("ideation.timer.title");
});
const draft = ref(DEFAULT_TIMER_SECONDS);
watch(
  [() => epoch, () => session.id],
  () => {
    draft.value = DEFAULT_TIMER_SECONDS;
  },
  { flush: "sync" },
);
function onOpenChange(open: boolean) {
  if (!open) writes.clearFailure();
}
function start(value: number) {
  draft.value = value;
  writes.start({ seconds: value, close_contributions_on_expiry: false });
}
function control(event: TimerControl) {
  writes.control(event, seconds.value);
}
</script>
<template>
  <Popover @update:open="onOpenChange">
    <PopoverTrigger as-child>
      <button
        id="brainstorming-timer-trigger"
        type="button"
        class="toolbar-btn gap-1.5"
        :class="active || elapsed ? 'text-primary' : ''"
        :aria-label="`${t('ideation.timer.title')}: ${label}`"
      >
        <Timer class="size-3.5" />
        <span
          id="brainstorming-timer-countdown"
          class="tabular-nums"
          :class="!active && !elapsed ? 'hidden sm:inline' : ''"
          >{{ label }}</span
        >
        <Pause
          v-if="timer?.status === 'paused'"
          class="size-3"
          :aria-label="t('ideation.timer.paused')"
        />
        <LockKeyhole
          v-if="!session.contributions_open"
          class="size-3"
          :aria-label="t('ideation.timer.contributionsClosed')"
        />
      </button>
    </PopoverTrigger>
    <PopoverContent
      align="start"
      class="w-80 space-y-4 p-4"
      :aria-label="t('ideation.timer.title')"
    >
      <h2 class="text-sm font-semibold">{{ t("ideation.timer.title") }}</h2>
      <p v-if="failure" role="alert" class="text-xs text-destructive">{{ error(failure) }}</p>
      <div v-if="active || timer?.status === 'elapsed'" class="space-y-3 text-center">
        <p class="text-3xl font-medium tabular-nums">{{ display }}</p>
        <p v-if="timer?.status === 'paused'" class="text-xs text-muted-foreground">
          {{ t("ideation.timer.paused") }}
        </p>
        <p
          v-if="timer?.outcome && timer.outcome !== 'completed'"
          class="text-xs text-muted-foreground"
        >
          {{ t(`ideation.timer.outcomes.${timer.outcome}`) }}
        </p>
        <div v-if="mayManage && active" class="flex flex-wrap items-center justify-center gap-1">
          <Button
            v-if="seconds > 0"
            :id="
              timer?.status === 'running'
                ? 'brainstorming-timer-pause'
                : 'brainstorming-timer-resume'
            "
            size="sm"
            variant="outline"
            :aria-disabled="pending"
            :class="pending ? 'opacity-50' : ''"
            @click="control(timer?.status === 'running' ? 'pause_timer' : 'resume_timer')"
            ><Pause v-if="timer?.status === 'running'" class="size-3" /><Play
              v-else
              class="size-3"
            />{{
              t(timer?.status === "running" ? "ideation.timer.pause" : "ideation.timer.resume")
            }}</Button
          >
          <Button
            v-if="seconds > 0"
            id="brainstorming-timer-extend"
            size="sm"
            variant="ghost"
            :disabled="pending || (timer?.duration_seconds ?? 0) + 60 > 86400"
            @click="control('extend_timer')"
            ><Plus class="size-3" />{{ t("ideation.timer.oneMinute") }}</Button
          >
          <Button
            id="brainstorming-timer-cancel"
            size="sm"
            variant="ghost"
            :disabled="pending"
            @click="control('cancel_timer')"
            ><Square class="size-3" />{{ t("ideation.timer.cancel") }}</Button
          >
        </div>
      </div>
      <div v-if="mayManage && !active" class="flex justify-center">
        <TimerDigits
          :seconds="draft"
          :pending="pending"
          @update:seconds="draft = $event"
          @start="start"
        />
      </div>
      <div class="space-y-2 border-t pt-3">
        <p
          class="text-xs"
          :class="session.contributions_open ? 'text-muted-foreground' : 'text-foreground'"
        >
          {{
            t(
              session.contributions_open
                ? "ideation.timer.contributionsOpen"
                : "ideation.timer.contributionsClosed",
            )
          }}
        </p>
        <p v-if="!session.contributions_open" class="text-xs text-muted-foreground">
          {{ t("ideation.timer.closedHelp") }}
        </p>
        <Button
          v-if="mayManage"
          id="brainstorming-contributions-toggle"
          type="button"
          size="sm"
          variant="outline"
          class="w-full"
          :disabled="pending"
          @click="writes.send('set_contributions_open', { open: !session.contributions_open })"
          >{{
            t(session.contributions_open ? "ideation.timer.closeNow" : "ideation.timer.reopen")
          }}</Button
        >
      </div>
    </PopoverContent>
  </Popover>
</template>
