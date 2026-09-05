<script setup lang="ts">
import { STATUS_I18N, TONES, type TranslationStatus } from "../../domain/status";

/** The five statuses in bar order, as a compact legend. */
const order: TranslationStatus[] = ["final", "review", "in_progress", "draft", "pending"];
</script>

<template>
  <div class="flex flex-wrap gap-x-3.5 gap-y-1 text-xs text-muted-foreground">
    <span v-for="status in order" :key="status" class="inline-flex items-center gap-1.5">
      <span :class="['size-2 rounded-sm', TONES[status].dot]" aria-hidden="true" />
      {{ $t(STATUS_I18N[status]) }}
    </span>
  </div>
</template>
