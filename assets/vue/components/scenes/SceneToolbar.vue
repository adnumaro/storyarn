<script setup>
import {
	Cable,
	Circle,
	Download,
	Eye,
	Hand,
	MapPin,
	MousePointer,
	Pencil,
	PenTool,
	Ruler,
	Settings,
	Square,
	StickyNote,
	Triangle,
} from "lucide-vue-next";
import { computed } from "vue";
import EditableText from "@/vue/components/EditableText.vue";
import { Button } from "@/vue/components/ui/button";
import {
	DropdownMenu,
	DropdownMenuContent,
	DropdownMenuItem,
	DropdownMenuTrigger,
} from "@/vue/components/ui/dropdown-menu";
import { ToggleGroup, ToggleGroupItem } from "@/vue/components/ui/toggle-group";
import { useLive } from "@/vue/composables/useLive";

const props = defineProps({
	activeTool: { type: String, default: "select" },
	editMode: { type: Boolean, default: true },
	canEdit: { type: Boolean, default: false },
	sceneName: { type: String, default: "" },
	sceneShortcut: { type: String, default: "" },
});

const live = useLive();

const tools = [
	{ id: "select", icon: MousePointer, label: "Select (Shift+V)" },
	{ id: "pan", icon: Hand, label: "Pan (Shift+H)" },
	{ id: "rectangle", icon: Square, label: "Rectangle (Shift+R)" },
	{ id: "triangle", icon: Triangle, label: "Triangle (Shift+T)" },
	{ id: "circle", icon: Circle, label: "Circle (Shift+C)" },
	{ id: "freeform", icon: PenTool, label: "Freeform (Shift+F)" },
	{ id: "pin", icon: MapPin, label: "Pin (Shift+P)" },
	{ id: "annotation", icon: StickyNote, label: "Annotation (Shift+N)" },
	{ id: "connector", icon: Cable, label: "Connector (Shift+L)" },
	{ id: "ruler", icon: Ruler, label: "Ruler (Shift+M)" },
];

const currentTool = computed(() => props.activeTool);

function setTool(tool) {
	if (tool) {
		live.pushEvent("set_tool", { type: tool });
	}
}

function saveName(name) {
	live.pushEvent("save_name", { name });
}

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
  <div class="flex items-center gap-2">
    <!-- Scene name pill -->
    <div class="flex items-center gap-1.5 v2-surface-panel px-3 py-1.5">
      <EditableText
        :model-value="sceneName"
        placeholder="Scene name"
        tag="span"
        class="text-sm font-medium max-w-[200px] truncate"
        :disabled="!canEdit"
        @save="saveName"
      />
      <span v-if="sceneShortcut" class="text-xs text-muted-foreground">
        #{{ sceneShortcut }}
      </span>
    </div>

    <!-- Tool palette (edit mode only) -->
    <div v-if="canEdit && editMode" class="v2-surface-panel px-1.5 py-1">
      <ToggleGroup
        type="single"
        :model-value="currentTool"
        class="gap-0.5"
        @update:model-value="setTool"
      >
        <ToggleGroupItem
          v-for="tool in tools"
          :key="tool.id"
          :value="tool.id"
          :aria-label="tool.label"
          :title="tool.label"
          class="size-7 p-0"
          size="sm"
        >
          <component :is="tool.icon" class="size-3.5" />
        </ToggleGroupItem>
      </ToggleGroup>
    </div>

    <!-- Actions -->
    <div class="flex items-center gap-1 v2-surface-panel px-1.5 py-1">
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
    </div>
  </div>
</template>
