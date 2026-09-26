<script setup lang="ts">
import { computed, ref } from "vue";
import { useI18n } from "vue-i18n";
import { ChevronRight } from "@lucide/vue";
import type { DecisionHistoryEntry } from "./decisionTypes";
import { formatDate } from "@shared/utils/date-utils";

const { entries } = defineProps<{ entries: DecisionHistoryEntry[] }>();
const { t, locale } = useI18n();
const expanded = ref<Set<string>>(new Set());
const newest = computed(() => entries[0]?.id ?? null);

// Emerald marks an agreement or an application, amber a changed source,
// muted a record that closes the decision; everything else stays neutral.
function dot(entry: DecisionHistoryEntry) {
  if (entry.kind === "application")
    return entry.operation === "applied" || entry.operation === "no_change_needed"
      ? "bg-emerald-600 dark:bg-emerald-400"
      : "bg-amber-600 dark:bg-amber-400";
  if (["accept", "register", "registered"].includes(entry.operation))
    return "bg-emerald-600 dark:bg-emerald-400";
  if (entry.operation === "withdraw" || entry.operation === "supersede")
    return "bg-muted-foreground";
  return "bg-foreground/55";
}
function label(entry: DecisionHistoryEntry) {
  if (entry.kind === "record") return t(`brainstormingDecisions.historyActions.${entry.operation}`);
  if (entry.kind === "task")
    return t(`brainstormingDecisions.historyActions.task_${entry.operation}`, {
      task: entry.targetName,
    });
  if (!entry.targetName)
    return entry.operation === "no_change_needed"
      ? t("brainstormingDecisions.historyActions.decisionNoChange")
      : t("brainstormingDecisions.historyActions.decisionNotApplied");
  return t(`brainstormingDecisions.historyActions.${entry.operation}`, {
    target: entry.targetName,
  });
}
function summary(entry: DecisionHistoryEntry) {
  if (entry.kind === "task") return entry.url ?? "";
  if (entry.kind === "application")
    return entry.targetType
      ? `${t(`brainstormingDecisions.states.${entry.operation}`)} · ${entry.targetName} · ${t(`brainstormingDecisions.targetTypes.${entry.targetType}`)}`
      : t(`brainstormingDecisions.states.${entry.operation}`);
  return recordSummary(entry);
}
function recordSummary(entry: DecisionHistoryEntry) {
  const actor = entry.actorName || t("brainstormingDecisions.formerMember");
  if (entry.operation === "registered")
    return t("brainstormingDecisions.historySummaries.registered", { name: actor });
  if (entry.operation === "propose" || entry.operation === "revise")
    return t("brainstormingDecisions.historySummaries.waiting", {
      name: entry.responsibleName || t("brainstormingDecisions.formerMember"),
    });
  if (entry.operation === "accept")
    return t("brainstormingDecisions.historySummaries.acceptedBy", { name: actor });
  return entry.title ?? "";
}
function date(value: string) {
  return formatDate(value, locale.value, "datetime");
}
function toggle(id: string) {
  const next = new Set(expanded.value);
  if (next.has(id)) next.delete(id);
  else next.add(id);
  expanded.value = next;
}
function open(entry: DecisionHistoryEntry) {
  return entry.id === newest.value ? !expanded.value.has(entry.id) : expanded.value.has(entry.id);
}
</script>
<template>
  <ol class="mt-2.5 ml-[5px] flex flex-col" :aria-label="t('brainstormingDecisions.history')">
    <li
      v-for="entry in entries"
      :key="entry.id"
      :data-history-entry="entry.kind"
      :data-operation="entry.operation"
      class="relative border-l border-border pb-3.5 pl-[22px] last:pb-0"
    >
      <span
        class="absolute top-[5px] -left-[5px] size-[9px] rounded-full shadow-[0_0_0_3px_hsl(var(--surface))]"
        :class="dot(entry)"
      />
      <div class="flex flex-wrap items-baseline gap-2">
        <span class="text-[13px] leading-[18px] font-medium">{{ label(entry) }}</span>
        <span class="text-xs text-muted-foreground">{{
          entry.actorName || t("brainstormingDecisions.formerMember")
        }}</span>
        <span class="flex-1" />
        <span class="text-[11px] whitespace-nowrap text-muted-foreground">{{
          date(entry.at)
        }}</span>
      </div>
      <p class="mt-0.5 text-xs text-muted-foreground">{{ summary(entry) }}</p>
      <template v-if="entry.text">
        <p
          v-if="open(entry)"
          class="mt-1.5 rounded-lg bg-muted/40 px-2.5 py-2 text-xs leading-normal text-pretty break-words whitespace-pre-wrap text-foreground"
        >
          {{ entry.text }}
        </p>
        <button
          type="button"
          class="mt-[3px] inline-flex items-center gap-1 text-[11px] text-muted-foreground hover:text-foreground"
          :aria-expanded="open(entry)"
          @click="toggle(entry.id)"
        >
          <ChevronRight
            class="size-2.5 transition-transform"
            :class="open(entry) ? 'rotate-90' : ''"
          />{{
            open(entry)
              ? t("brainstormingDecisions.hideFullText")
              : t("brainstormingDecisions.showFullText")
          }}
        </button>
      </template>
    </li>
  </ol>
</template>
