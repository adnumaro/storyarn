<script setup lang="ts">
import { computed } from "vue";
import { Badge } from "@components/ui/badge";
import { Progress } from "@components/ui/progress";

export type SettingsMeterStatus = "available" | "warning" | "reached" | "unlimited" | "unknown";

/**
 * A quota as one row: label and hint left, `used / limit` and a status pill
 * right, a progress bar below, and an optional footer for what to do when the
 * limit is reached.
 */
const {
  label,
  hint = null,
  used,
  limit = null,
  percent = null,
  status,
  statusLabel,
} = defineProps<{
  label: string;
  hint?: string | null;
  used: string;
  limit?: string | null;
  percent?: number | null;
  status: SettingsMeterStatus;
  statusLabel: string;
}>();

const badgeVariant = computed<"default" | "secondary" | "destructive" | "outline">(() => {
  if (status === "reached") return "destructive";
  if (status === "warning") return "default";
  if (status === "available") return "secondary";
  return "outline";
});
</script>

<template>
  <div class="flex flex-col gap-2.5 px-4 py-3.5" :data-meter-status="status">
    <div class="grid grid-cols-1 items-center gap-x-6 gap-y-2 sm:grid-cols-[minmax(0,1fr)_auto]">
      <div class="min-w-0">
        <div class="font-medium">{{ label }}</div>
        <div v-if="hint || $slots.hint" class="text-[13px] text-muted-foreground">
          <slot name="hint">{{ hint }}</slot>
        </div>
      </div>
      <div class="flex items-center justify-end gap-3">
        <span class="text-[13px] tabular-nums text-muted-foreground">
          <span class="text-foreground">{{ used }}</span>
          <template v-if="limit !== null"> / {{ limit }}</template>
        </span>
        <Badge :variant="badgeVariant">{{ statusLabel }}</Badge>
      </div>
    </div>

    <Progress v-if="percent !== null" :model-value="percent" class="h-2" />

    <div
      v-if="$slots.footer"
      class="grid grid-cols-1 items-center gap-x-6 gap-y-2 text-[13px] text-muted-foreground sm:grid-cols-[minmax(0,1fr)_auto]"
    >
      <slot name="footer" />
    </div>
  </div>
</template>
