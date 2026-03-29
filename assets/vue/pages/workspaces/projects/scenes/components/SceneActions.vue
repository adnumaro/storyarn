<script setup>
import { Download, Eye, Pencil, Settings } from "lucide-vue-next";
import { Button } from "@/vue/components/ui/button";
import {
	DropdownMenu,
	DropdownMenuContent,
	DropdownMenuItem,
	DropdownMenuTrigger,
} from "@/vue/components/ui/dropdown-menu";
import { useLive } from "@/vue/composables/useLive";

const props = defineProps({
	editMode: { type: Boolean, default: true },
	canEdit: { type: Boolean, default: false },
});

const live = useLive();

function toggleEditMode() {
	live.pushEvent("toggle_edit_mode", {
		mode: props.editMode ? "view" : "edit",
	});
}

function exportScene(format) {
	live.pushEvent("export_scene", { format });
}

function openSettings() {
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
