<script setup lang="ts">
import { computed } from "vue";
import type { Component } from "vue";
import { useI18n } from "vue-i18n";
import {
  Archive,
  ChevronLeft,
  GitBranch,
  Languages,
  Link,
  Menu,
  Package,
  Settings,
  ShieldCheck,
  Trash2,
  User,
  Users,
} from "lucide-vue-next";
import LiveLink from "@components/navigation/LiveLink.vue";

interface SettingsItem {
  label: string;
  path: string;
  icon: string;
}

interface SettingsSection {
  label: string;
  items: SettingsItem[];
}

interface SettingsWorkspace {
  id: number;
  label?: string;
  name: string;
  slug: string;
}

interface SettingsProject {
  id: number;
  name: string;
  slug: string;
}

const {
  currentPath,
  workspaces = [],
  managedWorkspaceSlugs = [],
  workspace = null,
  project = null,
  title = null,
  subtitle = null,
} = defineProps<{
  currentPath: string;
  workspaces?: SettingsWorkspace[];
  managedWorkspaceSlugs?: string[];
  workspace?: SettingsWorkspace | null;
  project?: SettingsProject | null;
  title?: string | null;
  subtitle?: string | null;
}>();

const { t } = useI18n();

const iconMap: Record<string, Component> = {
  archive: Archive,
  "chevron-left": ChevronLeft,
  "git-branch": GitBranch,
  languages: Languages,
  link: Link,
  menu: Menu,
  package: Package,
  settings: Settings,
  "shield-check": ShieldCheck,
  "trash-2": Trash2,
  user: User,
  users: Users,
};

const navIcon = (name: string): Component => iconMap[name] ?? Settings;

const projectSettingsBasePath = computed(() => {
  if (!workspace || !project) return null;
  return `/workspaces/${workspace.slug}/projects/${project.slug}/settings`;
});

const backPath = computed(() => {
  if (!workspace || !project) return "/workspaces";
  return `/workspaces/${workspace.slug}/projects/${project.slug}`;
});

const backLabel = computed(() => {
  if (!workspace || !project) return t("settings.nav.back_to_app");
  return t("project_settings.nav.back_to_project");
});

const sections = computed<SettingsSection[]>(() => {
  if (projectSettingsBasePath.value) {
    const basePath = projectSettingsBasePath.value;

    return [
      {
        label: t("project_settings.nav.sections.general"),
        items: [
          { label: t("project_settings.nav.items.general"), path: basePath, icon: "settings" },
          {
            label: t("project_settings.nav.items.version_control"),
            path: `${basePath}/version-control`,
            icon: "git-branch",
          },
        ],
      },
      {
        label: t("project_settings.nav.sections.integrations"),
        items: [
          {
            label: t("project_settings.nav.items.localization"),
            path: `${basePath}/localization`,
            icon: "languages",
          },
        ],
      },
      {
        label: t("project_settings.nav.sections.administration"),
        items: [
          {
            label: t("project_settings.nav.items.members"),
            path: `${basePath}/members`,
            icon: "users",
          },
          {
            label: t("project_settings.nav.items.snapshots"),
            path: `${basePath}/snapshots`,
            icon: "archive",
          },
          {
            label: t("project_settings.nav.items.import_export"),
            path: `${basePath}/export-import`,
            icon: "package",
          },
          {
            label: t("project_settings.nav.items.trash"),
            path: `${basePath}/trash`,
            icon: "trash-2",
          },
        ],
      },
    ];
  }

  const managedWorkspaceSet = new Set(managedWorkspaceSlugs);
  const managedWorkspaces = workspaces.filter((workspace) =>
    managedWorkspaceSet.has(workspace.slug),
  );

  return [
    {
      label: t("settings.nav.sections.account"),
      items: [
        { label: t("settings.nav.items.profile"), path: "/users/settings", icon: "user" },
        {
          label: t("settings.nav.items.security"),
          path: "/users/settings/security",
          icon: "shield-check",
        },
        {
          label: t("settings.nav.items.connected_accounts"),
          path: "/users/settings/connections",
          icon: "link",
        },
      ],
    },
    ...managedWorkspaces.map((workspace) => ({
      label: workspace.name,
      items: [
        {
          label: t("settings.nav.items.workspace_general"),
          path: `/users/settings/workspaces/${workspace.slug}/general`,
          icon: "settings",
        },
        {
          label: t("settings.nav.items.workspace_members"),
          path: `/users/settings/workspaces/${workspace.slug}/members`,
          icon: "users",
        },
        {
          label: t("settings.nav.items.deleted_projects"),
          path: `/users/settings/workspaces/${workspace.slug}/deleted-projects`,
          icon: "trash-2",
        },
      ],
    })),
  ];
});
</script>

