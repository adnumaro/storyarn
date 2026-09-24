<script setup lang="ts">
import { computed, ref } from "vue";
import { useI18n } from "vue-i18n";
import { Check, Copy } from "@lucide/vue";
import { Button } from "@components/ui/button";
import { Checkbox } from "@components/ui/checkbox";
import { taskBasis, taskParts, taskSummary, type TaskPart } from "./decisionTask";
import type { DecisionRecord } from "./decisionTypes";

/**
 * Prepares the text of a task from what the reader sees of the decision. It is
 * copied by the person; nothing is sent anywhere.
 */
const { decision } = defineProps<{ decision: DecisionRecord }>();
const emit = defineEmits<{ close: [] }>();
const { t } = useI18n();
const parts = computed(() => taskParts(taskBasis(decision)));
// Sources name the notes behind the decision; they go in only when asked for.
const chosen = ref<TaskPart[]>(parts.value.filter((part) => part !== "sources"));
const copied = ref(false);
const failed = ref(false);

const text = computed(() =>
  taskSummary(decision, chosen.value, {
    t,
    origin: window.location.origin,
    decisionUrl: decisionUrl(),
  }),
);

function decisionUrl() {
  const url = new URL(window.location.href);
  url.search = new URLSearchParams({ decision: String(decision.id) }).toString();
  url.hash = "";
  return url.toString();
}
function toggle(part: TaskPart, value: boolean | "indeterminate") {
  chosen.value =
    value === true ? [...chosen.value, part] : chosen.value.filter((item) => item !== part);
  copied.value = false;
}
async function copy() {
  try {
    await navigator.clipboard.writeText(text.value);
    copied.value = true;
    failed.value = false;
  } catch {
    failed.value = true;
  }
}
</script>
<template>
  <div id="decision-prepare-task-form" class="flex flex-col gap-2.5">
    <div>
      <p class="text-[13px] font-medium">{{ t("brainstormingDecisions.tasks.prepareTitle") }}</p>
      <p class="mt-0.5 text-xs text-muted-foreground">
        {{ t("brainstormingDecisions.tasks.prepareDescription") }}
      </p>
    </div>
    <fieldset class="flex flex-wrap gap-x-3.5 gap-y-1.5">
      <legend class="sr-only">{{ t("brainstormingDecisions.tasks.include") }}</legend>
      <label
        v-for="part in parts"
        :key="part"
        :for="`decision-task-part-${part}`"
        class="inline-flex items-center gap-1.5 text-xs"
      >
        <Checkbox
          :id="`decision-task-part-${part}`"
          :model-value="chosen.includes(part)"
          @update:model-value="toggle(part, $event)"
        />
        {{ t(`brainstormingDecisions.tasks.parts.${part}`) }}
      </label>
    </fieldset>
    <pre
      id="decision-task-preview"
      class="max-h-60 overflow-y-auto rounded-lg border border-border bg-muted/40 p-2.5 font-sans text-xs leading-relaxed break-words whitespace-pre-wrap"
      >{{ text }}</pre>
    <p v-if="failed" role="alert" class="text-xs text-destructive">
      {{ t("brainstormingDecisions.tasks.copyFailed") }}
    </p>
    <div class="flex justify-end gap-1.5">
      <Button variant="ghost" size="sm" @click="emit('close')">{{
        t("brainstormingDecisions.tasks.close")
      }}</Button>
      <Button id="decision-task-copy" size="sm" @click="copy"
        ><component :is="copied ? Check : Copy" class="size-3.5" />{{
          copied ? t("brainstormingDecisions.tasks.copied") : t("brainstormingDecisions.tasks.copy")
        }}</Button
      >
    </div>
  </div>
</template>
