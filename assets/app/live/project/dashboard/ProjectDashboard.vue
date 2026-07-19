<script setup lang="ts">
import {
  Activity,
  AlertTriangle,
  Box,
  ChartNoAxesColumnIncreasing,
  Clock,
  FileText,
  GitBranch,
  Info,
  Languages,
  LayoutDashboard,
  Map as MapIcon,
  MessageSquare,
  ScrollText,
  Text,
  Users,
  Variable,
} from "lucide-vue-next";
import type { Component } from "vue";
import { computed } from "vue";
import { formatRelativeTime } from "@shared/utils/date-utils";
import DashboardContent from "@shell/DashboardContent.vue";
import DashboardPanel from "@shell/DashboardPanel.vue";
import DashboardStatCard from "@shell/DashboardStatCard.vue";

interface ProjectStats {
  sheet_count: number;
  variable_count: number;
  flow_count: number;
  dialogue_count: number;
  scene_count: number;
  total_word_count: number;
}

interface NodeDistItem {
  label: string;
  count: number;
  percentage: number;
}

interface Speaker {
  name: string;
  count: number;
  href?: string;
}

interface Issue {
  severity: string;
  message: string;
  href: string;
}

interface LocalizationLang {
  name: string;
  percentage: number;
  final: number;
  total: number;
}

interface ActivityItem {
  type: string;
  name: string;
  updated_at: string;
}

const {
  stats = null,
  nodeDist = [],
  speakers = [],
  issues = [],
  localization = [],
  activity = [],
  workspaceSlug,
  projectSlug,
  loading = false,
} = defineProps<{
  stats?: ProjectStats | null;
  nodeDist?: NodeDistItem[];
  speakers?: Speaker[];
  issues?: Issue[];
  localization?: LocalizationLang[];
  activity?: ActivityItem[];
  canEdit?: boolean;
  workspaceSlug: string;
  projectSlug: string;
  loading?: boolean;
}>();

const statCards = computed(() => {
  if (!stats) return [];
  return [
    {
      icon: FileText,
      key: "sheets",
      value: stats.sheet_count,
      href: `/workspaces/${workspaceSlug}/projects/${projectSlug}/sheets`,
    },
    {
      icon: Variable,
      key: "variables",
      value: stats.variable_count,
      href: `/workspaces/${workspaceSlug}/projects/${projectSlug}/sheets`,
    },
    {
      icon: GitBranch,
      key: "flows",
      value: stats.flow_count,
      href: `/workspaces/${workspaceSlug}/projects/${projectSlug}/flows`,
    },
    {
      icon: MessageSquare,
      key: "dialogue_lines",
      value: stats.dialogue_count,
      href: `/workspaces/${workspaceSlug}/projects/${projectSlug}/flows`,
    },
    {
      icon: MapIcon,
      key: "scenes",
      value: stats.scene_count,
      href: `/workspaces/${workspaceSlug}/projects/${projectSlug}/scenes`,
    },
    { icon: Text, key: "words", value: stats.total_word_count, href: undefined },
  ];
});

const activityIcons: Record<string, Component> = {
  sheet: FileText,
  flow: GitBranch,
  scene: MapIcon,
  screenplay: ScrollText,
  node: Box,
};

function activityIcon(type: string) {
  return activityIcons[type] || Clock;
}

const activityTypeKeys: Record<string, string> = {
  sheet: "workspace.project_dashboard.activity_types.sheet",
  flow: "workspace.project_dashboard.activity_types.flow",
  scene: "workspace.project_dashboard.activity_types.scene",
  screenplay: "workspace.project_dashboard.activity_types.screenplay",
};

const maxSpeakerCount = computed(() =>
  speakers.reduce((maximum, speaker) => Math.max(maximum, speaker.count), 0),
);
</script>

