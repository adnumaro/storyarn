<script setup lang="ts">
import { ArrowLeft, ArrowRight, Eye, ScanEye, RotateCcw, X } from "lucide-vue-next";
import { Button } from "@components/ui/button";
import { Toggle } from "@components/ui/toggle";

const { canGoBack, showContinue, playerMode, isFinished, editorUrl } = defineProps<{
  canGoBack: boolean;
  showContinue: boolean;
  playerMode: "player" | "analysis";
  isFinished: boolean;
  editorUrl: string;
}>();

const emit = defineEmits<{
  "go-back": [];
  continue: [];
  "toggle-mode": [];
  restart: [];
}>();
</script>

<template>
  <div class="player-toolbar">
    <div class="player-toolbar-left">
      <Button
        variant="ghost"
        size="icon-sm"
        :disabled="!canGoBack"
        title="Back"
        @click="emit('go-back')"
      >
        <ArrowLeft :size="16" />
      </Button>
      <Button
        v-if="showContinue && !isFinished"
        size="sm"
        title="Continue"
        @click="emit('continue')"
      >
        Continue
        <ArrowRight :size="16" />
      </Button>
    </div>

    <div class="player-toolbar-center">
      <Toggle
        :model-value="playerMode === 'analysis'"
        class="player-toolbar-btn-mode"
        title="Toggle mode"
        @update:model-value="emit('toggle-mode')"
      >
        <component :is="playerMode === 'player' ? Eye : ScanEye" :size="16" />
        <span class="hidden sm:inline">
          {{ playerMode === "player" ? "Player" : "Analysis" }}
        </span>
      </Toggle>
    </div>

    <div class="player-toolbar-right">
      <Button variant="ghost" size="icon-sm" title="Restart" @click="emit('restart')">
        <RotateCcw :size="16" />
      </Button>
      <Button
        variant="ghost"
        size="icon-sm"
        as="a"
        :href="editorUrl"
        title="Back to editor"
        data-phx-link="redirect"
        data-phx-link-state="push"
      >
        <X :size="16" />
      </Button>
    </div>
  </div>
</template>
