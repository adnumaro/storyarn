<script setup lang="ts">
import {
  FileText,
  GitBranch,
  Image,
  Languages,
  LayoutDashboard,
  Map,
  Settings,
  Trash2,
  UploadCloud,
} from "lucide-vue-next";
import type { Component } from "vue";
import SidebarFrame from "@shell/SidebarFrame.vue";

interface SidebarLink {
  key: string;
  href: string;
  icon: Component;
  labelKey: string;
}

const {
  mainSidebarOpen = false,
  workspaceSlug,
  projectSlug,
  activeItem = "dashboard",
} = defineProps<{
  mainSidebarOpen?: boolean;
  workspaceSlug: string;
  projectSlug: string;
  activeItem?: string;
}>();

const projectBaseUrl = `/workspaces/${workspaceSlug}/projects/${projectSlug}`;

const projectLinks: SidebarLink[] = [
  {
    key: "dashboard",
    href: projectBaseUrl,
    icon: LayoutDashboard,
    labelKey: "layout.project_sidebar.dashboard",
  },
];

const toolLinks: SidebarLink[] = [
  {
    key: "sheets",
    href: `${projectBaseUrl}/sheets`,
    icon: FileText,
    labelKey: "layout.tools.sheets",
  },
  {
    key: "flows",
    href: `${projectBaseUrl}/flows`,
    icon: GitBranch,
    labelKey: "layout.tools.flows",
  },
  {
    key: "scenes",
    href: `${projectBaseUrl}/scenes`,
    icon: Map,
    labelKey: "layout.tools.scenes",
  },
  {
    key: "assets",
    href: `${projectBaseUrl}/assets`,
    icon: Image,
    labelKey: "layout.tools.assets",
  },
  {
    key: "localization",
    href: `${projectBaseUrl}/localization`,
    icon: Languages,
    labelKey: "layout.tools.localization",
  },
];

const settingsLinks: SidebarLink[] = [
  {
    key: "settings",
    href: `${projectBaseUrl}/settings`,
    icon: Settings,
    labelKey: "layout.project_sidebar.settings",
  },
  {
    key: "export-import",
    href: `${projectBaseUrl}/settings/export-import`,
    icon: UploadCloud,
    labelKey: "layout.project_sidebar.export_import",
  },
  {
    key: "trash",
    href: `${projectBaseUrl}/settings/trash`,
    icon: Trash2,
    labelKey: "layout.project_sidebar.trash",
  },
];

function isActive(key: string): boolean {
  return activeItem === key;
}
</script>

<template>
  <SidebarFrame :main-sidebar-open="mainSidebarOpen" active-tool="dashboard">
    <nav class="space-y-5">
      <section class="space-y-1">
        <a
          v-for="item in projectLinks"
          :key="item.key"
          :href="item.href"
          data-phx-link="redirect"
          data-phx-link-state="push"
          :class="[
            'flex items-center gap-2 rounded-md px-2 py-2 text-sm transition-colors',
            isActive(item.key)
              ? 'bg-accent text-accent-foreground font-medium'
              : 'text-muted-foreground hover:bg-accent/50 hover:text-foreground',
          ]"
        >
          <component :is="item.icon" class="size-4 shrink-0" />
          <span class="truncate">{{ $t(item.labelKey) }}</span>
        </a>
      </section>

      <section class="space-y-1">
        <h2 class="px-2 text-xs font-medium text-muted-foreground">
          {{ $t("layout.project_sidebar.tools") }}
        </h2>
        <a
          v-for="item in toolLinks"
          :key="item.key"
          :href="item.href"
          data-phx-link="redirect"
          data-phx-link-state="push"
          :class="[
            'flex items-center gap-2 rounded-md px-2 py-2 text-sm transition-colors',
            isActive(item.key)
              ? 'bg-accent text-accent-foreground font-medium'
              : 'text-muted-foreground hover:bg-accent/50 hover:text-foreground',
          ]"
        >
          <component :is="item.icon" class="size-4 shrink-0" />
          <span class="truncate">{{ $t(item.labelKey) }}</span>
        </a>
      </section>

      <section class="space-y-1">
        <h2 class="px-2 text-xs font-medium text-muted-foreground">
          {{ $t("layout.project_sidebar.project_settings") }}
        </h2>
        <a
          v-for="item in settingsLinks"
          :key="item.key"
          :href="item.href"
          data-phx-link="redirect"
          data-phx-link-state="push"
          :class="[
            'flex items-center gap-2 rounded-md px-2 py-2 text-sm transition-colors',
            isActive(item.key)
              ? 'bg-accent text-accent-foreground font-medium'
              : 'text-muted-foreground hover:bg-accent/50 hover:text-foreground',
          ]"
        >
          <component :is="item.icon" class="size-4 shrink-0" />
          <span class="truncate">{{ $t(item.labelKey) }}</span>
        </a>
      </section>
    </nav>
  </SidebarFrame>
</template>
