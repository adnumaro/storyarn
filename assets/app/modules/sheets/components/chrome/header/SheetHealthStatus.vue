<script setup lang="ts">
import { AlertTriangle, ChevronDown, CircleCheck, Info, TriangleAlert } from "lucide-vue-next";
import { computed, ref } from "vue";
import { useI18n } from "vue-i18n";
import ToolbarTooltip from "@components/toolbar/ToolbarTooltip.vue";
import { Popover, PopoverAnchor, PopoverContent, PopoverTrigger } from "@components/ui/popover";
import type { SheetHealth, SheetHealthItem, SheetHealthReason } from "@modules/sheets/types";

const {
  health = {
    errorItems: [],
    warningItems: [],
    infoItems: [],
  },
} = defineProps<{
  health?: SheetHealth;
}>();

const { t } = useI18n();
const open = ref(false);

const errorCount = computed(() => findingCount(health.errorItems));
const warningCount = computed(() => findingCount(health.warningItems));
const infoCount = computed(() => findingCount(health.infoItems));
const hasFindings = computed(
  () => errorCount.value > 0 || warningCount.value > 0 || infoCount.value > 0,
);

function findingCount(items: SheetHealthItem[]): number {
  return items.reduce((count, item) => count + item.reasons.length, 0);
}

function reasonLabel(reason: SheetHealthReason): string {
  return t(`sheets.health.findings.${reason.code}`, reason.details || {});
}

function selectorValue(value: number | string): string {
  return String(value).replaceAll('"', '\\"');
}

function findTarget(item: SheetHealthItem): HTMLElement | null {
  if (item.rowId != null && item.columnId != null) {
    const row = selectorValue(item.rowId);
    const column = selectorValue(item.columnId);
    const cell = document.querySelector<HTMLElement>(
      `[data-sheet-row-id="${row}"] [data-sheet-column-id="${column}"]`,
    );
    if (cell) return cell;
  }

  if (item.rowId != null) {
    const row = selectorValue(item.rowId);
    const rowElement = document.querySelector<HTMLElement>(`[data-sheet-row-id="${row}"]`);
    if (rowElement) return rowElement;
  }

  if (item.blockId == null) return null;
  return document.getElementById(`sheet-block-${item.blockId}`);
}

function navigateToFinding(item: SheetHealthItem): void {
  const target = findTarget(item);
  if (!target) return;

  target.scrollIntoView({ behavior: "smooth", block: "center" });
  target.classList.add("ring-2", "ring-primary", "ring-offset-2", "ring-offset-background");
  window.setTimeout(() => {
    target.classList.remove("ring-2", "ring-primary", "ring-offset-2", "ring-offset-background");
  }, 1600);
  open.value = false;
}
</script>

<template>
  <div class="shrink-0 pt-2">
    <Popover v-if="hasFindings" v-model:open="open">
      <PopoverAnchor as-child>
        <ToolbarTooltip :label="$t('sheets.health.review')" side="bottom">
          <PopoverTrigger
            data-testid="sheet-health-trigger"
            class="inline-flex h-8 items-center gap-2 rounded-md border border-border bg-background/80 px-2.5 text-xs shadow-sm transition-colors hover:bg-accent"
          >
            <span v-if="errorCount > 0" class="flex items-center gap-1 text-destructive">
              <TriangleAlert class="size-3.5" />
              <span data-testid="sheet-health-error-count">{{ errorCount }}</span>
            </span>
            <span v-if="warningCount > 0" class="flex items-center gap-1 text-yellow-500">
              <AlertTriangle class="size-3.5" />
              <span data-testid="sheet-health-warning-count">{{ warningCount }}</span>
            </span>
            <span v-if="infoCount > 0" class="flex items-center gap-1 text-blue-500">
              <Info class="size-3.5" />
              <span data-testid="sheet-health-info-count">{{ infoCount }}</span>
            </span>
            <ChevronDown class="size-3 text-muted-foreground" />
          </PopoverTrigger>
        </ToolbarTooltip>
      </PopoverAnchor>

      <PopoverContent side="bottom" align="end" :side-offset="6" class="w-90 max-w-[90vw] p-1">
        <div class="max-h-72 overflow-y-auto">
          <section v-if="health.errorItems.length > 0" data-testid="sheet-health-errors">
            <h3 class="px-2 py-1 text-[10px] font-medium uppercase text-muted-foreground">
              {{ $t("sheets.health.errors") }}
            </h3>
            <button
              v-for="(item, index) in health.errorItems"
              :key="`error-${item.blockId ?? 'sheet'}-${item.rowId ?? index}-${item.columnId ?? index}`"
              type="button"
              data-health-severity="error"
              :data-health-block-id="item.blockId"
              :disabled="item.blockId == null"
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
          </section>

          <section v-if="health.warningItems.length > 0" data-testid="sheet-health-warnings">
            <h3 class="mt-1 px-2 py-1 text-[10px] font-medium uppercase text-muted-foreground">
              {{ $t("sheets.health.warnings") }}
            </h3>
            <button
              v-for="(item, index) in health.warningItems"
              :key="`warning-${item.blockId ?? 'sheet'}-${item.rowId ?? index}-${item.columnId ?? index}`"
              type="button"
              data-health-severity="warning"
              :data-health-block-id="item.blockId"
              :disabled="item.blockId == null"
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
          </section>

          <section v-if="health.infoItems.length > 0" data-testid="sheet-health-info">
            <h3 class="mt-1 px-2 py-1 text-[10px] font-medium uppercase text-muted-foreground">
              {{ $t("sheets.health.info") }}
            </h3>
            <button
              v-for="(item, index) in health.infoItems"
              :key="`info-${item.blockId ?? 'sheet'}-${item.rowId ?? index}-${item.columnId ?? index}`"
              type="button"
              data-health-severity="info"
              :data-health-block-id="item.blockId"
              :disabled="item.blockId == null"
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
          </section>
        </div>
      </PopoverContent>
    </Popover>

    <ToolbarTooltip v-else :label="$t('sheets.health.looks_great')" side="bottom">
      <div
        data-testid="sheet-health-clean"
        class="inline-flex size-8 items-center justify-center rounded-md border border-border bg-background/60 text-green-500/70"
      >
        <CircleCheck class="size-4" />
      </div>
    </ToolbarTooltip>
  </div>
</template>
