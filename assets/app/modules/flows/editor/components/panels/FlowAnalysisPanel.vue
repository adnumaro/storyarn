<script setup lang="ts">
import { RotateCw, ScanSearch, X } from "lucide-vue-next";
import { computed, ref } from "vue";
import { useI18n } from "vue-i18n";
import { Button } from "@components/ui/button";
import Sidebar from "../../../../../shell/Sidebar.vue";
import { useLive } from "../../../../../shared/composables/useLive";
import FlowAnalysisFindingCard from "./FlowAnalysisFindingCard.vue";
import type { AnalysisFinding } from "./flowAnalysisTypes";

const {
  open = false,
  canEdit = false,
  stale = false,
  computedAt = null,
  reasonCodes = [],
  maxNoteLength = 2000,
  active = [],
  dismissed = [],
} = defineProps<{
  open?: boolean;
  canEdit?: boolean;
  stale?: boolean;
  computedAt?: string | null;
  reasonCodes?: string[];
  maxNoteLength?: number;
  active?: AnalysisFinding[];
  dismissed?: AnalysisFinding[];
}>();

const { t } = useI18n();
const live = useLive();

type Tab = "active" | "dismissed";
type CategoryFilter = "all" | "structure" | "reference_integrity";
type SeverityFilter = "all" | "error" | "warning";

const tab = ref<Tab>("active");
const categoryFilter = ref<CategoryFilter>("all");
const severityFilter = ref<SeverityFilter>("all");

const categoryOptions: CategoryFilter[] = ["all", "structure", "reference_integrity"];
const severityOptions: SeverityFilter[] = ["all", "error", "warning"];

function applyFilters(findings: AnalysisFinding[]): AnalysisFinding[] {
  return findings.filter(
    (finding) =>
      (categoryFilter.value === "all" || finding.category === categoryFilter.value) &&
      (severityFilter.value === "all" || finding.severity === severityFilter.value),
  );
}

const filteredActive = computed(() => applyFilters(active));
const filteredDismissed = computed(() => applyFilters(dismissed));
const shownFindings = computed(() =>
  tab.value === "active" ? filteredActive.value : filteredDismissed.value,
);

function close(): void {
  live.pushEvent("close_analysis_panel", {});
}

function rerun(): void {
  live.pushEvent("rerun_analysis", {});
}

function onDismiss(findingId: string, reasonCode: string, note: string): void {
  live.pushEvent("dismiss_finding", { finding_id: findingId, reason_code: reasonCode, note });
}

function onRestore(dismissalId: number): void {
  live.pushEvent("restore_finding_dismissal", { dismissal_id: dismissalId });
}

function onNavigate(type: string, id: number): void {
  live.pushEvent("analysis_navigate_evidence", { type, id });
}
</script>

<template>
  <Sidebar side="right" :open="open" @close="close">
    <template #header>
      <div class="flex items-center justify-between py-2.5">
        <div class="flex items-center gap-2 text-sm font-medium">
          <ScanSearch class="size-4" />
          {{ t("flows.analysis.title") }}
        </div>
        <div class="flex items-center gap-1">
          <Button
            variant="ghost"
            size="sm"
            class="h-7 gap-1.5 px-2 text-xs"
            data-testid="analysis-rerun"
            @click="rerun"
          >
            <RotateCw class="size-3.5" />
            {{ t("flows.analysis.rerun") }}
          </Button>
          <button
            type="button"
            class="p-1 rounded hover:bg-muted transition-colors text-muted-foreground hover:text-foreground"
            @click="close"
          >
            <X class="size-4" />
          </button>
        </div>
      </div>
    </template>

    <div class="flex h-full flex-col gap-3 py-3" data-testid="analysis-panel">
      <div
        v-if="stale"
        class="flex items-center justify-between gap-2 rounded-md border border-amber-500/40 bg-amber-500/10 px-2.5 py-2 text-xs"
        data-testid="analysis-stale-banner"
      >
        <span>{{ t("flows.analysis.stale_banner") }}</span>
        <Button size="sm" variant="outline" class="h-6 shrink-0 gap-1 px-2 text-xs" @click="rerun">
          <RotateCw class="size-3" />
          {{ t("flows.analysis.rerun") }}
        </Button>
      </div>

      <div class="flex rounded-md border border-border p-0.5 text-xs" role="tablist">
        <button
          v-for="option in ['active', 'dismissed'] as Tab[]"
          :key="option"
          type="button"
          role="tab"
          :aria-selected="tab === option"
          class="flex-1 rounded px-2 py-1"
          :class="
            tab === option ? 'bg-muted font-medium' : 'text-muted-foreground hover:text-foreground'
          "
          :data-testid="`analysis-tab-${option}`"
          @click="tab = option"
        >
          {{ t(`flows.analysis.tabs.${option}`) }}
          ({{ option === "active" ? filteredActive.length : filteredDismissed.length }})
        </button>
      </div>

      <div class="flex flex-wrap items-center gap-2 text-xs">
        <div class="flex rounded-md border border-border p-0.5">
          <button
            v-for="option in categoryOptions"
            :key="option"
            type="button"
            class="rounded px-1.5 py-0.5"
            :class="
              categoryFilter === option
                ? 'bg-muted font-medium'
                : 'text-muted-foreground hover:text-foreground'
            "
            @click="categoryFilter = option"
          >
            {{ t(`flows.analysis.filters.${option}`) }}
          </button>
        </div>
        <div class="flex rounded-md border border-border p-0.5">
          <button
            v-for="option in severityOptions"
            :key="option"
            type="button"
            class="rounded px-1.5 py-0.5"
            :class="
              severityFilter === option
                ? 'bg-muted font-medium'
                : 'text-muted-foreground hover:text-foreground'
            "
            @click="severityFilter = option"
          >
            {{ t(`flows.analysis.filters.${option}`) }}
          </button>
        </div>
      </div>

      <p v-if="computedAt" class="text-xs text-muted-foreground">
        {{ t("flows.analysis.computed_at", { time: new Date(computedAt).toLocaleTimeString() }) }}
      </p>

      <div class="min-h-0 flex-1 overflow-y-auto">
        <p
          v-if="shownFindings.length === 0"
          class="px-1 py-6 text-center text-xs text-muted-foreground"
          data-testid="analysis-empty"
        >
          {{
            tab === "active"
              ? t("flows.analysis.empty_active")
              : t("flows.analysis.empty_dismissed")
          }}
        </p>
        <ul v-else class="space-y-1.5">
          <FlowAnalysisFindingCard
            v-for="finding in shownFindings"
            :key="finding.findingId"
            :finding="finding"
            :can-edit="canEdit"
            :reason-codes="reasonCodes"
            :max-note-length="maxNoteLength"
            :dismissed="tab === 'dismissed'"
            @dismiss="onDismiss"
            @restore="onRestore"
            @navigate="onNavigate"
          />
        </ul>
      </div>
    </div>
  </Sidebar>
</template>
