<script setup lang="ts">
import { AlertCircle } from "@lucide/vue";

defineProps<{
  visible: boolean;
}>();
</script>

<template>
  <div
    v-if="visible"
    role="alert"
    data-testid="version-transport-error"
    class="flex items-start gap-2 rounded-lg border border-destructive/30 bg-destructive/10 p-3 text-sm text-destructive"
  >
    <AlertCircle class="mt-0.5 size-4 shrink-0" />
    <p>{{ $t("common.version_history.transport_error") }}</p>
  </div>
</template>
