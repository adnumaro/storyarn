<script setup lang="ts">
import {
  ChevronDown,
  ChevronRight,
  CircleAlert,
  Crosshair,
  TriangleAlert,
  Undo2,
} from "lucide-vue-next";
import { computed, ref } from "vue";
import { useI18n } from "vue-i18n";
import { Button } from "@components/ui/button";
import FlowAnalysisDismissForm from "./FlowAnalysisDismissForm.vue";
import type { AnalysisFinding } from "./flowAnalysisTypes";

const {
  finding,
  canEdit = false,
  reasonCodes = [],
  maxNoteLength = 2000,
  dismissed = false,
  actionError = null,
} = defineProps<{
  finding: AnalysisFinding;
  canEdit?: boolean;
  reasonCodes?: string[];
  maxNoteLength?: number;
  dismissed?: boolean;
  actionError?: string | null;
}>();

const emit = defineEmits<{
  dismiss: [findingId: string, reasonCode: string, note: string];
  restore: [dismissalId: number];
  navigate: [type: string, id: number];
}>();

const { t, te } = useI18n();

const expanded = ref(false);
const dismissFormOpen = ref(false);

const isError = computed(() => finding.severity === "error");

const ruleLabel = computed(() => t(`flows.analysis.rules.${finding.ruleId}`));
const limitations = computed(() =>
  t(finding.limitationsKey ?? `flows.analysis.limitations.${finding.ruleId}`),
);

const previouslyDismissed = computed(() => {
  const prev = finding.previousDismissal;
  if (!prev) return null;
  return t("flows.analysis.previously_dismissed", {
    reason: t(`flows.analysis.reasons.${prev.reasonCode}`),
    user: prev.dismissedBy ?? "—",
  });
});

const targetLabel = computed(() => {
  if (finding.targetType === "flow") return t("flows.analysis.target_flow");
  const typeKey = `flows.node_types.${finding.nodeType}`;
  const typeLabel = finding.nodeType && te(typeKey) ? t(typeKey) : (finding.nodeType ?? "");
  return `${typeLabel} #${finding.targetId}`;
});

const detailChips = computed(() => {
  const chips: string[] = [];
  if (finding.pins.length > 0) {
    chips.push(t("flows.analysis.pins_chip", { pins: finding.pins.join(", ") }));
  }
  if (finding.count != null) chips.push(t("flows.analysis.count_chip", { count: finding.count }));
  if (finding.hubId) chips.push(t("flows.analysis.hub_chip", { hub: finding.hubId }));
  return chips;
});

const dismissedMeta = computed(() =>
  t("flows.analysis.dismissed_meta", {
    reason: t(`flows.analysis.reasons.${finding.reasonCode}`),
    user: finding.dismissedBy ?? "—",
    time: finding.dismissedAt ? new Date(finding.dismissedAt).toLocaleString() : "—",
  }),
);

function evidenceLabel(type: string, id: number): string {
  return `${t(`flows.analysis.evidence_types.${type}`)} #${id}`;
}

function navigable(type: string): boolean {
  return type === "flow_node" || type === "flow_connection";
}

// The form stays open on submit: on success this finding moves to the
// dismissed list and the card unmounts; on a failed push the panel shows
// the action error and the typed reason/note survive for a retry.
function onDismissSubmit(reasonCode: string, note: string): void {
  emit("dismiss", finding.findingId, reasonCode, note);
}
</script>

<template>
  <li class="rounded-md border border-border bg-background" :data-finding-id="finding.findingId">
    <button
      type="button"
      class="flex w-full items-center gap-2 px-2.5 py-2 text-left text-sm hover:bg-muted/50"
      :data-testid="dismissed ? 'analysis-dismissed-finding' : 'analysis-finding'"
      :aria-expanded="expanded"
      @click="expanded = !expanded"
    >
      <component
        :is="isError ? CircleAlert : TriangleAlert"
        class="size-4 shrink-0"
        :class="isError ? 'text-destructive' : 'text-amber-500'"
      />
      <span
        class="min-w-0 flex-1 truncate"
        :class="dismissed && 'text-muted-foreground line-through'"
      >
        {{ ruleLabel }}
      </span>
      <span class="shrink-0 text-xs text-muted-foreground">{{ targetLabel }}</span>
      <component
        :is="expanded ? ChevronDown : ChevronRight"
        class="size-3.5 shrink-0 text-muted-foreground"
      />
    </button>

    <div v-if="expanded" class="space-y-3 border-t border-border px-2.5 py-2.5 text-sm">
      <div v-if="detailChips.length > 0" class="flex flex-wrap gap-1.5">
        <span
          v-for="chip in detailChips"
          :key="chip"
          class="rounded bg-muted px-1.5 py-0.5 text-xs text-muted-foreground"
        >
          {{ chip }}
        </span>
      </div>

      <p class="text-xs text-muted-foreground">{{ limitations }}</p>

      <p
        v-if="previouslyDismissed"
        class="rounded bg-amber-500/10 px-2 py-1 text-xs text-amber-600 dark:text-amber-400"
        data-testid="analysis-previously-dismissed"
      >
        {{ previouslyDismissed }}
      </p>

      <div v-if="finding.evidence.length > 0">
        <p class="mb-1 text-xs font-medium text-muted-foreground">
          {{ t("flows.analysis.evidence_title") }}
        </p>
        <ul class="space-y-1">
          <li
            v-for="item in finding.evidence"
            :key="`${item.type}-${item.id}`"
            class="flex items-center justify-between gap-2 text-xs"
          >
            <span>{{ evidenceLabel(item.type, item.id) }}</span>
            <Button
              v-if="navigable(item.type)"
              variant="ghost"
              size="sm"
              class="h-6 gap-1 px-1.5 text-xs text-primary"
              data-testid="analysis-evidence-navigate"
              @click="emit('navigate', item.type, item.id)"
            >
              <Crosshair class="size-3" />
              {{ t("flows.analysis.evidence_go_to") }}
            </Button>
          </li>
        </ul>
      </div>

      <div v-if="dismissed" class="space-y-2">
        <p class="text-xs text-muted-foreground">{{ dismissedMeta }}</p>
        <p v-if="finding.note" class="rounded bg-muted px-2 py-1 text-xs">{{ finding.note }}</p>
        <Button
          v-if="canEdit && finding.dismissalId != null"
          variant="outline"
          size="sm"
          class="gap-1.5 text-xs"
          data-testid="analysis-restore"
          @click="emit('restore', finding.dismissalId)"
        >
          <Undo2 class="size-3.5" />
          {{ t("flows.analysis.restore") }}
        </Button>
      </div>

      <div v-else-if="canEdit">
        <Button
          v-if="!dismissFormOpen"
          variant="outline"
          size="sm"
          class="text-xs"
          data-testid="analysis-dismiss"
          @click="dismissFormOpen = true"
        >
          {{ t("flows.analysis.dismiss") }}
        </Button>

        <FlowAnalysisDismissForm
          v-else
          :reason-codes="reasonCodes"
          :max-note-length="maxNoteLength"
          :error="actionError"
          @submit="onDismissSubmit"
          @cancel="dismissFormOpen = false"
        />
      </div>
    </div>
  </li>
</template>
