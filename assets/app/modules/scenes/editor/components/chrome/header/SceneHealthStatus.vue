<script setup lang="ts">
import { AlertTriangle, ChevronDown, CircleCheck, Info, TriangleAlert } from "lucide-vue-next";
import { computed, ref } from "vue";
import { useI18n } from "vue-i18n";
import ToolbarTooltip from "@components/toolbar/ToolbarTooltip.vue";
import { Popover, PopoverAnchor, PopoverContent, PopoverTrigger } from "@components/ui/popover";
import { useLive } from "@shared/composables/useLive.ts";
import type { SceneHealth, SceneHealthItem, SceneHealthReason } from "@modules/scenes/types/health";

const {
  health = {
    errorItems: [],
    warningItems: [],
    infoItems: [],
  },
} = defineProps<{
  health?: SceneHealth;
}>();

const { t } = useI18n();
const live = useLive();
const open = ref(false);

const errorCount = computed(() => findingCount(health.errorItems));
const warningCount = computed(() => findingCount(health.warningItems));
const infoCount = computed(() => findingCount(health.infoItems));
const hasFindings = computed(
  () => errorCount.value > 0 || warningCount.value > 0 || infoCount.value > 0,
);

function findingCount(items: SceneHealthItem[]): number {
  return items.reduce((count, item) => count + item.reasons.length, 0);
}

function itemsFor(severity: "error" | "warning" | "info"): SceneHealthItem[] {
  if (severity === "error") return health.errorItems;
  if (severity === "warning") return health.warningItems;
  return health.infoItems;
}

function reasonLabel(reason: SceneHealthReason): string {
  return t(`scenes.health.findings.${reason.code}`, reason.details || {});
}

function navigable(item: SceneHealthItem): boolean {
  return (
    ["pin", "zone", "connection", "annotation"].includes(item.entityType) && item.entityId != null
  );
}

function navigateToFinding(item: SceneHealthItem): void {
  if (!navigable(item)) return;

  live.pushEvent("focus_search_result", {
    type: item.entityType,
    id: item.entityId,
  });
  open.value = false;
}
</script>

<template>
  <div class="shrink-0">
    <Popover v-if="hasFindings" v-model:open="open">
      <PopoverAnchor as-child>
        <ToolbarTooltip :label="$t('scenes.health.review')" side="bottom">
          <PopoverTrigger
            data-testid="scene-health-trigger"
            class="inline-flex h-8 items-center gap-2 rounded-md border border-border bg-background/80 px-2.5 text-xs shadow-sm transition-colors hover:bg-accent"
          >
            <span v-if="errorCount > 0" class="flex items-center gap-1 text-destructive">
              <TriangleAlert class="size-3.5" />
              <span data-testid="scene-health-error-count">{{ errorCount }}</span>
            </span>
            <span v-if="warningCount > 0" class="flex items-center gap-1 text-yellow-500">
              <AlertTriangle class="size-3.5" />
              <span data-testid="scene-health-warning-count">{{ warningCount }}</span>
            </span>
            <span v-if="infoCount > 0" class="flex items-center gap-1 text-blue-500">
              <Info class="size-3.5" />
              <span data-testid="scene-health-info-count">{{ infoCount }}</span>
            </span>
            <ChevronDown class="size-3 text-muted-foreground" />
          </PopoverTrigger>
        </ToolbarTooltip>
      </PopoverAnchor>

      <PopoverContent side="bottom" align="end" :side-offset="6" class="w-90 max-w-[90vw] p-1">
        <div class="max-h-72 overflow-y-auto">
          <section
            v-for="severity in ['error', 'warning', 'info'] as const"
            :key="severity"
            :data-testid="`scene-health-${severity}`"
          >
            <template v-if="itemsFor(severity).length > 0">
              <h3 class="mt-1 px-2 py-1 text-[10px] font-medium uppercase text-muted-foreground">
                {{
                  $t(
                    `scenes.health.${severity === "error" ? "errors" : severity === "warning" ? "warnings" : "info"}`,
                  )
                }}
              </h3>
              <button
                v-for="(item, index) in itemsFor(severity)"
                :key="`${severity}-${item.entityType}-${item.entityId ?? index}`"
                type="button"
                :data-health-severity="severity"
                :data-health-entity-type="item.entityType"
                :data-health-entity-id="item.entityId"
                :disabled="!navigable(item)"
                class="w-full rounded-md px-2 py-1.5 text-left text-xs transition-colors enabled:hover:bg-accent disabled:cursor-default"
                @click="navigateToFinding(item)"
              >
                <span class="block truncate font-medium">{{ item.label }}</span>
                <span
                  v-for="reason in item.reasons"
                  :key="`${reason.code}-${JSON.stringify(reason.details)}`"
                  class="mt-0.5 block text-[11px] leading-4 text-muted-foreground"
                >
                  {{ reasonLabel(reason) }}
                </span>
              </button>
            </template>
          </section>
        </div>
      </PopoverContent>
    </Popover>

    <ToolbarTooltip v-else :label="$t('scenes.health.looks_great')" side="bottom">
      <div
        data-testid="scene-health-clean"
        class="inline-flex size-8 items-center justify-center rounded-md border border-border bg-background/60 text-green-500/70"
      >
        <CircleCheck class="size-4" />
      </div>
    </ToolbarTooltip>
  </div>
</template>
