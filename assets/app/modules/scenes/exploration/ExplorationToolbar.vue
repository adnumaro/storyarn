<script setup lang="ts">
import { ArrowLeft, Save, Scan } from "lucide-vue-next";
import { Button } from "@components/ui/button";
import ToolbarTooltip from "@components/toolbar/ToolbarTooltip.vue";
import { useLive } from "../../../shared/composables/useLive";

const {
  sceneName = "",
  activeFlowName = null,
  flowMode = false,
  showZones = false,
} = defineProps<{
  sceneName?: string;
  activeFlowName?: string | null;
  flowMode?: boolean;
  showZones?: boolean;
}>();

const live = useLive();

function exit() {
  live.pushEvent("exit_exploration", {});
}

function save() {
  live.pushEvent("save_session", {});
}

function toggleZones() {
  live.pushEvent("toggle_show_zones", {});
}
</script>

<template>
  <div
    class="flex items-center h-10 px-2 bg-background/80 backdrop-blur-sm border-b border-border shrink-0"
  >
    <!-- Left: Exit -->
    <div class="flex items-center gap-1">
      <Button variant="ghost" size="sm" @click="exit">
        <ArrowLeft class="size-4" />
        {{ $t("scenes.exploration.exit") }}
      </Button>
    </div>

    <!-- Center: Scene name + flow name -->
    <div class="flex-1 flex items-center justify-center gap-2 min-w-0">
      <span class="text-sm font-medium truncate">{{ sceneName }}</span>
      <span v-if="flowMode && activeFlowName" class="text-xs opacity-50 truncate">
        — {{ activeFlowName }}
      </span>
    </div>

    <!-- Right: Save + Show zones -->
    <div class="flex items-center gap-1">
      <ToolbarTooltip :label="$t('scenes.exploration.save_progress')">
        <Button variant="ghost" size="icon-sm" @click="save">
          <Save class="size-4" />
        </Button>
      </ToolbarTooltip>
      <ToolbarTooltip :label="$t('scenes.exploration.show_zones')">
        <Button :variant="showZones ? 'secondary' : 'ghost'" size="icon-sm" @click="toggleZones">
          <Scan class="size-4" />
        </Button>
      </ToolbarTooltip>
    </div>
  </div>
</template>
