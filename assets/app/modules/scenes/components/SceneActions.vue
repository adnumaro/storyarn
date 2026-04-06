<script setup lang="ts">
import { Download, Eye, Pencil, Settings } from "lucide-vue-next";
import { Button } from "@components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@components/ui/dropdown-menu";
import { useLive } from "@composables/useLive";

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
  <div class="flex items-center gap-1 v2-surface-panel px-1.5 h-full">
    <!-- Settings -->
    <Button
      v-if="canEdit && editMode"
      variant="ghost"
      size="icon-sm"
      class="size-7"
      title="Scene settings"
      @click="openSettings"
    >
      <Settings class="size-3.5" />
    </Button>

    <!-- Export -->
    <DropdownMenu>
      <DropdownMenuTrigger as-child>
        <Button variant="ghost" size="icon-sm" class="size-7" title="Export">
          <Download class="size-3.5" />
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end">
        <DropdownMenuItem class="text-xs gap-2" @select="exportScene('png')">
          Export as PNG
        </DropdownMenuItem>
        <DropdownMenuItem class="text-xs gap-2" @select="exportScene('svg')">
          Export as SVG
        </DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>

    <!-- Edit/View toggle -->
    <Button
      v-if="canEdit"
      variant="ghost"
      size="icon-sm"
      class="size-7"
      :title="editMode ? 'Switch to view mode' : 'Switch to edit mode'"
      @click="toggleEditMode"
    >
      <component :is="editMode ? Eye : Pencil" class="size-3.5" />
    </Button>
  </div>
</template>
