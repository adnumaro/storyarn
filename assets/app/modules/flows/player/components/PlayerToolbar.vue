<script setup lang="ts">
import { ArrowLeft, Eye, ScanEye, RotateCcw, X } from "lucide-vue-next";
import { Button } from "@components/ui/button";
import { Toggle } from "@components/ui/toggle";
import ToolbarTooltip from "@components/toolbar/ToolbarTooltip.vue";

const { canGoBack, playerMode, editorUrl } = defineProps<{
  canGoBack: boolean;
  playerMode: "player" | "analysis";
  editorUrl: string;
}>();

const emit = defineEmits<{
  "go-back": [];
  "toggle-mode": [];
  restart: [];
}>();
</script>

<template>
  <div class="player-toolbar">
    <div class="player-toolbar-left">
      <ToolbarTooltip :label="$t('flows.player.back')">
        <Button variant="ghost" size="icon-sm" :disabled="!canGoBack" @click="emit('go-back')">
          <ArrowLeft :size="16" />
        </Button>
      </ToolbarTooltip>
    </div>

    <div class="player-toolbar-center">
      <ToolbarTooltip :label="$t('flows.player.toggle_mode')">
        <Toggle
          :model-value="playerMode === 'analysis'"
          class="player-toolbar-btn-mode"
          @update:model-value="emit('toggle-mode')"
        >
          <component :is="playerMode === 'player' ? Eye : ScanEye" :size="16" />
          <span class="hidden sm:inline">
            {{
              playerMode === "player"
                ? $t("flows.player.mode_player")
                : $t("flows.player.mode_analysis")
            }}
          </span>
        </Toggle>
      </ToolbarTooltip>
    </div>

    <div class="player-toolbar-right">
      <ToolbarTooltip :label="$t('flows.player.restart')">
        <Button variant="ghost" size="icon-sm" @click="emit('restart')">
          <RotateCcw :size="16" />
        </Button>
      </ToolbarTooltip>
      <ToolbarTooltip :label="$t('flows.player.back_to_editor')">
        <Button
          variant="ghost"
          size="icon-sm"
          as="a"
          :href="editorUrl"
          data-phx-link="redirect"
          data-phx-link-state="push"
        >
          <X :size="16" />
        </Button>
      </ToolbarTooltip>
    </div>
  </div>
</template>
