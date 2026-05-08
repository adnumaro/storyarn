<script setup lang="ts">
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
} from "../components/ui/dropdown-menu";
import ToolbarTooltip from "../components/toolbar/ToolbarTooltip.vue";
import { useLive } from "../composables/useLive";

interface LeftToolbarUrls {
  workspace?: string;
  projectSettings: string;
  trash: string;
  tools: Record<string, string>;
}

const {
  activeTool,
  hasTree = true,
  mainSidebarOpen = false,
  projectName,
  workspaceName,
  showToolSwitcher = true,
  isSuperAdmin = false,
  urls,
} = defineProps<{
  activeTool: string;
  hasTree?: boolean;
  mainSidebarOpen?: boolean;
  projectName: string;
  workspaceName: string;
  showToolSwitcher?: boolean;
  isSuperAdmin?: boolean;
  urls: LeftToolbarUrls;
}>();

const live = useLive();

const toolDefs = [
  { key: "dashboard", icon: LayoutDashboard },
  { key: "sheets", icon: FileText },
  { key: "flows", icon: GitBranch },
  { key: "scenes", icon: Map },
  { key: "screenplays", icon: ScrollText },
  { key: "assets", icon: Image },
  { key: "localization", icon: Languages },
];

const activeToolDef = computed(() => toolDefs.find((t) => t.key === activeTool) || toolDefs[0]);

const otherTools = computed(() => {
  const filtered = toolDefs.filter((t) => t.key !== activeTool);
  if (!isSuperAdmin) {
    return filtered.filter((t) => t.key !== "screenplays");
  }
  return filtered;
});

function toggleMainSidebar() {
  live.pushEvent("main_sidebar_toggle", {});
}
</script>

<template>
  <nav class="flex items-center gap-1 px-1 py-1 surface-panel h-8">
    <!-- Main sidebar toggle -->
    <ToolbarTooltip
      v-if="hasTree"
      :label="
        mainSidebarOpen
          ? $t('layout.left_toolbar.hide_panel')
          : $t('layout.left_toolbar.show_panel')
      "
      side="bottom"
      align="start"
    >
      <button
        type="button"
        :class="['toolbar-btn size-8', mainSidebarOpen && 'bg-accent']"
        @click="toggleMainSidebar"
      >
        <PanelLeft class="size-3.5" />
      </button>
    </ToolbarTooltip>

    <div v-if="hasTree" class="w-px h-5 bg-border" />

    <!-- Project dropdown -->
    <DropdownMenu>
      <DropdownMenuTrigger as-child>
        <button class="toolbar-btn gap-1.5 font-medium max-w-52">
          <Folder class="size-3.5 opacity-60 shrink-0" />
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
            {{ $t("layout.left_toolbar.project_settings") }}
          </a>
        </DropdownMenuItem>
        <DropdownMenuSeparator />
        <DropdownMenuItem as-child>
          <a :href="urls.trash" class="flex items-center gap-2">
            <Trash2 class="size-4" />
            {{ $t("layout.left_toolbar.trash") }}
          </a>
        </DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>

    <!-- Tool switcher -->
    <DropdownMenu v-if="showToolSwitcher">
      <DropdownMenuTrigger as-child>
        <button class="toolbar-btn gap-1.5">
          <component :is="activeToolDef.icon" class="size-3.5" />
          <span class="hidden xl:inline text-sm font-medium">{{
            $t(`layout.tools.${activeToolDef.key}`)
          }}</span>
          <ChevronDown class="size-3 opacity-50" />
        </button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="start" :side-offset="8" class="w-48">
        <DropdownMenuItem v-for="tool in otherTools" :key="tool.key" as-child>
          <a
            :href="urls.tools[tool.key]"
            data-phx-link="redirect"
            data-phx-link-state="push"
            class="flex items-center gap-2"
          >
            <component :is="tool.icon" class="size-4" />
            {{ $t(`layout.tools.${tool.key}`) }}
          </a>
        </DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  </nav>
</template>
