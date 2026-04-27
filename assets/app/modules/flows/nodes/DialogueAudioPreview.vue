<script setup lang="ts">
import { Volume2 } from "lucide-vue-next";
import { computed } from "vue";

const { audioAssetId } = defineProps<{
  audioAssetId?: string | number | null;
}>();

const hasAudio = computed(() => !!audioAssetId);
</script>

<template>
  <Volume2
    v-if="hasAudio"
    class="ml-auto size-3.5 opacity-80"
    :aria-label="$t('flows.dialogue_toolbar.has_audio')"
  />
</template>
