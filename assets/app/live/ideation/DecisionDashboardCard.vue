<script setup lang="ts">
import { computed, ref, watch } from "vue";
import { useI18n } from "vue-i18n";
import { ChevronDown, ExternalLink } from "@lucide/vue";
import { Button } from "@components/ui/button";
import { Popover, PopoverContent, PopoverTrigger } from "@components/ui/popover";
import LiveLink from "@components/navigation/LiveLink.vue";
import DecisionCard from "./DecisionCard.vue";
import DecisionMarkForm from "./DecisionMarkForm.vue";
import { applyTarget, type DashboardDecision } from "./decisionDashboard";
import type { ApplicationState } from "./decisionTypes";

/**
 * One dashboard row: the decision opens its session on the panel, and a
 * decision still to apply offers "Go apply" and "Mark applied" for the content
 * of its group, or the first one still pending.
 */
const {
  item,
  href,
  groupKey = null,
  pending = false,
  declared = 0,
} = defineProps<{
  item: DashboardDecision;
  href: string;
  groupKey?: string | null;
  pending?: boolean;
  /** Counts confirmed declarations; the mark form closes only once one lands. */
  declared?: number;
}>();
const emit = defineEmits<{
  declare: [
    item: DashboardDecision,
    targetKey: string,
    state: ApplicationState,
    note: string | null,
  ];
}>();
const { t } = useI18n();
const marking = ref(false);
const target = computed(() => applyTarget(item, groupKey));
const applyHref = computed(() =>
  target.value?.href
    ? `${target.value.href}?${new URLSearchParams({ decision: String(item.decision.id), session: String(item.sessionId) })}`
    : null,
);

// Grouped by content, one decision shows on several cards: each names its content.
const idBase = computed(() => `dashboard-decision-${item.decision.id}-${target.value?.key}`);
watch(
  () => declared,
  () => (marking.value = false),
);
function declare(state: ApplicationState, note: string | null) {
  if (!target.value) return;
  emit("declare", item, target.value.key, state, note);
}
</script>
<template>
  <DecisionCard
    :decision="item.decision"
    :href="href"
    link-mode="patch"
    :session-name="item.sessionTitle"
    :round-count="item.roundCount"
  >
    <template v-if="target && applyHref" #actions>
      <Button variant="outline" size="xs" as-child>
        <LiveLink :id="`${idBase}-apply`" :to="applyHref"
          ><ExternalLink class="size-3" />{{ t("brainstormingDecisions.about.goApply") }}</LiveLink
        >
      </Button>
      <Popover v-model:open="marking">
        <PopoverTrigger as-child>
          <Button :id="`${idBase}-mark`" variant="ghost" size="xs" :disabled="pending"
            >{{ t("brainstormingDecisions.markApplied") }}<ChevronDown class="size-3"
          /></Button>
        </PopoverTrigger>
        <PopoverContent align="end" class="w-[300px] p-3">
          <DecisionMarkForm
            :name="target.name"
            :id-prefix="`${idBase}-mark`"
            :pending="pending"
            @confirm="declare"
            @cancel="marking = false"
          />
        </PopoverContent>
      </Popover>
    </template>
  </DecisionCard>
</template>