<template>
  <div
    class="flex h-screen w-screen overflow-hidden bg-linear-to-br from-background via-background to-muted/40 dark:to-muted/10"
  >
    <input id="settings-sidebar-check" type="checkbox" class="peer hidden" />

    <label
      for="settings-sidebar-check"
      class="fixed inset-0 bg-background/80 backdrop-blur-sm z-30 hidden peer-checked:block lg:hidden cursor-pointer"
    />

    <div class="absolute top-3 left-3 z-20 lg:hidden">
      <label
        for="settings-sidebar-check"
        class="inline-flex items-center justify-center size-9 rounded-md bg-background border border-border shadow-sm hover:bg-accent transition-colors cursor-pointer text-muted-foreground"
      >
        <Menu class="size-5" />
      </label>
    </div>

    <aside
      :class="[
        'flex-none w-[252px] surface-panel flex flex-col z-40 shrink-0 overflow-hidden rounded-lg',
        'fixed lg:relative top-3 bottom-3 left-3 lg:top-0 lg:bottom-0 lg:left-0 h-[calc(100vh-1.5rem)] lg:h-auto',
        'lg:ml-3 lg:my-3',
        'transition-transform duration-200',
        '-translate-x-[calc(100%+1rem)] peer-checked:translate-x-0 lg:translate-x-0',
      ]"
    >
      <div class="px-2 pt-3 pb-3 border-b border-border/10">
        <LiveLink
          :to="backPath"
          class="flex items-center gap-2 px-2 py-1.5 rounded-lg text-sm font-medium text-foreground/70 hover:bg-black/5 hover:text-foreground dark:hover:bg-white/5 transition-colors"
        >
          <ChevronLeft class="size-4" />
          {{ backLabel }}
        </LiveLink>
      </div>

      <nav class="flex-1 overflow-y-auto p-3 space-y-5">
        <div v-for="section in sections" :key="section.label">
          <h3 class="text-xs font-semibold uppercase text-foreground/50 px-2 mb-2 tracking-wider">
            {{ section.label }}
          </h3>
          <ul class="space-y-0.5">
            <li v-for="item in section.items" :key="item.path">
              <LiveLink
                :to="item.path"
                :class="[
                  'flex items-center gap-3 px-2 py-2 rounded-lg text-sm transition-colors',
                  currentPath === item.path &&
                    'bg-black/5 dark:bg-white/10 font-medium text-foreground',
                  currentPath !== item.path &&
                    'text-foreground/80 hover:bg-black/5 dark:hover:bg-white/5 hover:text-foreground',
                ]"
              >
                <component :is="navIcon(item.icon)" class="size-4 opacity-70" />
                {{ item.label }}
              </LiveLink>
            </li>
          </ul>
        </div>
      </nav>
    </aside>

    <main class="flex-1 min-w-0 overflow-y-auto bg-background p-4 pt-16 lg:px-8 lg:py-3 min-vh-100">
      <div class="max-w-3xl mx-auto lg:mt-5">
        <header v-if="title" class="pb-4">
          <h1 class="text-lg font-semibold leading-8">{{ title }}</h1>
          <p v-if="subtitle" class="text-sm text-muted-foreground">{{ subtitle }}</p>
        </header>

        <div class="mt-8">
          <slot />
        </div>
      </div>
    </main>
  </div>
</template>
