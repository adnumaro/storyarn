<script setup lang="ts">
import { ref } from "vue";
import { useI18n } from "vue-i18n";
import { Button } from "@components/ui/button";
import { Textarea } from "@components/ui/textarea";
import type { ApplicationState } from "./decisionTypes";

type Mark = Exclude<ApplicationState, "not_applied">;

/**
 * The optional-note step of marking a target: a statement, not a verification.
 * The state is chosen here unless the caller already chose it.
 */
const {
  name,
  idPrefix,
  initial = "applied",
  choosable = true,
  pending = false,
} = defineProps<{
  name: string;
  idPrefix: string;
  initial?: Mark;
  choosable?: boolean;
  pending?: boolean;
}>();
const emit = defineEmits<{ confirm: [state: Mark, note: string | null]; cancel: [] }>();
const { t } = useI18n();
const choices: Mark[] = ["applied", "partially_applied", "no_change_needed"];
const choice = ref<Mark>(initial);
const note = ref("");
</script>
<template>
  <p class="text-[13px] font-medium">
    {{
      t("brainstormingDecisions.markAs", {
        name,
        state: t(`brainstormingDecisions.stateChips.${choice}`),
      })
    }}
  </p>
  <p class="mt-0.5 text-xs text-muted-foreground">
    {{ t("brainstormingDecisions.markStatement") }}
  </p>
  <div v-if="choosable" class="mt-2.5 flex rounded-md border border-border p-0.5" role="radiogroup">
    <button
      v-for="option in choices"
      :id="`${idPrefix}-${option}`"
      :key="option"
      type="button"
      role="radio"
      :aria-checked="choice === option"
      class="flex-1 rounded-[5px] px-1.5 py-1 text-[11.5px]"
      :class="choice === option ? 'bg-accent font-medium text-foreground' : 'text-muted-foreground'"
      @click="choice = option"
    >
      {{ t(`brainstormingDecisions.states.${option}`) }}
    </button>
  </div>
  <Textarea
    :id="`${idPrefix}-note`"
    v-model="note"
    class="mt-2.5"
    :rows="2"
    :maxlength="1000"
    :placeholder="t('brainstormingDecisions.notePlaceholder')"
  />
  <div class="mt-2.5 flex justify-end gap-1.5">
    <Button variant="ghost" size="sm" @click="emit('cancel')">{{
      t("brainstormingDecisions.cancel")
    }}</Button>
    <Button
      :id="`${idPrefix}-confirm`"
      size="sm"
      :disabled="pending"
      @click="emit('confirm', choice, note.trim() || null)"
      >{{ t(`brainstormingDecisions.markConfirm.${choice}`) }}</Button
    >
  </div>
</template>
