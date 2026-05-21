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
  PanelLeftClose,
  ScrollText,
  Settings,
  Trash2,
} from "lucide-vue-next";
import { computed, onMounted, onUnmounted, ref } from "vue";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@components/ui/dropdown-menu";
import ToolbarTooltip from "@components/toolbar/ToolbarTooltip.vue";
import type { ProjectNavbarContextUrls } from "./projectNavbarTypes";

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
  urls: ProjectNavbarContextUrls;
}>();

const sidebarOpen = ref(mainSidebarOpen);

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
  const open = !sidebarOpen.value;
  sidebarOpen.value = open;
  window.dispatchEvent(new CustomEvent("storyarn:main-sidebar-change", { detail: { open } }));
}

function syncSidebarOpenFromBody() {
  sidebarOpen.value = document.body.dataset.mainSidebarOpen === "1";
}

function handleMainSidebarChange(event: Event) {
  sidebarOpen.value = Boolean((event as CustomEvent<{ open?: boolean }>).detail?.open);
}

onMounted(() => {
  syncSidebarOpenFromBody();
  window.addEventListener("storyarn:main-sidebar-change", handleMainSidebarChange);
});

onUnmounted(() => {
  window.removeEventListener("storyarn:main-sidebar-change", handleMainSidebarChange);
});
</script>

<template>
  <nav class="flex items-center gap-1 px-1 py-1 h-8">
    <!-- Main sidebar toggle -->
    <ToolbarTooltip
      v-if="hasTree"
      :label="
        sidebarOpen
          ? $t('layout.project_navbar_context.hide_panel')
          : $t('layout.project_navbar_context.show_panel')
      "
      side="bottom"
      align="start"
    >
      <button
        type="button"
        :aria-label="
          sidebarOpen
            ? $t('layout.project_navbar_context.hide_panel')
            : $t('layout.project_navbar_context.show_panel')
        "
        :aria-pressed="sidebarOpen"
        :class="['toolbar-btn size-8', sidebarOpen && 'bg-accent']"
        @click="toggleMainSidebar"
      >
        <PanelLeftClose v-if="sidebarOpen" class="size-4" />
        <PanelLeft v-else class="size-4" />
      </button>
    </ToolbarTooltip>

    <div v-if="hasTree" class="w-px h-5 bg-border" />

    <!-- Project dropdown -->
    <DropdownMenu>
      <DropdownMenuTrigger as-child>
        <button
          class="toolbar-btn gap-1.5 font-medium h-8 max-w-52"
          :aria-label="projectName"
          :title="projectName"
        >
          <Folder class="size-4 opacity-60 shrink-0" />
          <span class="hidden xl:inline truncate text-sm">{{ projectName }}</span>
          <ChevronDown class="size-3.5 opacity-50" />
        </button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="start" :side-offset="8" class="w-56">
        <div class="px-3 py-2">
          <p class="text-sm font-medium truncate">{{ projectName }}</p>
          <a
            v-if="urls.workspace"
            :href="urls.workspace"
            data-phx-link="redirect"
            data-phx-link-state="push"
            class="text-xs text-muted-foreground truncate hover:text-foreground"
          >
            {{ workspaceName }}
          </a>
        </div>
        <DropdownMenuSeparator />
        <DropdownMenuItem as-child>
          <a
            :href="urls.projectSettings"
            data-phx-link="redirect"
            data-phx-link-state="push"
            class="flex items-center gap-2"
          >
            <Settings class="size-4" />
            {{ $t("layout.project_navbar_context.project_settings") }}
          </a>
        </DropdownMenuItem>
        <DropdownMenuSeparator />
        <DropdownMenuItem as-child>
          <a
            :href="urls.trash"
            data-phx-link="redirect"
            data-phx-link-state="push"
            class="flex items-center gap-2"
          >
            <Trash2 class="size-4" />
            {{ $t("layout.project_navbar_context.trash") }}
          </a>
        </DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>

    <!-- Tool switcher -->
    <DropdownMenu v-if="showToolSwitcher">
      <DropdownMenuTrigger as-child>
        <button
          class="toolbar-btn h-8 gap-1.5"
          :aria-label="$t(`layout.tools.${activeToolDef.key}`)"
          :title="$t(`layout.tools.${activeToolDef.key}`)"
        >
          <component :is="activeToolDef.icon" class="size-4" />
          <span class="hidden xl:inline text-sm font-medium">{{
            $t(`layout.tools.${activeToolDef.key}`)
          }}</span>
          <ChevronDown class="size-3.5 opacity-50" />
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
