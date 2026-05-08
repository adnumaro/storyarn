<script setup lang="ts">
import { Download, Eye, Pencil, Settings } from "lucide-vue-next";
import { Button } from "@components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@components/ui/dropdown-menu";
import { useLive } from "../../../shared/composables/useLive";

const { editMode = true, canEdit = false } = defineProps<{
  editMode: boolean;
  canEdit: boolean;
}>();

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
    <Button
      v-if="canEdit && editMode"
      variant="ghost"
      size="icon-sm"
      class="size-7"
      :title="$t('scenes.actions.scene_settings')"
      @click="openSettings"
    >
      <Settings class="size-3.5" />
    </Button>

    <!-- Export -->
    <DropdownMenu>
      <DropdownMenuTrigger as-child>
        <Button variant="ghost" size="icon-sm" class="size-7" :title="$t('scenes.actions.export')">
          <Download class="size-3.5" />
        </Button>
      </DropdownMenuTrigger>
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
    <Button
      v-if="canEdit"
      variant="ghost"
      size="icon-sm"
      class="size-7"
      :title="editMode ? $t('scenes.actions.switch_view') : $t('scenes.actions.switch_edit')"
      @click="toggleEditMode"
    >
      <component :is="editMode ? Eye : Pencil" class="size-3.5" />
    </Button>
  </div>
</template>
