<script setup lang="ts">
import { computed, ref } from "vue";
import type { Component } from "vue";
import { useI18n } from "vue-i18n";
import {
  Archive,
  BookOpen,
  ChevronLeft,
  CircleHelp,
  Gauge,
  GitBranch,
  Languages,
  Link,
  Package,
  PanelLeft,
  PanelLeftClose,
  Plug,
  Settings,
  ShieldCheck,
  Trash2,
  User,
  Users,
} from "lucide-vue-next";
import LiveLink from "@components/navigation/LiveLink.vue";
import OnboardingDialog from "@components/onboarding/OnboardingDialog.vue";
import { useResponsiveSidebar } from "@shared/composables/useResponsiveSidebar";
import { sensitiveSettingsPath } from "@shared/navigation/sensitiveSettingsPath";

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

interface SettingsFeatureFlags {
  aiIntegrations?: boolean;
}

const {
  currentPath,
  workspaces = [],
  workspaceSettingsAccess = {},
  workspace = null,
  project = null,
  title = null,
  subtitle = null,
  onboarding = null,
  sudoGrant = null,
  featureFlags = {},
} = defineProps<{
  currentPath: string;
  workspaces?: SettingsWorkspace[];
  workspaceSettingsAccess?: Record<string, "manage" | "general">;
  workspace?: SettingsWorkspace | null;
  project?: SettingsProject | null;
  title?: string | null;
  subtitle?: string | null;
  onboarding?: { guide: string; autoShow: boolean } | null;
  sudoGrant?: string | null;
  featureFlags?: SettingsFeatureFlags;
}>();

const { t } = useI18n();

const iconMap: Record<string, Component> = {
  archive: Archive,
  "book-open": BookOpen,
  "chevron-left": ChevronLeft,
  gauge: Gauge,
  "git-branch": GitBranch,
  languages: Languages,
  link: Link,
  package: Package,
  plug: Plug,
  settings: Settings,
  "shield-check": ShieldCheck,
  "trash-2": Trash2,
  user: User,
  users: Users,
};

const navIcon = (name: string): Component => iconMap[name] ?? Settings;

const { sidebarOpen, toggleSidebar } = useResponsiveSidebar();
const onboardingDialog = ref<{ openTutorial: () => void } | null>(null);

function showTutorial(): void {
  onboardingDialog.value?.openTutorial();
}

function routePath(path: string): string {
  return path.split("?", 1)[0] ?? path;
}

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
          {
            label: t("project_settings.nav.items.usage_limits"),
            path: `${basePath}/usage-limits`,
            icon: "gauge",
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

  const managedWorkspaces = workspaces.filter(
    (workspace) => workspaceSettingsAccess[workspace.slug] === "manage",
  );
  const readOnlyWorkspaces = workspaces.filter(
    (workspace) => workspaceSettingsAccess[workspace.slug] === "general",
  );

  const accountItems = [
    {
      label: t("settings.nav.items.profile"),
      path: sensitiveSettingsPath("/users/settings", sudoGrant),
      icon: "user",
    },
    {
      label: t("settings.nav.items.security"),
      path: sensitiveSettingsPath("/users/settings/security", sudoGrant),
      icon: "shield-check",
    },
    {
      label: t("settings.nav.items.tutorials"),
      path: "/users/settings/tutorials",
      icon: "book-open",
    },
  ];

  if (featureFlags.aiIntegrations) {
    accountItems.push({
      label: t("settings.nav.items.integrations"),
      path: "/users/settings/integrations",
      icon: "plug",
    });
  }

  return [
    {
      label: t("settings.nav.sections.account"),
      items: accountItems,
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
    ...readOnlyWorkspaces.map((workspace) => ({
      label: workspace.name,
      items: [
        {
          label: t("settings.nav.items.workspace_general"),
          path: `/users/settings/workspaces/${workspace.slug}/general`,
          icon: "settings",
        },
      ],
    })),
  ];
});
</script>

<template>
  <div class="relative h-screen w-screen overflow-hidden bg-surface">
    <aside
      :aria-hidden="!sidebarOpen"
      :inert="!sidebarOpen"
      class="absolute inset-y-0 left-0 z-0 w-[calc(100vw-4rem)] sm:w-63 overflow-hidden flex flex-col"
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
                  currentPath === routePath(item.path) &&
                    'bg-black/5 dark:bg-white/10 font-medium text-foreground',
                  currentPath !== routePath(item.path) &&
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

    <main
      :class="[
        'relative z-10 h-full min-dvh-100 min-w-0 w-full bg-background transition-[margin-left,width,border-radius,box-shadow] duration-300 ease-out will-change-[margin-left,width] flex flex-col overflow-hidden',
        sidebarOpen
          ? 'ml-[calc(100vw-4rem)] w-16 sm:ml-63 sm:w-[calc(100%-15.75rem)] shadow-xl rounded-l-2xl'
          : 'ml-0 w-full',
      ]"
    >
      <div
        class="flex h-12 shrink-0 items-center border-b border-border/70 bg-background/95 px-3 lg:hidden"
      >
        <button
          type="button"
          class="toolbar-btn size-9"
          :aria-label="
            sidebarOpen
              ? $t('layout.main_sidebar.hide_panel')
              : $t('layout.main_sidebar.show_panel')
          "
          :title="
            sidebarOpen
              ? $t('layout.main_sidebar.hide_panel')
              : $t('layout.main_sidebar.show_panel')
          "
          :aria-pressed="sidebarOpen"
          @click="toggleSidebar"
        >
          <PanelLeftClose v-if="sidebarOpen" class="size-4" />
          <PanelLeft v-else class="size-4" />
        </button>
      </div>

      <div class="flex-1 min-h-0 overflow-y-auto p-4 lg:p-8">
        <div class="max-w-3xl mx-auto">
          <header v-if="title" class="flex items-start justify-between gap-4 pb-4">
            <div>
              <h1 class="text-lg font-semibold leading-8">{{ title }}</h1>
              <p v-if="subtitle" class="text-sm text-muted-foreground">{{ subtitle }}</p>
            </div>
            <button
              v-if="onboarding"
              type="button"
              class="inline-flex h-9 shrink-0 items-center gap-2 rounded-lg border border-border px-3 text-sm font-medium text-muted-foreground transition-colors hover:bg-muted hover:text-foreground"
              @click="showTutorial"
            >
              <CircleHelp class="size-4" />
              {{ t("onboarding.common.view_tutorial") }}
            </button>
          </header>

          <div>
            <slot />
          </div>
        </div>
      </div>
    </main>

    <OnboardingDialog
      v-if="onboarding"
      ref="onboardingDialog"
      :guide-key="onboarding.guide"
      :auto-show="onboarding.autoShow"
    />
  </div>
</template>
