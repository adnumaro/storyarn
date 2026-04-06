<script setup lang="ts">
import { computed } from "vue";

const { audioAssetId } = defineProps<{
  audioAssetId?: string | number | null;
}>();

const hasAudio = computed(() => !!audioAssetId);
</script>

<template>
  <span v-if="hasAudio" class="ml-auto opacity-80 text-xs" title="Has audio">&#x1F50A;</span>
</template>
