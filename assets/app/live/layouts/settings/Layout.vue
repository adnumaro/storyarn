<script setup lang="ts">
import { computed, ref, watch } from "vue";
import type { Component } from "vue";
import { useI18n } from "vue-i18n";
import {
  Archive,
  BookOpen,
  Bot,
  Check,
  ChevronLeft,
  ChevronsUpDown,
  CircleHelp,
  FileUp,
  Gauge,
  GitBranch,
  Languages,
  Lock,
  Menu,
  Package,
  Plug,
  Search,
  Settings,
  ShieldCheck,
  SlidersHorizontal,
  Trash2,
  User,
  Users,
  X,
} from "@lucide/vue";
import LiveLink from "@components/navigation/LiveLink.vue";
import NotificationBell from "@components/notifications/NotificationBell.vue";
import OnboardingDialog from "@components/onboarding/OnboardingDialog.vue";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@components/ui/dropdown-menu";
import { useResponsiveSidebar } from "@shared/composables/useResponsiveSidebar";
import { sensitiveSettingsPath } from "@shared/navigation/sensitiveSettingsPath";

interface SettingsNavWorkspace {
  id: number;
  slug: string;
  name: string;
  access: "manage" | "general";
  owner: boolean;
}

interface SettingsNavProject {
  id: number;
  slug: string;
  name: string;
  workspaceSlug: string;
  access: "owner" | "editor" | "viewer";
}

interface SettingsNavOption {
  id: number;
  slug: string;
  name: string;
}

interface SettingsNav {
  workspace: SettingsNavWorkspace | null;
  workspaces: SettingsNavWorkspace[];
  project: SettingsNavProject | null;
  projects: SettingsNavOption[];
}

interface SettingsItem {
  key: string;
  label: string;
  path: string;
  icon: Component;
  locked: boolean;
  /** Highlight the item for its child routes too (detail pages). */
  matchPrefix?: boolean;
}

interface SettingsSwitcherOption {
  key: string;
  name: string;
  path: string;
  current: boolean;
}

interface SettingsGroup {
  key: string;
  label: string;
  items: SettingsItem[];
  switcher: { label: string; options: SettingsSwitcherOption[] } | null;
}

interface SettingsFeatureFlags {
  aiIntegrations?: boolean;
}

const {
  currentPath,
  settingsNav = null,
  title = null,
  subtitle = null,
  onboarding = null,
  sudoGrant = null,
  featureFlags = {},
} = defineProps<{
  currentPath: string;
  settingsNav?: SettingsNav | null;
  title?: string | null;
  subtitle?: string | null;
  onboarding?: { guide: string; autoShow: boolean } | null;
  sudoGrant?: string | null;
  featureFlags?: SettingsFeatureFlags;
}>();

const { t } = useI18n();

const { sidebarOpen, mobileSidebarOpen, closeSidebar, toggleSidebar } = useResponsiveSidebar();
const onboardingDialog = ref<{ openTutorial: () => void } | null>(null);

function showTutorial(): void {
  onboardingDialog.value?.openTutorial();
}

function openSearch(): void {
  closeSidebar();
  window.dispatchEvent(new CustomEvent("storyarn:open-palette"));
}

function routePath(path: string): string {
  return path.split("?", 1)[0] ?? path;
}

function isActive(item: SettingsItem): boolean {
  const currentRoute = routePath(currentPath);
  const itemRoute = routePath(item.path);

  if (currentRoute === itemRoute) return true;
  return item.matchPrefix === true && currentRoute.startsWith(`${itemRoute}/`);
}

