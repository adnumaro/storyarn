<script setup lang="ts">
import { RotateCw, ScanSearch, Sparkles, X } from "lucide-vue-next";
import { computed, ref, watch, watchEffect } from "vue";
import { useI18n } from "vue-i18n";
import { Button } from "@components/ui/button";
import { FLOW_ANALYSIS_DESTINATION } from "@shared/command-palette/aiDestinations";
import type { PaletteCommand } from "@shared/command-palette/registry";
import { registerPaletteCommands } from "@shared/command-palette/registry";
import Sidebar from "../../../../../shell/Sidebar.vue";
import { useLive } from "../../../../../shared/composables/useLive";
import FlowAnalysisFindingCard from "./FlowAnalysisFindingCard.vue";
import type { AnalysisFinding, FlowExplanationState } from "./flowAnalysisTypes";

const {
  open = false,
  canEdit = false,
  stale = false,
  computedAt = null,
  reasonCodes = [],
  maxNoteLength = 2000,
  active = [],
  dismissed = [],
  explanation = null,
} = defineProps<{
  open?: boolean;
  canEdit?: boolean;
  stale?: boolean;
  computedAt?: string | null;
  reasonCodes?: string[];
  maxNoteLength?: number;
  active?: AnalysisFinding[];
  dismissed?: AnalysisFinding[];
  explanation?: FlowExplanationState | null;
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
const filtersActive = computed(
  () => categoryFilter.value !== "all" || severityFilter.value !== "all",
);

function clearFilters(): void {
  categoryFilter.value = "all";
  severityFilter.value = "all";
}
const filteredDismissed = computed(() => applyFilters(dismissed));
const shownFindings = computed(() =>
  tab.value === "active" ? filteredActive.value : filteredDismissed.value,
);

// `pushEvent` never throws; a dropped push invokes the onError callback
// and the panel surfaces it inline instead of failing silently.
const actionError = ref<string | null>(null);
const pending = ref(false);

// A fresh snapshot always changes computedAt; clear the pending state then.
watch(
  () => computedAt,
  () => {
    pending.value = false;
  },
);

function pushAction(event: string, payload: Record<string, unknown>): void {
  actionError.value = null;
  live.pushEvent(event, payload, undefined, () => {
    pending.value = false;
    actionError.value = t("flows.analysis.action_failed");
  });
}

function close(): void {
  pushAction("close_analysis_panel", {});
}

function rerun(): void {
  pending.value = true;
  pushAction("rerun_analysis", {});
}

function onDismiss(findingId: string, reasonCode: string, note: string): void {
  pushAction("dismiss_finding", { finding_id: findingId, reason_code: reasonCode, note });
}

function onRestore(dismissalId: number): void {
  pushAction("restore_finding_dismissal", { dismissal_id: dismissalId });
}

function onNavigate(type: string, id: number): void {
  pushAction("analysis_navigate_evidence", { type, id });
}

function onExplain(findingId: string): void {
  pushAction("open_explanation", { finding_id: findingId });
}

function onExecuteExplanation(routeRef: string): void {
  pushAction("execute_explanation", { route_ref: routeRef });
}

function onRerunExplanation(): void {
  pushAction("rerun_explanation", {});
}

function onResumeExplanation(): void {
  pushAction("resume_explanation", {});
}

function onCloseExplanation(): void {
  pushAction("close_explanation", {});
}

// ── Palette v2 AI command ────────────────────────────────────────────────
// The command is a `launch`: it starts the panel preflight and opens the
// panel destination (owned by the panel host). Route and cost resolution stay
// in the panel, never in the palette.
/** The expanded card IS the selection; with none, the command has no referent. */
const selectedFindingId = ref<string | null>(null);

function onToggleFinding(findingId: string, expanded: boolean): void {
  if (expanded) {
    selectedFindingId.value = findingId;
  } else if (selectedFindingId.value === findingId) {
    selectedFindingId.value = null;
  }
}

/**
 * The selection must be a CURRENT finding, not merely an expanded card.
 *
 * `onToggleFinding` also fires from the dismissed tab, and a stale snapshot
 * means every occurrence id is provisional. The server refuses both, so this is
 * about not offering a command that is guaranteed to fail.
 */
const explainableFindingId = computed(() => {
  const findingId = selectedFindingId.value;
  if (findingId == null || stale) return null;
  return active.some((finding) => finding.findingId === findingId) ? findingId : null;
});

function explainCommand(findingId: string): PaletteCommand {
  return {
    kind: "ai",
    mode: "launch",
    // Cost is disclosed by the panel preflight, never by the palette.
    cost: { kind: "deferred_to_preflight" },
    id: "flows.explain_finding",
    labelKey: "flows.explanation.explain_action",
    groupKey: "palette.groups.actions",
    icon: Sparkles,
    taskId: "flows.explain_finding",
    context: { surface: "flows", selection: { type: "flow_finding", id: findingId } },
    availability: { state: "ready" },
    destination: FLOW_ANALYSIS_DESTINATION,
    launch: async () => {
      pushAction("open_explanation", { finding_id: findingId });
      return { status: "launched" };
    },
  };
}

watchEffect((onCleanup) => {
  const findingId = explainableFindingId.value;
  const eligible = explanation?.available === true && findingId != null;

  const unregister = registerPaletteCommands(
    "flows",
    eligible && findingId ? [explainCommand(findingId)] : [],
  );

  onCleanup(unregister);
});
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
            :disabled="pending"
            @click="rerun"
          >
            <RotateCw class="size-3.5" :class="pending && 'animate-spin'" />
            {{ t("flows.analysis.rerun") }}
          </Button>
          <button
            type="button"
            class="p-1 rounded hover:bg-muted transition-colors text-muted-foreground hover:text-foreground"
            :aria-label="t('flows.analysis.close')"
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
        <Button
          size="sm"
          variant="outline"
          class="h-6 shrink-0 gap-1 px-2 text-xs"
          :disabled="pending"
          @click="rerun"
        >
          <RotateCw class="size-3" :class="pending && 'animate-spin'" />
          {{ t("flows.analysis.rerun") }}
        </Button>
      </div>

      <div class="flex rounded-md border border-border p-0.5 text-xs" role="tablist">
        <button
          v-for="option in ['active', 'dismissed'] as Tab[]"
          :id="`analysis-tab-button-${option}`"
          :key="option"
          type="button"
          role="tab"
          :aria-selected="tab === option"
          aria-controls="analysis-findings-list"
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
        <div class="flex rounded-md border border-border p-0.5" role="group">
          <button
            v-for="option in categoryOptions"
            :key="option"
            type="button"
            :aria-pressed="categoryFilter === option"
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
        <div class="flex rounded-md border border-border p-0.5" role="group">
          <button
            v-for="option in severityOptions"
            :key="option"
            type="button"
            :aria-pressed="severityFilter === option"
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

      <p
        v-if="actionError"
        role="alert"
        class="text-xs text-destructive"
        data-testid="analysis-action-error"
      >
        {{ actionError }}
      </p>

      <div
        id="analysis-findings-list"
        role="tabpanel"
        :aria-labelledby="`analysis-tab-button-${tab}`"
        class="min-h-0 flex-1 overflow-y-auto"
      >
        <div
          v-if="shownFindings.length === 0"
          class="px-1 py-6 text-center text-xs text-muted-foreground"
          data-testid="analysis-empty"
        >
          <template
            v-if="filtersActive && (tab === 'active' ? active.length : dismissed.length) > 0"
          >
            <p>{{ t("flows.analysis.empty_filtered") }}</p>
            <Button variant="outline" size="sm" class="mt-2 text-xs" @click="clearFilters">
              {{ t("flows.analysis.clear_filters") }}
            </Button>
          </template>
          <p v-else>
            {{
              tab === "active"
                ? t("flows.analysis.empty_active")
                : t("flows.analysis.empty_dismissed")
            }}
          </p>
        </div>
        <!-- Keyed by findingKey, not findingId: the id rotates with the
             evidence fingerprint, so keying on it would collapse every
             expanded card (and drop its AI surface) on each rerun. -->
        <ul v-else class="space-y-1.5">
          <FlowAnalysisFindingCard
            v-for="finding in shownFindings"
            :key="finding.findingKey"
            :finding="finding"
            :can-edit="canEdit"
            :reason-codes="reasonCodes"
            :max-note-length="maxNoteLength"
            :dismissed="tab === 'dismissed'"
            :action-error="actionError"
            :explanation="explanation"
            @dismiss="onDismiss"
            @restore="onRestore"
            @navigate="onNavigate"
            @toggle="onToggleFinding"
            @explain="onExplain"
            @execute="onExecuteExplanation"
            @rerun-explanation="onRerunExplanation"
            @resume-explanation="onResumeExplanation"
            @close-explanation="onCloseExplanation"
          />
        </ul>
      </div>
    </div>
  </Sidebar>
</template>
