<script setup>
import { computed } from "vue";

const { subtitle } = defineProps({
  subtitle: { type: Object, default: null },
});

const visible = computed(() => subtitle != null);
</script>

<template>
  <div
    v-if="visible"
    class="absolute bottom-16 inset-x-0 z-40 flex justify-center pointer-events-none"
  >
    <div
      class="bg-background/90 backdrop-blur-sm border border-border rounded-lg px-4 py-2 max-w-lg shadow-lg animate-in fade-in duration-200"
    >
      <div v-if="subtitle.speaker" class="text-xs font-semibold text-primary mb-0.5">
        {{ subtitle.speaker }}
      </div>
      <div class="text-sm text-foreground leading-relaxed text-center">
        {{ subtitle.text }}
      </div>
    </div>
  </div>
</template>