const personalGroup = computed<SettingsGroup>(() => {
  const items: SettingsItem[] = [
    {
      key: "profile",
      label: t("settings.nav.items.profile"),
      path: sensitiveSettingsPath("/users/settings", sudoGrant),
      icon: User,
      locked: false,
    },
    {
      key: "preferences",
      label: t("settings.nav.items.preferences"),
      path: "/users/settings/preferences",
      icon: SlidersHorizontal,
      locked: false,
    },
    {
      key: "security",
      label: t("settings.nav.items.security"),
      path: sensitiveSettingsPath("/users/settings/security", sudoGrant),
      icon: ShieldCheck,
      locked: false,
    },
  ];

  if (featureFlags.aiIntegrations) {
    items.push(
      {
        key: "integrations",
        label: t("settings.nav.items.integrations"),
        path: sensitiveSettingsPath("/users/settings/integrations", sudoGrant),
        icon: Plug,
        locked: false,
        matchPrefix: true,
      },
      {
        key: "ai_team",
        label: t("settings.nav.items.ai_team"),
        path: sensitiveSettingsPath("/users/settings/ai-team", sudoGrant),
        icon: Bot,
        locked: false,
        matchPrefix: true,
      },
    );
  }

  items.push({
    key: "tutorials",
    label: t("settings.nav.items.tutorials"),
    path: "/users/settings/tutorials",
    icon: BookOpen,
    locked: false,
  });

  return {
    key: "personal",
    label: t("settings.nav.sections.personal"),
    items,
    switcher: null,
  };
});

const workspaceGroup = computed<SettingsGroup | null>(() => {
  const workspace = settingsNav?.workspace;
  if (!workspace) return null;

  const base = `/users/settings/workspaces/${workspace.slug}`;
  const general: SettingsItem = {
    key: "workspace_general",
    label: t("settings.nav.items.workspace_general"),
    path: `${base}/general`,
    icon: Settings,
    locked: !workspace.owner,
  };

  const items: SettingsItem[] =
    workspace.access === "manage"
      ? [
          general,
          {
            key: "workspace_members",
            label: t("settings.nav.items.workspace_members"),
            path: `${base}/members`,
            icon: Users,
            locked: false,
          },
          ...(featureFlags.aiIntegrations
            ? [
                {
                  key: "workspace_ai",
                  label: t("settings.nav.items.workspace_ai"),
                  path: `${base}/ai`,
                  icon: Bot,
                  locked: !workspace.owner,
                },
              ]
            : []),
          {
            key: "workspace_imports",
            label: t("settings.nav.items.workspace_imports"),
            path: `${base}/imports`,
            icon: FileUp,
            locked: false,
          },
          {
            key: "deleted_projects",
            label: t("settings.nav.items.deleted_projects"),
            path: `${base}/deleted-projects`,
            icon: Trash2,
            locked: false,
          },
        ]
      : [general];

  const options = (settingsNav?.workspaces ?? []).map((option) => ({
    key: option.slug,
    name: option.name,
    path: `/users/settings/workspaces/${option.slug}/general`,
    current: option.slug === workspace.slug,
  }));

  return {
    key: "workspace",
    label: workspace.name,
    items,
    switcher: options.length > 1 ? { label: t("settings.nav.switch_workspace"), options } : null,
  };
});

const projectGroup = computed<SettingsGroup | null>(() => {
  const project = settingsNav?.project;
  if (!project || project.access === "viewer") return null;

  const base = `/workspaces/${project.workspaceSlug}/projects/${project.slug}/settings`;
  const ownerOnly = project.access !== "owner";
  const item = (
    key: string,
    labelKey: string,
    suffix: string,
    icon: Component,
    locked: boolean,
  ): SettingsItem => ({
    key,
    label: t(`project_settings.nav.items.${labelKey}`),
    path: `${base}${suffix}`,
    icon,
    locked,
  });

  const items: SettingsItem[] = [
    item("project_general", "general", "", Settings, ownerOnly),
    item("project_members", "members", "/members", Users, ownerOnly),
    item("project_version_control", "version_control", "/version-control", GitBranch, ownerOnly),
    item("project_snapshots", "snapshots", "/snapshots", Archive, ownerOnly),
    item("project_import_export", "import_export", "/export-import", Package, false),
    item("project_trash", "trash", "/trash", Trash2, false),
    item("project_localization", "localization", "/localization", Languages, ownerOnly),
    item("project_usage_limits", "usage_limits", "/usage-limits", Gauge, ownerOnly),
  ];

  const options = (settingsNav?.projects ?? []).map((option) => ({
    key: option.slug,
    name: option.name,
    path: `/workspaces/${project.workspaceSlug}/projects/${option.slug}/settings`,
    current: option.slug === project.slug,
  }));

  return {
    key: "project",
    label: project.name,
    items,
    switcher: options.length > 1 ? { label: t("settings.nav.switch_project"), options } : null,
  };
});

