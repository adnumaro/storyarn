<script setup lang="ts">
import { Download, Eye, Pencil, Settings } from "lucide-vue-next";
import ToolbarTooltip from "@components/toolbar/ToolbarTooltip.vue";
import { Button } from "@components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@components/ui/dropdown-menu";
import { useLive } from "@shared/composables/useLive.ts";

interface SceneHeaderActionsProps {
  editMode: boolean;
  canEdit: boolean;
}

const { editMode = true, canEdit = false } = defineProps<SceneHeaderActionsProps>();

const live = useLive();

function toggleEditMode(): void {
  live.pushEvent("toggle_edit_mode", {
    mode: editMode ? "view" : "edit",
  });
}

function exportScene(format: string): void {
  live.pushEvent("export_scene", { format });
}

function openSettings(): void {
  live.pushEvent("open_scene_settings", {});
}
</script>

<template>
  <div class="flex items-center gap-1 surface-panel px-1.5 h-full">
    <!-- Settings -->
    <ToolbarTooltip
      v-if="canEdit && editMode"
      :label="$t('scenes.actions.scene_settings')"
      side="bottom"
    >
      <Button variant="ghost" size="icon-sm" class="size-7" @click="openSettings">
        <Settings class="size-3.5" />
      </Button>
    </ToolbarTooltip>

    <!-- Export -->
    <DropdownMenu>
      <ToolbarTooltip :label="$t('scenes.actions.export')" side="bottom">
        <DropdownMenuTrigger class="toolbar-btn size-7">
          <Download class="size-3.5" />
        </DropdownMenuTrigger>
      </ToolbarTooltip>
      <DropdownMenuContent align="end">
        <DropdownMenuItem class="text-xs gap-2" @select="exportScene('png')">
          {{ $t("scenes.actions.export_png") }}
        </DropdownMenuItem>
        <DropdownMenuItem class="text-xs gap-2" @select="exportScene('svg')">
          {{ $t("scenes.actions.export_svg") }}
        </DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>

    <!-- Edit/View toggle -->
    <ToolbarTooltip
      v-if="canEdit"
      :label="editMode ? $t('scenes.actions.switch_view') : $t('scenes.actions.switch_edit')"
      side="bottom"
    >
      <Button variant="ghost" size="icon-sm" class="size-7" @click="toggleEditMode">
        <component :is="editMode ? Eye : Pencil" class="size-3.5" />
      </Button>
    </ToolbarTooltip>
  </div>
</template>
