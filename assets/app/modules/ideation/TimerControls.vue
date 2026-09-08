<script setup lang="ts">
import { computed, onUnmounted, ref, shallowRef, watch } from "vue";
import { Timer, Play, Pause, Plus, Square, LockKeyhole } from "@lucide/vue";
import { Button } from "@components/ui/button";
import { Popover, PopoverContent, PopoverTrigger } from "@components/ui/popover";
import { Input } from "@components/ui/input";
import { Checkbox } from "@components/ui/checkbox";
import { Label } from "@components/ui/label";
import { useLive } from "@shared/composables/useLive";
import { useBoardText } from "./composables/useBoardText";
import { useSessionTimer } from "./composables/useSessionTimer";
import type { Session, SessionTimer } from "./types";

const { session, epoch, timer, canManage, canEdit } = defineProps<{
  session: Session;
  epoch: string;
  timer: SessionTimer | null;
  canManage: boolean;
  canEdit: boolean;
}>();
const live = useLive();
const { t, error } = useBoardText();
const duration = ref<string | number>(300);
const reveal = ref(false);
const closeContributions = ref(false);
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
const pendingWrite = shallowRef<PendingWrite | null>(null);
const pending = computed(() => pendingWrite.value !== null);
const failure = ref<string | null>(null);
const mayManage = computed(() => canManage && canEdit && session.status === "open");
const active = computed(() => timer?.status === "running" || timer?.status === "paused");
const validDuration = computed(
  () =>
    Number.isInteger(Number(duration.value)) &&
    Number(duration.value) >= 15 &&
    Number(duration.value) <= 86400,
);
const { seconds, display } = useSessionTimer(
  () => timer,
  () => `${epoch}:${session.id}`,
  () => live.pushEvent("sync_board", { epoch, session_id: session.id }),
);
const elapsed = computed(
  () => timer?.status === "elapsed" || (timer?.status === "running" && seconds.value === 0),
);
const label = computed(() => {
  if (elapsed.value) return t("ideation.timer.elapsed");
  if (active.value) return display.value;
  return t("ideation.timer.title");
});
function send(event: string, payload: Record<string, unknown>) {
  if (!mayManage.value || pending.value) return;
  failure.value = null;
  const attempt: PendingWrite = {
    epoch,
    sessionId: session.id,
    revision: session.revision,
    timerVersion: event === "set_contributions_open" ? null : (timer?.version ?? 0),
    acknowledgedRevision: null,
  };
  pendingWrite.value = attempt;
  live.pushEvent(
    event,
    {
      ...payload,
      epoch,
      session_id: session.id,
      revision: session.revision,
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
    pendingWrite.value === attempt && attempt.epoch === epoch && attempt.sessionId === session.id
  );
}
function releaseAcknowledgedWrite() {
  const attempt = pendingWrite.value;
  if (!attempt || !currentAttempt(attempt) || attempt.acknowledgedRevision === null) return;
  if (session.revision < attempt.acknowledgedRevision) return;
  // An effective timer write advances both counters. Wait for both props even
  // when LiveVue patches them in place or the reply arrives before the refresh.
  const changed = attempt.acknowledgedRevision > attempt.revision;
  if (
    attempt.timerVersion !== null &&
    (timer?.version ?? 0) < attempt.timerVersion + Number(changed)
  )
    return;
  pendingWrite.value = null;
}
function onOpenChange(open: boolean) {
  if (!open) failure.value = null;
}
function start() {
  if (!validDuration.value || active.value) return;
  send("start_timer", {
    seconds: Number(duration.value),
    reveal_on_expiry: reveal.value && session.configuration.private_mode,
    close_contributions_on_expiry: closeContributions.value,
  });
}
function control(event: "pause_timer" | "resume_timer" | "cancel_timer" | "extend_timer") {
  if (!timer || !active.value || (event !== "cancel_timer" && seconds.value === 0)) return;
  send(event, {
    timer_version: timer.version,
    ...(event === "extend_timer" ? { seconds: 60 } : {}),
  });
}
watch(
  () => session.configuration.private_mode,
  (enabled) => {
    if (!enabled) reveal.value = false;
  },
);
watch([() => session.revision, () => timer?.version], releaseAcknowledgedWrite);
watch(
  [() => epoch, () => session.id],
  () => {
    pendingWrite.value = null;
    failure.value = null;
    duration.value = 300;
    reveal.value = false;
    closeContributions.value = false;
  },
  { flush: "sync" },
);
watch(
  mayManage,
  (allowed) => {
    if (!allowed) {
      pendingWrite.value = null;
      failure.value = null;
    }
  },
  { flush: "sync" },
);
onUnmounted(() => {
  pendingWrite.value = null;
});
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
    <span role="status" class="sr-only">{{ elapsed ? t("ideation.timer.elapsed") : "" }}</span>
    <PopoverContent
      align="start"
      class="w-80 space-y-4 p-4"
      :aria-label="t('ideation.timer.title')"
    >
      <div>
        <h2 class="text-sm font-semibold">{{ t("ideation.timer.title") }}</h2>
        <p class="mt-1 text-xs leading-relaxed text-muted-foreground">
          {{ t("ideation.timer.help") }}
        </p>
      </div>
      <p v-if="failure" role="alert" class="text-xs text-destructive">{{ error(failure) }}</p>
      <div v-if="active || timer?.status === 'elapsed'" class="space-y-3 text-center">
        <p class="text-3xl font-medium tabular-nums">{{ display }}</p>
        <p v-if="elapsed" id="brainstorming-timer-finished" class="text-xs text-primary">
          {{ t("ideation.timer.elapsed") }}
        </p>
        <p v-else-if="timer?.status === 'paused'" class="text-xs text-muted-foreground">
          {{ t("ideation.timer.paused") }}
        </p>
        <p
          v-if="timer?.outcome && timer.outcome !== 'completed'"
          class="text-xs text-muted-foreground"
        >
          {{ t(`ideation.timer.outcomes.${timer.outcome}`) }}
        </p>
        <p v-if="active && timer?.reveal_on_expiry" class="text-xs text-muted-foreground">
          {{ t("ideation.timer.reveal") }}
        </p>
        <p
          v-if="active && timer?.close_contributions_on_expiry"
          class="text-xs text-muted-foreground"
        >
          {{ t("ideation.timer.close") }}
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
      <form v-if="mayManage && !active" class="space-y-3" @submit.prevent="start">
        <div class="flex gap-1">
          <Button
            v-for="minutes in [1, 5, 10]"
            :key="minutes"
            type="button"
            size="sm"
            variant="outline"
            class="flex-1"
            :disabled="pending"
            @click="duration = minutes * 60"
            >{{ t("ideation.timer.preset", { minutes }) }}</Button
          >
        </div>
        <div class="space-y-1.5">
          <Label for="brainstorming-timer-duration" class="text-xs">{{
            t("ideation.timer.duration")
          }}</Label>
          <Input
            id="brainstorming-timer-duration"
            v-model="duration"
            type="number"
            :min="15"
            :max="86400"
            step="1"
            :disabled="pending"
            :aria-describedby="'brainstorming-timer-duration-help'"
          />
          <p id="brainstorming-timer-duration-help" class="text-[11px] text-muted-foreground">
            {{ t("ideation.timer.durationHelp") }}
          </p>
        </div>
        <fieldset class="space-y-2 border-t pt-3">
          <legend class="text-xs font-medium">{{ t("ideation.timer.whenElapsed") }}</legend>
          <p class="text-xs text-muted-foreground">{{ t("ideation.timer.notifyOnly") }}</p>
          <div class="flex items-start gap-2">
            <Checkbox
              id="brainstorming-timer-reveal"
              :model-value="reveal"
              :disabled="pending || !session.configuration.private_mode"
              @update:model-value="reveal = $event === true"
            />
            <div class="space-y-1">
              <Label for="brainstorming-timer-reveal" class="text-xs leading-relaxed">{{
                t("ideation.timer.reveal")
              }}</Label>
              <p
                v-if="!session.configuration.private_mode"
                class="text-[11px] text-muted-foreground"
              >
                {{ t("ideation.timer.revealHelp") }}
              </p>
            </div>
          </div>
          <div class="flex items-start gap-2">
            <Checkbox
              id="brainstorming-timer-close"
              :model-value="closeContributions"
              :disabled="pending"
              @update:model-value="closeContributions = $event === true"
            />
            <Label for="brainstorming-timer-close" class="text-xs leading-relaxed">{{
              t("ideation.timer.close")
            }}</Label>
          </div>
        </fieldset>
        <Button
          id="brainstorming-timer-start"
          type="submit"
          size="sm"
          class="w-full"
          :disabled="pending || !validDuration"
          ><Play class="size-3" />{{ t("ideation.timer.start") }}</Button
        >
      </form>
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
          @click="send('set_contributions_open', { open: !session.contributions_open })"
          >{{
            t(session.contributions_open ? "ideation.timer.closeNow" : "ideation.timer.reopen")
          }}</Button
        >
      </div>
    </PopoverContent>
  </Popover>
</template>