const groups = computed<SettingsGroup[]>(() =>
  [personalGroup.value, workspaceGroup.value, projectGroup.value].filter(
    (group): group is SettingsGroup => group !== null,
  ),
);

const activeGroup = computed<SettingsGroup | null>(
  () => groups.value.find((group) => group.items.some(isActive)) ?? null,
);

const activeItem = computed<SettingsItem | null>(
  () => activeGroup.value?.items.find(isActive) ?? null,
);

const backPath = computed(() => {
  const project = settingsNav?.project;
  if (project) return `/workspaces/${project.workspaceSlug}/projects/${project.slug}`;

  const workspace = settingsNav?.workspace;
  if (workspace && activeGroup.value?.key === "workspace") return `/workspaces/${workspace.slug}`;

  return "/workspaces";
});

const scopeLabel = computed(() => activeGroup.value?.label ?? t("settings.nav.sections.personal"));
const pageLabel = computed(() => title ?? activeItem.value?.label ?? "");

const wide = computed(() => {
  const route = routePath(currentPath);
  return route === "/users/settings/ai-team" || route.endsWith("/settings/export-import");
});

const contentWidthClass = computed(() => (wide.value ? "max-w-[960px]" : "max-w-[720px]"));

watch(
  () => currentPath,
  () => closeSidebar(),
);
</script>

