<script setup lang="ts">
import { Loader2, RotateCw, Sparkles, TriangleAlert } from "lucide-vue-next";
import { computed } from "vue";
import { useI18n } from "vue-i18n";
import ContextDisclosure from "@components/ai/ContextDisclosure.vue";
import { Button } from "@components/ui/button";
import type { ExplanationStatus, FlowExplanationState } from "./flowAnalysisTypes";

const { findingId, findingKey, explanation } = defineProps<{
  findingId: string;
  /** Stable anchor: a rerun rotates findingId, and the surface must survive it. */
  findingKey: string;
  explanation: FlowExplanationState;
}>();

const emit = defineEmits<{
  explain: [findingId: string];
  execute: [routeRef: string];
  rerun: [];
  resume: [];
  close: [];
}>();

const { t, te } = useI18n();

/**
 * The surface belongs to ONE finding at a time. It matches on the stable key,
 * not the occurrence id: rerunning the analysis rotates every findingId, and
 * an explanation that vanished on rerun would be worse than one marked stale.
 */
const mine = computed(() => explanation.findingKey === findingKey);
const status = computed<ExplanationStatus>(() => (mine.value ? explanation.status : "idle"));

const retentionMinutes = computed(() => Math.round((explanation.retentionSeconds ?? 0) / 60));

const errorMessage = computed(() => {
  const key = `flows.explanation.errors.${explanation.error}`;
  return te(key) ? t(key) : t("flows.explanation.errors.unknown");
});

function laneLabel(lane: string): string {
  const key = `flows.explanation.lanes.${lane}`;
  return te(key) ? t(key) : lane;
}

function blockedLaneLabel(lane: string, reason: string): string {
  const key = `flows.explanation.errors.${reason}`;
  return t("flows.explanation.lane_blocked", {
    lane: laneLabel(lane),
    reason: te(key) ? t(key) : t("flows.explanation.errors.unknown"),
  });
}
</script>