<template>
  <DashboardContent
    :title="$t('workspace.project_dashboard.title')"
    :subtitle="$t('workspace.project_dashboard.subtitle')"
    :icon="LayoutDashboard"
    :loading="loading"
  >
    <div class="grid grid-cols-2 gap-3 sm:grid-cols-3 xl:grid-cols-6">
      <DashboardStatCard
        v-for="stat in statCards"
        :key="stat.key"
        :icon="stat.icon"
        :label="$t(`workspace.project_dashboard.stats.${stat.key}`)"
        :value="stat.value"
        :href="stat.href"
        :test-id="`project-stat-${stat.key}`"
      />
    </div>

    <div class="grid grid-cols-1 gap-5 lg:grid-cols-2">
      <DashboardPanel
        :title="$t('workspace.project_dashboard.node_distribution')"
        :icon="ChartNoAxesColumnIncreasing"
      >
        <div v-if="nodeDist.length === 0" class="py-7 text-center text-sm text-muted-foreground">
          {{ $t("workspace.project_dashboard.no_nodes") }}
        </div>
        <div v-else class="space-y-3.5">
          <div v-for="item in nodeDist" :key="item.label" class="group">
            <div class="mb-1.5 flex items-center justify-between gap-3 text-sm">
              <span
                class="truncate text-muted-foreground transition-colors group-hover:text-foreground"
              >
                {{ item.label }}
              </span>
              <span class="flex shrink-0 items-baseline gap-2">
                <span class="font-semibold tabular-nums">{{ item.count }}</span>
                <span class="w-9 text-right text-xs text-muted-foreground tabular-nums">
                  {{ item.percentage }}%
                </span>
              </span>
            </div>
            <div class="h-1.5 overflow-hidden rounded-full bg-muted">
              <div
                class="h-full rounded-full bg-linear-to-r from-primary to-project-accent transition-[width] duration-500"
                :style="{ width: `${item.percentage}%` }"
              />
            </div>
          </div>
        </div>
      </DashboardPanel>

      <DashboardPanel :title="$t('workspace.project_dashboard.top_speakers')" :icon="Users">
        <div v-if="speakers.length === 0" class="py-7 text-center text-sm text-muted-foreground">
          {{ $t("workspace.project_dashboard.no_speakers") }}
        </div>
        <div v-else class="space-y-3.5">
          <div v-for="item in speakers" :key="item.name" class="group">
            <div class="mb-1.5 flex items-center justify-between gap-3 text-sm">
              <a
                v-if="item.href"
                :href="item.href"
                data-phx-link="redirect"
                data-phx-link-state="push"
                class="truncate text-muted-foreground transition-colors hover:text-primary"
              >
                {{ item.name }}
              </a>
              <span v-else class="truncate text-muted-foreground">{{ item.name }}</span>
              <span class="shrink-0 font-semibold tabular-nums">{{ item.count }}</span>
            </div>
            <div class="h-1.5 overflow-hidden rounded-full bg-muted">
              <div
                class="h-full rounded-full bg-project-accent/75 transition-[width] duration-500"
                :style="{
                  width: `${maxSpeakerCount > 0 ? (item.count / maxSpeakerCount) * 100 : 0}%`,
                }"
              />
            </div>
          </div>
        </div>
      </DashboardPanel>
    </div>

    <DashboardPanel
      v-if="issues.length > 0"
      :title="$t('workspace.project_dashboard.issues')"
      :icon="AlertTriangle"
      :padded="false"
    >
      <div class="divide-y divide-border/60">
        <a
          v-for="(issue, index) in issues"
          :key="index"
          :href="issue.href"
          data-phx-link="redirect"
          data-phx-link-state="push"
          class="group flex items-start gap-3 px-4 py-3 text-sm transition-colors hover:bg-primary/[0.035] sm:px-5"
        >
          <span
            :class="[
              'mt-0.5 grid size-7 shrink-0 place-items-center rounded-lg',
              issue.severity === 'warning'
                ? 'bg-amber-500/10 text-amber-500'
                : 'bg-sky-500/10 text-sky-500',
            ]"
          >
            <AlertTriangle v-if="issue.severity === 'warning'" class="size-3.5" />
            <Info v-else class="size-3.5" />
          </span>
          <span
            class="leading-6 text-muted-foreground transition-colors group-hover:text-foreground"
          >
            {{ issue.message }}
          </span>
        </a>
      </div>
    </DashboardPanel>

    <DashboardPanel
      v-if="localization.length > 0"
      :title="$t('workspace.project_dashboard.localization_progress')"
      :icon="Languages"
    >
      <div class="space-y-3">
        <a
          v-for="lang in localization"
          :key="lang.name"
          :href="`/workspaces/${workspaceSlug}/projects/${projectSlug}/localization`"
          data-phx-link="redirect"
          data-phx-link-state="push"
          class="group flex items-center gap-3 rounded-xl px-2 py-2 transition-colors hover:bg-primary/[0.04]"
        >
          <span
            class="w-28 shrink-0 truncate text-sm font-medium text-muted-foreground transition-colors group-hover:text-foreground"
          >
            {{ lang.name }}
          </span>
          <div class="h-2 flex-1 overflow-hidden rounded-full bg-muted">
            <div
              class="h-full rounded-full bg-linear-to-r from-primary to-project-accent transition-[width] duration-500"
              :style="{ width: `${lang.percentage}%` }"
            />
          </div>
          <span class="shrink-0 text-xs text-muted-foreground tabular-nums">
            {{ lang.final }} / {{ lang.total }}
          </span>
        </a>
      </div>
    </DashboardPanel>

    <DashboardPanel :title="$t('workspace.project_dashboard.recent_activity')" :icon="Activity">
      <div v-if="activity.length === 0" class="py-7 text-center text-sm text-muted-foreground">
        {{ $t("workspace.project_dashboard.no_activity") }}
      </div>
      <div v-else class="divide-y divide-border/50">
        <div
          v-for="(item, index) in activity"
          :key="index"
          class="flex items-center gap-3 py-3 first:pt-0 last:pb-0"
        >
          <span class="grid size-8 shrink-0 place-items-center rounded-lg bg-muted/70 text-primary">
            <component :is="activityIcon(item.type)" class="size-3.5" />
          </span>
          <span class="min-w-0 flex-1 text-sm">
            <span class="font-medium">{{ item.name }}</span>
            <span class="text-muted-foreground">
              &middot;
              {{ activityTypeKeys[item.type] ? $t(activityTypeKeys[item.type]) : item.type }}
            </span>
          </span>
          <span class="shrink-0 text-xs text-muted-foreground">
            {{ formatRelativeTime(item.updated_at) }}
          </span>
        </div>
      </div>
    </DashboardPanel>
  </DashboardContent>
</template>
