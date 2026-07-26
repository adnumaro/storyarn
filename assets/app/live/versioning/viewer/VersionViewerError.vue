<script setup lang="ts">
import { computed } from "vue";
import { FileQuestion, ShieldAlert, ShieldOff, TriangleAlert } from "lucide-vue-next";

type ViewerErrorReason = "not_found" | "unverified_legacy" | "integrity" | "unreadable";

const { reason } = defineProps<{
  reason: ViewerErrorReason;
}>();

const ICONS = {
  not_found: FileQuestion,
  unverified_legacy: ShieldOff,
  integrity: ShieldAlert,
  unreadable: TriangleAlert,
} as const;

const icon = computed(() => ICONS[reason] ?? TriangleAlert);
const titleKey = computed(() => `common.version_viewer_error.${reason}.title`);
const descriptionKey = computed(() => `common.version_viewer_error.${reason}.description`);
</script>

<template>
  <div
    class="h-full w-full flex items-center justify-center p-6 bg-background"
    data-testid="version-viewer-error"
  >
    <div class="max-w-sm flex flex-col items-center text-center gap-3">
      <div
        class="flex items-center justify-center size-11 rounded-full bg-muted text-muted-foreground"
      >
        <component :is="icon" class="size-5" />
      </div>
      <p class="text-sm font-medium text-foreground">{{ $t(titleKey) }}</p>
      <p class="text-xs text-muted-foreground leading-relaxed">{{ $t(descriptionKey) }}</p>
    </div>
  </div>
</template>
