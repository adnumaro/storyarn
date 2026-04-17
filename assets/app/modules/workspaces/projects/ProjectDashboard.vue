<script setup lang="ts">
import {
  AlertTriangle,
  Box,
  Clock,
  FileText,
  GitBranch,
  Info,
  Map as MapIcon,
  MessageSquare,
  ScrollText,
  Text,
  Variable,
} from "lucide-vue-next";
import type { Component } from "vue";
import { computed } from "vue";
import { useLive } from "@composables/useLive";
import { formatRelativeTime } from "@utils/date-utils";
import DashboardContent from "@components/layout/DashboardContent.vue";

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
  canEdit = false,
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

const live = useLive();

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
</script>

<template>
  <DashboardContent :loading="loading">
    <!-- Dashboard Content -->
    <div class="space-y-6">
      <!-- Section 1: Stats -->
      <div class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-3">
        <a
          v-for="stat in statCards"
          :key="stat.label"
          :href="stat.href"
          class="rounded-lg border border-border bg-surface p-4 space-y-2 transition-colors"
          :class="stat.href ? 'hover:bg-muted/30 cursor-pointer' : 'cursor-default'"
        >
          <div class="flex items-center gap-2 text-xs text-muted-foreground">
            <component :is="stat.icon" class="size-4" />
            {{ $t(`workspace.project_dashboard.stats.${stat.key}`) }}
          </div>
          <p class="text-2xl font-bold tabular-nums">{{ stat.value }}</p>
        </a>
      </div>

      <!-- Section 2: Content Breakdown -->
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <!-- Node Distribution -->
        <div class="rounded-lg border border-border bg-surface p-4 space-y-3">
          <h2 class="text-sm font-medium">
            {{ $t("workspace.project_dashboard.node_distribution") }}
          </h2>
          <div
            v-if="nodeDist.length === 0"
            class="text-sm text-muted-foreground/50 py-2 text-center"
          >
            {{ $t("workspace.project_dashboard.no_nodes") }}
          </div>
          <div v-else class="space-y-1.5">
            <div
              v-for="item in nodeDist"
              :key="item.label"
              class="flex items-center justify-between text-sm"
            >
              <span class="text-muted-foreground">{{ item.label }}</span>
              <div class="flex items-center gap-2">
                <span class="tabular-nums font-medium">{{ item.count }}</span>
                <span class="text-xs text-muted-foreground/60 tabular-nums w-10 text-right">
                  {{ item.percentage }}%
                </span>
              </div>
            </div>
          </div>
        </div>

        <!-- Top Speakers -->
        <div class="rounded-lg border border-border bg-surface p-4 space-y-3">
          <h2 class="text-sm font-medium">{{ $t("workspace.project_dashboard.top_speakers") }}</h2>
          <div
            v-if="speakers.length === 0"
            class="text-sm text-muted-foreground/50 py-2 text-center"
          >
            {{ $t("workspace.project_dashboard.no_speakers") }}
          </div>
          <div v-else class="space-y-1.5">
            <div
              v-for="item in speakers"
              :key="item.name"
              class="flex items-center justify-between text-sm"
            >
              <a
                v-if="item.href"
                :href="item.href"
                class="text-muted-foreground hover:text-foreground hover:underline transition-colors"
              >
                {{ item.name }}
              </a>
              <span v-else class="text-muted-foreground">{{ item.name }}</span>
              <span class="tabular-nums font-medium">{{ item.count }}</span>
            </div>
          </div>
        </div>
      </div>

      <!-- Section 3: Issues & Warnings -->
      <div v-if="issues.length > 0" class="space-y-2">
        <h2 class="text-sm font-medium">{{ $t("workspace.project_dashboard.issues") }}</h2>
        <div class="rounded-lg border border-border divide-y divide-border">
          <a
            v-for="(issue, i) in issues"
            :key="i"
            :href="issue.href"
            class="flex items-start gap-2 px-3 py-2 text-sm hover:bg-muted/30 transition-colors"
          >
            <AlertTriangle
              v-if="issue.severity === 'warning'"
              class="size-4 text-yellow-500 shrink-0 mt-0.5"
            />
            <Info v-else class="size-4 text-blue-400 shrink-0 mt-0.5" />
            <span class="text-muted-foreground">{{ issue.message }}</span>
          </a>
        </div>
      </div>

      <!-- Section 4: Localization Progress (conditional) -->
      <div
        v-if="localization.length > 0"
        class="rounded-lg border border-border bg-surface p-4 space-y-3"
      >
        <h2 class="text-sm font-medium">
          {{ $t("workspace.project_dashboard.localization_progress") }}
        </h2>
        <div class="space-y-2">
          <a
            v-for="lang in localization"
            :key="lang.name"
            :href="`/workspaces/${workspaceSlug}/projects/${projectSlug}/localization`"
            class="flex items-center gap-3 group hover:bg-muted/30 -mx-2 px-2 py-1 rounded transition-colors"
          >
            <span
              class="text-sm text-muted-foreground w-28 shrink-0 truncate group-hover:text-foreground transition-colors"
            >
              {{ lang.name }}
            </span>
            <div class="flex-1 h-2 rounded-full bg-muted overflow-hidden">
              <div
                class="h-full rounded-full bg-primary transition-all"
                :style="{ width: `${lang.percentage}%` }"
              />
            </div>
            <span class="text-xs text-muted-foreground tabular-nums shrink-0">
              {{ lang.final }} / {{ lang.total }}
            </span>
          </a>
        </div>
      </div>

      <!-- Section 5: Recent Activity -->
      <div class="rounded-lg border border-border bg-surface p-4 space-y-3">
        <h2 class="text-sm font-medium">{{ $t("workspace.project_dashboard.recent_activity") }}</h2>
        <div v-if="activity.length === 0" class="text-sm text-muted-foreground/50 py-2 text-center">
          {{ $t("workspace.project_dashboard.no_activity") }}
        </div>
        <div v-else class="space-y-0.5">
          <div v-for="(item, i) in activity" :key="i" class="flex items-center gap-3 py-1.5">
            <component
              :is="activityIcon(item.type)"
              class="size-4 text-muted-foreground/40 shrink-0"
            />
            <span class="text-sm flex-1 min-w-0">
              <span class="font-medium truncate">{{ item.name }}</span>
              <span class="text-muted-foreground/50">
                &middot;
                {{ activityTypeKeys[item.type] ? $t(activityTypeKeys[item.type]) : item.type }}
              </span>
            </span>
            <span class="text-xs text-muted-foreground/40 shrink-0">
              {{ formatRelativeTime(item.updated_at) }}
            </span>
          </div>
        </div>
      </div>
    </div>
  </DashboardContent>
</template>
