<script setup lang="ts">
import { computed, onMounted, onUnmounted } from "vue";
import { useLive } from "@composables/useLive";
import PlayerSlide from "./PlayerSlide.vue";
import PlayerChoices from "./PlayerChoices.vue";
import PlayerToolbar from "./PlayerToolbar.vue";
import PlayerOutcome from "./PlayerOutcome.vue";
import type { SlideData } from "./PlayerSlide.vue";
import type { ResponseData } from "./PlayerChoices.vue";
import type { OutcomeData } from "./PlayerOutcome.vue";

const {
  slide,
  playerMode,
  canGoBack,
  showContinue,
  isFinished,
  sceneBackdropUrl = null,
  editorUrl,
  responses = [],
} = defineProps<{
  slide: SlideData | OutcomeData;
  playerMode: "player" | "analysis";
  canGoBack: boolean;
  showContinue: boolean;
  isFinished: boolean;
  sceneBackdropUrl: string | null;
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
  <div class="player-main relative">
    <!-- Scene backdrop -->
    <div v-if="sceneBackdropUrl" class="scene-backdrop scene-backdrop-transition">
      <img :src="sceneBackdropUrl" alt="" class="scene-backdrop-img" draggable="false" />
    </div>

    <!-- Flow content -->
    <div class="relative z-10 flex flex-col items-center justify-center flex-1 w-full">
      <PlayerOutcome
        v-if="slide.type === 'outcome'"
        :slide="slide as OutcomeData"
        :editor-url="editorUrl"
        @restart="onRestart"
      />
      <template v-else>
        <PlayerSlide :slide="slide as SlideData" />
        <PlayerChoices
          :responses="responses"
          :player-mode="playerMode"
          @choose="onChooseResponse"
        />
      </template>
    </div>
  </div>

  <PlayerToolbar
    :can-go-back="canGoBack"
    :show-continue="showContinue"
    :player-mode="playerMode"
    :is-finished="isFinished"
    :editor-url="editorUrl"
    @go-back="onGoBack"
    @continue="onContinue"
    @toggle-mode="onToggleMode"
    @restart="onRestart"
  />
</template>
