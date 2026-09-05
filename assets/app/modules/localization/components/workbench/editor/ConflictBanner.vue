<script setup lang="ts">
import { TriangleAlert } from "@lucide/vue";
import { Button } from "@components/ui/button";

/** Somebody saved this string while it was open here. */
const emit = defineEmits<{ overwrite: []; reload: [] }>();
</script>

<template>
  <div
    class="flex items-start gap-2.5 rounded-md border border-amber-500/40 bg-amber-500/8 px-3.5 py-3 text-[13px]"
    role="alert"
    data-testid="localization-conflict-banner"
  >
    <TriangleAlert class="mt-0.5 size-4 shrink-0 text-amber-600 dark:text-amber-400" />
    <div class="min-w-0 flex-1">
      <p class="font-medium">{{ $t("localization.editor.conflict.title") }}</p>
      <p class="mt-0.5 text-xs text-muted-foreground">
        {{ $t("localization.editor.conflict.description") }}
      </p>
      <div class="mt-2 flex gap-2">
        <Button size="xs" @click="emit('overwrite')">
          {{ $t("localization.editor.conflict.overwrite") }}
        </Button>
        <Button variant="ghost" size="xs" @click="emit('reload')">
          {{ $t("localization.editor.conflict.reload") }}
        </Button>
      </div>
    </div>
  </div>
</template>
