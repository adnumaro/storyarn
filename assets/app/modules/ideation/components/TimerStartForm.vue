<script setup lang="ts">
import { computed, watch } from "vue";
import { Play } from "@lucide/vue";
import { Button } from "@components/ui/button";
import { Input } from "@components/ui/input";
import { Checkbox } from "@components/ui/checkbox";
import { Label } from "@components/ui/label";
import { useBoardText } from "../composables/useBoardText";
import type { TimerDraft, TimerStart } from "../composables/useTimerWrites";

// The one timer form, used from the header chip and from the round bar. The
// parent owns the draft so choices survive closing the popover.
const {
  modelValue,
  privateMode = false,
  pending = false,
} = defineProps<{
  modelValue: TimerDraft;
  privateMode?: boolean;
  pending?: boolean;
}>();
const emit = defineEmits<{
  "update:modelValue": [draft: TimerDraft];
  start: [options: TimerStart];
}>();
const { t } = useBoardText();
const validDuration = computed(
  () =>
    Number.isInteger(Number(modelValue.duration)) &&
    Number(modelValue.duration) >= 15 &&
    Number(modelValue.duration) <= 86400,
);
function update(changes: Partial<TimerDraft>) {
  emit("update:modelValue", { ...modelValue, ...changes });
}
function start() {
  if (!validDuration.value) return;
  emit("start", {
    seconds: Number(modelValue.duration),
    reveal_on_expiry: modelValue.reveal && privateMode,
    close_contributions_on_expiry: modelValue.closeContributions,
  });
}
watch(
  () => privateMode,
  (enabled) => {
    if (!enabled && modelValue.reveal) update({ reveal: false });
  },
);
</script>
<template>
  <form class="space-y-3" @submit.prevent="start">
    <div class="flex gap-1">
      <Button
        v-for="minutes in [1, 5, 10]"
        :key="minutes"
        type="button"
        size="sm"
        variant="outline"
        class="flex-1"
        :disabled="pending"
        @click="update({ duration: minutes * 60 })"
        >{{ t("ideation.timer.preset", { minutes }) }}</Button
      >
    </div>
    <div class="space-y-1.5">
      <Label for="brainstorming-timer-duration" class="text-xs">{{
        t("ideation.timer.duration")
      }}</Label>
      <Input
        id="brainstorming-timer-duration"
        :model-value="modelValue.duration"
        type="number"
        :min="15"
        :max="86400"
        step="1"
        :disabled="pending"
        :aria-describedby="'brainstorming-timer-duration-help'"
        @update:model-value="update({ duration: $event as string | number })"
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
          :model-value="modelValue.reveal"
          :disabled="pending || !privateMode"
          @update:model-value="update({ reveal: $event === true })"
        />
        <div class="space-y-1">
          <Label for="brainstorming-timer-reveal" class="text-xs leading-relaxed">{{
            t("ideation.timer.reveal")
          }}</Label>
          <p v-if="!privateMode" class="text-[11px] text-muted-foreground">
            {{ t("ideation.timer.revealHelp") }}
          </p>
        </div>
      </div>
      <div class="flex items-start gap-2">
        <Checkbox
          id="brainstorming-timer-close"
          :model-value="modelValue.closeContributions"
          :disabled="pending"
          @update:model-value="update({ closeContributions: $event === true })"
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
</template>
