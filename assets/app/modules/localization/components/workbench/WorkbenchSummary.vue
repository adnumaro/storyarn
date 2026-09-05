<script setup lang="ts">
import { computed } from "vue";
import { useI18n } from "vue-i18n";
import { percentFinal, type Tone } from "../../domain/status";
import type { WorkbenchFilters, WorkbenchProgress } from "../../domain/types";
import CountChip from "../progress/CountChip.vue";
import SegmentedProgress from "../progress/SegmentedProgress.vue";

/**
 * Where the language stands, and the three sets that need work as toggles
 * over the list below.
 */
const { progress, filters } = defineProps<{
  progress: WorkbenchProgress;
  filters: WorkbenchFilters;
}>();

const emit = defineEmits<{ toggle: [kind: "pending" | "review" | "stale"] }>();

const { t } = useI18n();

const percent = computed(() => percentFinal(progress.final, progress.total));

const counts = computed(() => ({
  pending: progress.pending,
  draft: progress.draft,
  inProgress: progress.in_progress,
  review: progress.review,
  final: progress.final,
}));

interface Tile {
  kind: "pending" | "review" | "stale";
  tone: Tone;
  label: string;
  count: number;
  active: boolean;
}

const tiles = computed<Tile[]>(() => [
  {
    kind: "pending",
    tone: "pending",
    label: t("localization.status.pending"),
    count: progress.pending,
    active: filters.status === "pending" && !filters.stale,
  },
  {
    kind: "review",
    tone: "review",
    label: t("localization.status.review"),
    count: progress.review,
    active: filters.status === "review" && !filters.stale,
  },
  {
    kind: "stale",
    tone: "outdated",
    label: t("localization.flags.outdated"),
    count: progress.stale,
    active: filters.stale,
  },
]);
</script>

<template>
  <div
    class="flex flex-col gap-3 rounded-lg border border-border bg-card px-4 py-3 sm:flex-row sm:items-center sm:gap-5"
  >
    <div class="flex shrink-0 items-center gap-3">
      <span class="text-xl font-semibold tracking-tight tabular-nums">{{ percent }}%</span>
      <span class="text-xs leading-tight text-muted-foreground">
        {{
          $t("localization.workbench.final_of_total", {
            final: progress.final,
            total: progress.total,
          })
        }}
      </span>
    </div>
    <SegmentedProgress :counts="counts" :total="progress.total" class="min-w-0 flex-1" />
    <div class="flex shrink-0 flex-wrap gap-1.5">
      <CountChip
        v-for="tile in tiles"
        :key="tile.kind"
        :tone="tile.tone"
        :label="tile.label"
        :count="tile.count"
        :active="tile.active"
        @click="emit('toggle', tile.kind)"
      />
    </div>
  </div>
</template>