<template>
  <div v-if="explanation.available" class="border-t border-border pt-2.5">
    <!-- Entry point -->
    <Button
      v-if="status === 'idle'"
      variant="outline"
      size="sm"
      class="h-7 gap-1.5 text-xs"
      data-testid="explanation-open"
      @click="emit('explain', findingId)"
    >
      <Sparkles class="size-3.5" />
      {{ t("flows.explanation.explain_action") }}
    </Button>

    <!-- Preflight: what is sent, who pays, what it costs — before anything runs -->
    <div v-else-if="status === 'preflight'" class="space-y-2" data-testid="explanation-preflight">
      <p class="text-xs font-medium">{{ t("flows.explanation.preflight_title") }}</p>

      <ContextDisclosure v-if="explanation.disclosure" :disclosure="explanation.disclosure" />

      <p
        v-if="explanation.retentionSeconds"
        class="text-xs text-muted-foreground"
        data-testid="explanation-retention"
      >
        {{ t("flows.explanation.retention", { minutes: retentionMinutes }) }}
      </p>

      <ul class="space-y-1.5">
        <li
          v-for="route in explanation.routes"
          :key="route.routeRef"
          class="flex items-center justify-between gap-2 rounded-md border border-border px-2 py-1.5"
        >
          <span class="min-w-0 text-xs">
            <span class="font-medium">{{ laneLabel(route.lane) }}</span>
            <span class="text-muted-foreground">
              · {{ route.provider }}/{{ route.model }} ·
              {{ t("flows.explanation.payer", { payer: route.payer }) }} ·
              {{ t("flows.explanation.price_units", { count: route.priceUnits }) }}
            </span>
          </span>
          <Button
            size="sm"
            class="h-6 shrink-0 px-2 text-xs"
            data-testid="explanation-execute"
            @click="emit('execute', route.routeRef)"
          >
            {{ t("flows.explanation.run_action") }}
          </Button>
        </li>

        <li
          v-for="blocked in explanation.blockedLanes"
          :key="blocked.lane"
          class="rounded-md border border-dashed border-border px-2 py-1.5 text-xs text-muted-foreground"
          data-testid="explanation-blocked-lane"
        >
          {{ blockedLaneLabel(blocked.lane, blocked.reason) }}
        </li>
      </ul>

      <Button variant="ghost" size="sm" class="h-6 px-2 text-xs" @click="emit('close')">
        {{ t("flows.explanation.cancel_action") }}
      </Button>
    </div>

    <!-- Waiting for a slot, then generating -->
    <p
      v-else-if="status === 'queued' || status === 'running'"
      class="flex items-center gap-2 text-xs text-muted-foreground"
      role="status"
      :data-testid="status === 'queued' ? 'explanation-queued' : 'explanation-running'"
    >
      <Loader2 class="size-3.5 animate-spin" />
      {{ status === "queued" ? t("flows.explanation.queued") : t("flows.explanation.running") }}
    </p>

    <!-- Stopped watching, NOT failed: the run is alive and already paid for -->
    <div v-else-if="status === 'detached'" class="space-y-2" data-testid="explanation-detached">
      <p class="text-xs text-muted-foreground">{{ t("flows.explanation.detached") }}</p>
      <div class="flex gap-2">
        <Button
          variant="outline"
          size="sm"
          class="h-6 gap-1 px-2 text-xs"
          data-testid="explanation-resume"
          @click="emit('resume')"
        >
          <Loader2 class="size-3" />
          {{ t("flows.explanation.resume_action") }}
        </Button>
        <Button variant="ghost" size="sm" class="h-6 px-2 text-xs" @click="emit('close')">
          {{ t("flows.explanation.close_action") }}
        </Button>
      </div>
    </div>

    <!-- Result: visually separated from every deterministic fact above -->
    <div v-else-if="status === 'succeeded' && explanation.result" class="space-y-2">
      <p
        v-if="explanation.stale"
        class="rounded bg-amber-500/10 px-2 py-1 text-xs text-amber-600 dark:text-amber-400"
        data-testid="explanation-stale"
      >
        {{ t("flows.explanation.stale") }}
      </p>

      <section
        class="space-y-2 rounded-md border border-primary/30 bg-primary/5 px-2.5 py-2"
        data-testid="explanation-result"
        :aria-label="t('flows.explanation.generated_label')"
      >
        <p class="flex items-center gap-1.5 text-xs font-medium text-primary">
          <Sparkles class="size-3.5" />
          {{ t("flows.explanation.generated_label") }}
        </p>

        <p class="text-sm">{{ explanation.result.summary }}</p>

        <div>
          <p class="text-xs font-medium text-muted-foreground">
            {{ t("flows.explanation.why_title") }}
          </p>
          <p class="text-xs">{{ explanation.result.whyItTriggers }}</p>
        </div>

        <div v-if="explanation.result.implications.length > 0">
          <p class="text-xs font-medium text-muted-foreground">
            {{ t("flows.explanation.implications_title") }}
          </p>
          <ul class="list-disc space-y-0.5 pl-4 text-xs">
            <li v-for="item in explanation.result.implications" :key="item">{{ item }}</li>
          </ul>
        </div>

        <div v-if="explanation.result.suggestedChecks.length > 0">
          <p class="text-xs font-medium text-muted-foreground">
            {{ t("flows.explanation.checks_title") }}
          </p>
          <ul class="list-disc space-y-0.5 pl-4 text-xs">
            <li v-for="item in explanation.result.suggestedChecks" :key="item">{{ item }}</li>
          </ul>
        </div>

        <p class="text-xs text-muted-foreground">{{ t("flows.explanation.generated_note") }}</p>
      </section>

      <div class="flex gap-2">
        <Button
          variant="outline"
          size="sm"
          class="h-6 gap-1 px-2 text-xs"
          data-testid="explanation-rerun"
          @click="emit('rerun')"
        >
          <RotateCw class="size-3" />
          {{ t("flows.explanation.rerun_action") }}
        </Button>
        <Button variant="ghost" size="sm" class="h-6 px-2 text-xs" @click="emit('close')">
          {{ t("flows.explanation.close_action") }}
        </Button>
      </div>
    </div>

    <!-- Blocked, failed or expired -->
    <div v-else class="space-y-2" data-testid="explanation-error">
      <p class="flex items-start gap-1.5 text-xs text-muted-foreground" role="alert">
        <TriangleAlert class="mt-0.5 size-3.5 shrink-0 text-amber-500" />
        <span>{{ status === "expired" ? t("flows.explanation.expired") : errorMessage }}</span>
      </p>
      <div class="flex gap-2">
        <Button
          variant="outline"
          size="sm"
          class="h-6 gap-1 px-2 text-xs"
          data-testid="explanation-rerun"
          @click="emit('rerun')"
        >
          <RotateCw class="size-3" />
          {{ t("flows.explanation.retry_action") }}
        </Button>
        <Button variant="ghost" size="sm" class="h-6 px-2 text-xs" @click="emit('close')">
          {{ t("flows.explanation.close_action") }}
        </Button>
      </div>
    </div>
  </div>
</template>
