<script setup>
import {
	ChevronDown,
	FileText,
	Folder,
	GitBranch,
	Image,
	Languages,
	LayoutDashboard,
	Map,
	PanelLeft,
	ScrollText,
	Settings,
	Trash2,
} from "lucide-vue-next";
import { computed } from "vue";
import {
	DropdownMenu,
	DropdownMenuContent,
	DropdownMenuItem,
	DropdownMenuSeparator,
	DropdownMenuTrigger,
} from "@/vue/components/ui/dropdown-menu";
import {
	Tooltip,
	TooltipContent,
	TooltipProvider,
	TooltipTrigger,
} from "@/vue/components/ui/tooltip";
import { useLive } from "@/vue/composables/useLive";

const props = defineProps({
	activeTool: { type: String, required: true },
	hasTree: { type: Boolean, default: true },
	treePanelOpen: { type: Boolean, default: false },
	projectName: { type: String, required: true },
	workspaceName: { type: String, required: true },
	showToolSwitcher: { type: Boolean, default: true },
	isSuperAdmin: { type: Boolean, default: false },
	urls: { type: Object, required: true },
});

const live = useLive();

const tools = [
	{ key: "dashboard", icon: LayoutDashboard, label: "Dashboard" },
	{ key: "sheets", icon: FileText, label: "Sheets" },
	{ key: "flows", icon: GitBranch, label: "Flows" },
	{ key: "scenes", icon: Map, label: "Scenes" },
	{ key: "screenplays", icon: ScrollText, label: "Screenplays" },
	{ key: "assets", icon: Image, label: "Assets" },
	{ key: "localization", icon: Languages, label: "Localization" },
];

const activeToolDef = computed(
	() => tools.find((t) => t.key === props.activeTool) || tools[0],
);

const otherTools = computed(() => {
	const filtered = tools.filter((t) => t.key !== props.activeTool);
	if (!props.isSuperAdmin) {
		return filtered.filter((t) => t.key !== "screenplays");
	}
	return filtered;
});

function toggleTreePanel() {
	live.pushEvent("tree_panel_toggle", {});
}
</script>

<template>
  <nav class="flex items-center gap-1 px-1 py-1 v2-surface-panel">
    <!-- Tree panel toggle -->
    <TooltipProvider v-if="hasTree" :delay-duration="300">
      <Tooltip>
        <TooltipTrigger as-child>
          <button
            type="button"
            :class="[
              'v2-toolbar-btn size-8',
              treePanelOpen && 'bg-accent',
            ]"
            @click="toggleTreePanel"
          >
            <PanelLeft class="size-4" />
          </button>
        </TooltipTrigger>
        <TooltipContent side="bottom" align="start">
          {{ treePanelOpen ? "Hide panel" : "Show panel" }}
        </TooltipContent>
      </Tooltip>
    </TooltipProvider>

    <div v-if="hasTree" class="w-px h-5 bg-border" />

    <!-- Project dropdown -->
    <DropdownMenu>
      <DropdownMenuTrigger as-child>
        <button class="v2-toolbar-btn gap-1.5 font-medium max-w-52">
          <Folder class="size-4 opacity-60 shrink-0" />
          <span class="hidden xl:inline truncate text-sm">{{ projectName }}</span>
          <ChevronDown class="size-3 opacity-50" />
        </button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="start" :side-offset="8" class="w-56">
        <div class="px-3 py-2">
          <p class="text-sm font-medium truncate">{{ projectName }}</p>
          <a
            v-if="urls.workspace"
            :href="urls.workspace"
            class="text-xs text-muted-foreground truncate hover:text-foreground"
          >
            {{ workspaceName }}
          </a>
        </div>
        <DropdownMenuSeparator />
        <DropdownMenuItem as-child>
          <a :href="urls.projectSettings" class="flex items-center gap-2">
            <Settings class="size-4" />
            Project settings
          </a>
        </DropdownMenuItem>
        <DropdownMenuSeparator />
        <DropdownMenuItem as-child>
          <a :href="urls.trash" class="flex items-center gap-2">
            <Trash2 class="size-4" />
            Trash
          </a>
        </DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>

    <!-- Tool switcher -->
    <DropdownMenu v-if="showToolSwitcher">
      <DropdownMenuTrigger as-child>
        <button class="v2-toolbar-btn gap-1.5">
          <component :is="activeToolDef.icon" class="size-4" />
          <span class="hidden xl:inline text-sm font-medium">{{ activeToolDef.label }}</span>
          <ChevronDown class="size-3 opacity-50" />
        </button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="start" :side-offset="8" class="w-48">
        <DropdownMenuItem v-for="tool in otherTools" :key="tool.key" as-child>
          <a :href="urls.tools[tool.key]" class="flex items-center gap-2">
            <component :is="tool.icon" class="size-4" />
            {{ tool.label }}
          </a>
        </DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  </nav>
</template>
