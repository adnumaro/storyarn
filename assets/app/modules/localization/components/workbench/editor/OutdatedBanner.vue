<script setup lang="ts">
import { Check, TriangleAlert } from "@lucide/vue";
import { Button } from "@components/ui/button";

/**
 * The source changed after this translation was written. The translator can
 * confirm the translation still fits; saving a new one clears the flag too.
 */
const { canEdit = false, busy = false } = defineProps<{
  canEdit?: boolean;
  busy?: boolean;
}>();

const emit = defineEmits<{ confirm: [] }>();
</script>

<template>
  <div
    class="flex flex-col gap-3 rounded-md border border-orange-500/35 bg-orange-500/8 px-3.5 py-3"
    role="status"
    data-testid="localization-outdated-banner"
  >
    <div class="flex items-start gap-2.5">
      <TriangleAlert class="mt-0.5 size-4 shrink-0 text-orange-600 dark:text-orange-400" />
      <p class="text-[13px] font-medium">{{ $t("localization.editor.outdated.title") }}</p>
    </div>
    <div v-if="canEdit" class="flex flex-wrap items-center gap-2 sm:pl-6.5">
      <Button variant="outline" size="sm" :disabled="busy" @click="emit('confirm')">
        <Check class="size-3.5" />
        {{ $t("localization.editor.outdated.confirm") }}
      </Button>
      <span class="text-xs text-muted-foreground">
        {{ $t("localization.editor.outdated.hint") }}
      </span>
    </div>
  </div>
</template>
