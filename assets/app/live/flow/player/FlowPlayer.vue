<script setup lang="ts">
import { computed, onMounted, onUnmounted } from "vue";
import { useLive } from "@shared/composables/useLive";
import PlayerSlide from "@modules/flows/player/components/PlayerSlide.vue";
import PlayerChoices from "@modules/flows/player/components/PlayerChoices.vue";
import PlayerToolbar from "@modules/flows/player/components/PlayerToolbar.vue";
import PlayerOutcome from "@modules/flows/player/components/PlayerOutcome.vue";
import PlayerAudioTracks from "@modules/flows/player/components/PlayerAudioTracks.vue";
import PlayerVisualLayers from "@modules/flows/player/components/PlayerVisualLayers.vue";
import type { SlideData } from "@modules/flows/player/components/PlayerSlide.vue";
import type { ResponseData } from "@modules/flows/player/components/PlayerChoices.vue";
import type { OutcomeData } from "@modules/flows/player/components/PlayerOutcome.vue";
import type { PlayerAudioTrack } from "@modules/flows/player/components/PlayerAudioTracks.vue";
import type { PlayerVisualLayer } from "@modules/flows/player/components/PlayerVisualLayers.vue";

const {
  slide,
  playerMode,
  canGoBack,
  showContinue,
  isFinished,
  visualLayers = [],
  audioTracks = [],
  editorUrl,
  responses = [],
} = defineProps<{
  slide: SlideData | OutcomeData;
  playerMode: "player" | "analysis";
  canGoBack: boolean;
  showContinue: boolean;
  isFinished: boolean;
  visualLayers?: PlayerVisualLayer[];
  audioTracks?: PlayerAudioTrack[];
  editorUrl: string;
  responses: ResponseData[];
}>();

const live = useLive();

function onChooseResponse(responseId: string) {
  live.pushEvent("choose_response", { id: responseId });
}

function onContinue() {
  live.pushEvent("continue", {});
}

function onGoBack() {
  live.pushEvent("go_back", {});
}

function onToggleMode() {
  live.pushEvent("toggle_mode", {});
}

function onRestart() {
  live.pushEvent("restart", {});
}

const visibleResponses = computed(() => {
  if (playerMode === "player") {
    return responses.filter((r) => r.valid);
  }
  return responses;
});

const EDITABLE_TAGS = new Set(["INPUT", "TEXTAREA", "SELECT"]);

const KEY_ACTIONS: Record<string, () => void> = {
  " ": () => {
    if (showContinue && !isFinished) onContinue();
  },
  Enter: () => {
    if (showContinue && !isFinished) onContinue();
  },
  ArrowRight: () => {
    if (showContinue && !isFinished) onContinue();
  },
  ArrowLeft: () => onGoBack(),
  Escape: () => live.pushEvent("exit_player", {}),
  p: () => onToggleMode(),
  P: () => onToggleMode(),
  r: () => onRestart(),
  R: () => onRestart(),
};

function handleNumberKey(key: string) {
  if (key >= "1" && key <= "9") {
    const resp = visibleResponses.value[parseInt(key) - 1];
    if (resp) onChooseResponse(resp.id);
  }
}

function handleKeydown(e: KeyboardEvent) {
  if (EDITABLE_TAGS.has((e.target as HTMLElement).tagName)) return;

  const action = KEY_ACTIONS[e.key];
  if (action) {
    e.preventDefault();
    action();
  } else {
    handleNumberKey(e.key);
  }
}

onMounted(() => {
  document.addEventListener("keydown", handleKeydown);
});

onUnmounted(() => {
  document.removeEventListener("keydown", handleKeydown);
});
</script>

<template>
  <div class="player-frame">
    <PlayerToolbar
      :can-go-back="canGoBack"
      :player-mode="playerMode"
      :editor-url="editorUrl"
      @go-back="onGoBack"
      @toggle-mode="onToggleMode"
      @restart="onRestart"
    />

    <div class="player-main">
      <div class="player-stage">
        <PlayerVisualLayers :layers="visualLayers" />
        <PlayerAudioTracks :tracks="audioTracks" />

        <PlayerOutcome
          v-if="slide.type === 'outcome'"
          :slide="slide as OutcomeData"
          :editor-url="editorUrl"
          @restart="onRestart"
        />
      </div>

      <div v-if="slide.type !== 'outcome'" class="player-dialogue-overlay">
        <div class="player-dialogue-panel">
          <PlayerSlide :slide="slide as SlideData" />
          <PlayerChoices
            :responses="responses"
            :player-mode="playerMode"
            :show-continue="showContinue && !isFinished"
            @choose="onChooseResponse"
            @continue="onContinue"
          />
        </div>
      </div>
    </div>
  </div>
</template>
