<script setup lang="ts">
import { computed } from "vue";
import { ArrowRight, ShieldQuestion } from "lucide-vue-next";

export interface ResponseData {
  id: string;
  text: string;
  valid: boolean;
  number: number;
  has_condition: boolean;
}

const {
  responses,
  playerMode,
  showContinue = false,
} = defineProps<{
  responses: ResponseData[];
  playerMode: "player" | "analysis";
  showContinue?: boolean;
}>();

const emit = defineEmits<{
  choose: [responseId: string];
  continue: [];
}>();

const visibleResponses = computed(() => {
  if (playerMode === "player") {
    return responses.filter((r) => r.valid);
  }
  return responses;
});

const shouldShowContinue = computed(() => showContinue && visibleResponses.value.length === 0);
</script>

<template>
  <div v-if="visibleResponses.length > 0 || shouldShowContinue" class="player-choices">
    <button
      v-if="shouldShowContinue"
      type="button"
      class="player-response player-response-continue"
      @click="emit('continue')"
    >
      <span class="player-response-number player-response-icon">
        <ArrowRight :size="14" />
      </span>
      <span class="player-response-text">{{ $t("flows.player.continue") }}</span>
    </button>

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
