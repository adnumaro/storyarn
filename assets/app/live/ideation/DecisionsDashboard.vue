<script setup lang="ts">
import { computed, ref, type Component } from "vue";
import { useI18n } from "vue-i18n";
import { ChevronDown, ChevronUp, Clapperboard, FileText, ListChecks, Workflow } from "@lucide/vue";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@components/ui/select";
import { Switch } from "@components/ui/switch";
import DecisionDashboardCard from "./DecisionDashboardCard.vue";
import {
  dashboardDecisions,
  groupByTarget,
  type ApplicationFilter,
  type DashboardDecision,
  type DecisionSessionGroup,
  type StatusFilter,
} from "./decisionDashboard";
import type { ApplicationState, DecisionTargetType } from "./decisionTypes";

/**
 * Every decision of the project, as the panel lists them, with the session
 * each one belongs to. Rows open their session with the panel on the decision.
 */
const {
  groups,
  baseUrl,
  pending = false,
  declared = 0,
} = defineProps<{
  groups: DecisionSessionGroup[];
  baseUrl: string;
  pending?: boolean;
  /** Counts confirmed declarations; a mark form closes only once one lands. */
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
const icons: Record<DecisionTargetType, Component> = {
  sheet: FileText,
  flow: Workflow,
  scene: Clapperboard,
};
const statusOptions: StatusFilter[] = ["all", "proposed", "accepted", "retired"];
const applicationOptions: ApplicationFilter[] = ["all", "toApply", "applied", "noChange"];
const status = ref<StatusFilter>("all");
const application = ref<ApplicationFilter>("all");
const grouped = ref(false);
const showRetired = ref(false);
const listed = computed(() => dashboardDecisions(groups, status.value, application.value));
const targetGroups = computed(() => groupByTarget([...listed.value.live, ...listed.value.retired]));
function href(item: DashboardDecision) {
  return `${baseUrl}/${item.sessionId}?decision=${item.decision.id}`;
}
</script>
<template>
  <section id="brainstorming-decisions-dashboard" class="space-y-4">
    <div class="flex flex-wrap items-center gap-2">
      <Select v-model="status">
        <SelectTrigger id="decisions-dashboard-status" class="h-8 w-auto min-w-40 text-xs"
          ><SelectValue
        /></SelectTrigger>
        <SelectContent
          ><SelectItem v-for="option in statusOptions" :key="option" :value="option">{{
            t(`brainstormingDecisions.dashboard.status.${option}`)
          }}</SelectItem></SelectContent
        >
      </Select>
      <Select v-model="application">
        <SelectTrigger id="decisions-dashboard-application" class="h-8 w-auto min-w-40 text-xs"
          ><SelectValue
        /></SelectTrigger>
        <SelectContent
          ><SelectItem v-for="option in applicationOptions" :key="option" :value="option">{{
            t(`brainstormingDecisions.dashboard.application.${option}`)
          }}</SelectItem></SelectContent
        >
      </Select>
      <span class="flex-1" />
      <label class="flex items-center gap-2 text-xs text-muted-foreground">
        <Switch id="decisions-dashboard-group" v-model="grouped" />
        {{ t("brainstormingDecisions.dashboard.groupByContent") }}
      </label>
    </div>
    <p
      v-if="!listed.live.length && !listed.retired.length"
      class="rounded-lg border border-dashed border-border px-4 py-8 text-center text-sm text-muted-foreground"
    >
      {{ t("brainstormingDecisions.dashboard.empty") }}
    </p>
    <template v-else-if="grouped">
      <section
        v-for="group in targetGroups"
        :key="group.key"
        :data-decision-group="group.key"
        class="space-y-2"
      >
        <h3 class="flex items-center gap-2 text-sm font-medium">
          <component
            :is="group.type ? icons[group.type] : ListChecks"
            class="size-4 text-muted-foreground"
          />
          <span>{{ group.name ?? t("brainstormingDecisions.dashboard.noContent") }}</span>
          <span v-if="group.type" class="text-xs font-normal text-muted-foreground">{{
            t(`brainstormingDecisions.targetTypes.${group.type}`)
          }}</span>
          <span
            class="text-xs font-normal"
            :class="group.toApply ? 'text-amber-700 dark:text-amber-400' : 'text-muted-foreground'"
            >{{
              t("brainstormingDecisions.dashboard.groupSummary", {
                count: group.items.length,
                pending: group.toApply,
              })
            }}</span
          >
        </h3>
        <ul class="space-y-2">
          <li v-for="item in group.items" :key="`${group.key}-${item.decision.id}`">
            <DecisionDashboardCard
              :item="item"
              :href="href(item)"
              :group-key="group.key"
              :pending="pending"
              :declared="declared"
              @declare="(...args) => emit('declare', ...args)"
            />
          </li>
        </ul>
      </section>
    </template>
    <ul v-else class="space-y-2">
      <li v-for="item in listed.live" :key="item.decision.id" :data-decision-row="item.decision.id">
        <DecisionDashboardCard
          :item="item"
          :href="href(item)"
          :pending="pending"
          :declared="declared"
          @declare="(...args) => emit('declare', ...args)"
        />
      </li>
      <li v-if="listed.retired.length" class="pt-1.5">
        <button
          id="decisions-dashboard-retired"
          type="button"
          class="flex w-full items-center gap-2.5 text-[11px] text-muted-foreground hover:text-foreground"
          :aria-expanded="showRetired"
          @click="showRetired = !showRetired"
        >
          <span class="h-px flex-1 bg-border" />{{
            t("brainstormingDecisions.retired", { count: listed.retired.length })
          }}<ChevronUp v-if="showRetired" class="size-3" /><ChevronDown
            v-else
            class="size-3"
          /><span class="h-px flex-1 bg-border" />
        </button>
      </li>
      <template v-if="showRetired">
        <li
          v-for="item in listed.retired"
          :key="item.decision.id"
          :data-decision-row="item.decision.id"
        >
          <DecisionDashboardCard :item="item" :href="href(item)" />
        </li>
      </template>
    </ul>
  </section>
</template>
