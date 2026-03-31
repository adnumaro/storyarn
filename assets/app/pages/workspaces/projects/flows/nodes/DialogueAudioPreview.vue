<script setup>
import { computed } from "vue";

const props = defineProps({
  audioAssetId: { type: [String, Number], default: null },
});

const hasAudio = computed(() => !!props.audioAssetId);
</script>

<template>
  <span v-if="hasAudio" class="ml-auto opacity-80 text-xs" title="Has audio">&#x1F50A;</span>
</template>
