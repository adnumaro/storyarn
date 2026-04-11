<script setup lang="ts">
import { computed } from "vue";
import { ShieldQuestion } from "lucide-vue-next";

export interface ResponseData {
  id: string;
  text: string;
  valid: boolean;
  number: number;
  has_condition: boolean;
}

const { responses, playerMode } = defineProps<{
  responses: ResponseData[];
  playerMode: "player" | "analysis";
}>();

const emit = defineEmits<{
  choose: [responseId: string];
}>();

const visibleResponses = computed(() => {
  if (playerMode === "player") {
    return responses.filter((r) => r.valid);
  }
  return responses;
});
</script>

<template>
  <div v-if="visibleResponses.length > 0" class="player-choices">
    <button
      v-for="resp in visibleResponses"
      :key="resp.id"
      type="button"
      :class="['player-response', !resp.valid && 'player-response-invalid']"
      :disabled="!resp.valid && playerMode === 'analysis'"
      @click="emit('choose', resp.id)"
    >
      <span class="player-response-number">{{ resp.number }}</span>
      <span class="player-response-text">{{ resp.text }}</span>
      <span v-if="resp.has_condition && playerMode === 'analysis'" class="player-response-badge">
        <ShieldQuestion :size="12" />
      </span>
    </button>
  </div>
</template>