<template>
  <div class="flex h-dvh w-full overflow-hidden bg-background text-foreground">
    <div
      v-if="mobileSidebarOpen"
      class="fixed inset-0 z-30 bg-black/55 lg:hidden"
      aria-hidden="true"
      @click="closeSidebar"
    />

    <aside
      :aria-hidden="!sidebarOpen"
      :inert="!sidebarOpen"
      :class="[
        'fixed inset-y-0 left-0 z-40 flex w-[300px] flex-col overflow-hidden border-r border-border bg-card text-[13px] shadow-2xl transition-transform duration-200 ease-out',
        'lg:static lg:z-auto lg:w-60 lg:shrink-0 lg:translate-x-0 lg:shadow-none',
        mobileSidebarOpen ? 'translate-x-0' : '-translate-x-full',
      ]"
    >
      <div class="flex items-center gap-2 px-4 pb-2.5 pt-4">
        <LiveLink
          :to="backPath"
          class="flex min-w-0 items-center gap-2 text-[13px] text-muted-foreground transition-colors hover:text-foreground"
        >
          <ChevronLeft class="size-3.5 shrink-0" />
          <span class="truncate">{{ t("settings.nav.back_to_app") }}</span>
        </LiveLink>
        <button
          type="button"
          class="ml-auto inline-flex size-8 items-center justify-center rounded-lg text-muted-foreground hover:bg-accent hover:text-foreground lg:hidden"
          :aria-label="t('settings.nav.close_navigation')"
          @click="closeSidebar"
        >
          <X class="size-[18px]" />
        </button>
      </div>

      <div class="px-3 pb-1.5">
        <button
          type="button"
          class="flex w-full items-center gap-2 rounded-md border border-border bg-background px-2.5 py-1.5 text-left text-muted-foreground transition-colors hover:text-foreground"
          @click="openSearch"
        >
          <Search class="size-3.5 shrink-0" />
          <span class="min-w-0 flex-1 truncate">{{ t("settings.nav.search") }}</span>
          <kbd class="rounded border border-border px-1 font-sans text-[11px]">⌘K</kbd>
        </button>
      </div>

      <nav class="flex-1 overflow-y-auto px-3 pb-3 pt-1">
        <div v-for="group in groups" :key="group.key" :data-settings-group="group.key">
          <div class="flex items-center gap-1.5 px-2.5 pb-1 pt-3.5 text-xs text-muted-foreground">
            <DropdownMenu v-if="group.switcher">
              <DropdownMenuTrigger as-child>
                <button
                  type="button"
                  class="flex min-w-0 flex-1 items-center gap-1.5 rounded text-left text-xs text-muted-foreground transition-colors hover:text-foreground"
                  :title="group.switcher.label"
                >
                  <span class="min-w-0 flex-1 truncate">{{ group.label }}</span>
                  <ChevronsUpDown class="size-3 shrink-0" />
                </button>
              </DropdownMenuTrigger>
              <DropdownMenuContent align="start" :side-offset="4" class="w-56">
                <DropdownMenuLabel>{{ group.switcher.label }}</DropdownMenuLabel>
                <DropdownMenuSeparator />
                <DropdownMenuItem
                  v-for="option in group.switcher.options"
                  :key="option.key"
                  as-child
                >
                  <a
                    :href="option.path"
                    data-phx-link="redirect"
                    data-phx-link-state="push"
                    class="flex items-center gap-2"
                  >
                    <span class="min-w-0 flex-1 truncate">{{ option.name }}</span>
                    <Check v-if="option.current" class="size-3.5 shrink-0" />
                  </a>
                </DropdownMenuItem>
              </DropdownMenuContent>
            </DropdownMenu>
            <span v-else class="min-w-0 flex-1 truncate">{{ group.label }}</span>
          </div>

          <ul class="space-y-px">
            <li v-for="item in group.items" :key="item.key">
              <LiveLink
                :to="item.path"
                :class="[
                  'flex items-center gap-2 rounded-md px-2.5 py-[5px] transition-colors',
                  isActive(item)
                    ? 'bg-accent font-medium text-foreground'
                    : 'text-foreground/85 hover:bg-accent/60 hover:text-foreground',
                ]"
                :aria-current="isActive(item) ? 'page' : undefined"
                @click="closeSidebar"
              >
                <component
                  :is="item.icon"
                  :class="['size-[15px] shrink-0', isActive(item) ? '' : 'text-muted-foreground']"
                />
                <span class="min-w-0 flex-1 truncate">{{ item.label }}</span>
                <Lock
                  v-if="item.locked"
                  class="size-3 shrink-0 text-muted-foreground"
                  data-settings-locked
                  :aria-label="t('settings.nav.locked')"
                  :title="t('settings.nav.locked')"
                />
              </LiveLink>
            </li>
          </ul>
        </div>
      </nav>
    </aside>

    <div class="relative flex min-w-0 flex-1 flex-col">
      <div class="absolute right-3 top-2.5 z-10 lg:right-4 lg:top-4">
        <NotificationBell />
      </div>

      <header
        class="flex h-14 shrink-0 items-center gap-3 border-b border-border bg-card pl-3 pr-14 lg:hidden"
      >
        <button
          type="button"
          class="inline-flex size-9 items-center justify-center rounded-lg text-foreground hover:bg-accent"
          :aria-label="
            mobileSidebarOpen
              ? t('settings.nav.close_navigation')
              : t('settings.nav.open_navigation')
          "
          :aria-pressed="mobileSidebarOpen"
          @click="toggleSidebar"
        >
          <Menu class="size-5" />
        </button>
        <div class="min-w-0 flex-1">
          <div class="truncate text-[11px] text-muted-foreground">{{ scopeLabel }}</div>
          <div class="truncate text-[15px] font-semibold leading-tight">{{ pageLabel }}</div>
        </div>
      </header>

      <main class="min-h-0 flex-1 overflow-y-auto">
        <div class="px-4 py-5 lg:px-12 lg:py-14">
          <div :class="[contentWidthClass, 'mx-auto']" data-testid="settings-content">
            <header v-if="title" class="flex items-start justify-between gap-4 pb-6">
              <div>
                <h1 class="text-2xl font-semibold leading-tight tracking-[-0.01em]">{{ title }}</h1>
                <p v-if="subtitle" class="mt-1 text-sm text-muted-foreground">{{ subtitle }}</p>
              </div>
              <button
                v-if="onboarding"
                type="button"
                class="inline-flex h-8 shrink-0 items-center gap-2 rounded-md border border-border px-3 text-sm font-medium text-muted-foreground transition-colors hover:bg-muted hover:text-foreground"
                @click="showTutorial"
              >
                <CircleHelp class="size-4" />
                {{ t("onboarding.common.view_tutorial") }}
              </button>
            </header>

            <slot />
          </div>
        </div>
      </main>
    </div>

    <OnboardingDialog
      v-if="onboarding"
      ref="onboardingDialog"
      :guide-key="onboarding.guide"
      :auto-show="onboarding.autoShow"
    />
  </div>
</template>
