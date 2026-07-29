<script setup lang="ts">
import {
  AlertTriangle,
  Box,
  CircleCheck,
  CircleX,
  Clock,
  FileText,
  GitBranch,
  LoaderCircle,
  Map as MapIcon,
  MessageSquare,
  Text,
  Variable,
} from "@lucide/vue";
import type { Component } from "vue";
import { computed } from "vue";
import { useI18n } from "vue-i18n";
import { Button } from "@components/ui/button";
import { useLive } from "@shared/composables/useLive";
import { formatRelativeTime } from "@shared/utils/date-utils";
import DashboardContent from "@shell/DashboardContent.vue";
import type { DashboardLoadStatus } from "@components/dashboard/types";

interface ProjectStats {
  sheet_count: number;
  variable_count: number;
  flow_count: number;
  dialogue_count: number;
  scene_count: number;
  total_word_count: number;
}

interface ToolHealthCounts {
  error: number;
  warning: number;
  info: number;
  actionable: number;
}

type ToolKey = "flows" | "sheets" | "scenes";

type ToolHealth = Record<ToolKey, ToolHealthCounts>;

// "clean" is not a health severity — it is the absence of actionable findings,
// so it is deliberately not `HealthStatusSeverity`.
type ToolHealthState = "error" | "warning" | "clean";

interface ToolHealthCard {
  tool: ToolKey;
  icon: Component;
  href: string;
  counts: ToolHealthCounts;
  clean: boolean;
  state: ToolHealthState;
}

interface ActivityItem {
  type: string;
  name: string;
  updated_at: string;
}

const {
  stats = null,
  activity = [],
  toolHealth = null,
  overviewStatus = "loading",
  issuesStatus = "loading",
  workspaceSlug,
  projectSlug,
} = defineProps<{
  stats?: ProjectStats | null;
  activity?: ActivityItem[];
  toolHealth?: ToolHealth | null;
  overviewStatus?: DashboardLoadStatus;
  issuesStatus?: DashboardLoadStatus;
  canEdit?: boolean;
  workspaceSlug: string;
  projectSlug: string;
}>();

const { t } = useI18n();
const live = useLive();

const projectPath = computed(() => `/workspaces/${workspaceSlug}/projects/${projectSlug}`);

const statCards = computed(() => {
  if (!stats) return [];
  return [
    {
      icon: FileText,
      key: "sheets",
      value: stats.sheet_count,
      href: `${projectPath.value}/sheets`,
    },
    {
      icon: Variable,
      key: "variables",
      value: stats.variable_count,
      href: `${projectPath.value}/sheets`,
    },
    { icon: GitBranch, key: "flows", value: stats.flow_count, href: `${projectPath.value}/flows` },
    {
      icon: MessageSquare,
      key: "dialogue_lines",
      value: stats.dialogue_count,
      href: `${projectPath.value}/flows`,
    },
    { icon: MapIcon, key: "scenes", value: stats.scene_count, href: `${projectPath.value}/scenes` },
    { icon: Text, key: "words", value: stats.total_word_count, href: undefined },
  ];
});

const toolIcons: Record<ToolKey, Component> = {
  flows: GitBranch,
  sheets: FileText,
  scenes: MapIcon,
};

const toolOrder: ToolKey[] = ["flows", "sheets", "scenes"];

// Only errors and warnings are reported. An `info` finding describes valid
// content, so a tool that has nothing but those is up to date — which is why
// `clean` is driven by `actionable`, never by the raw finding total.
function healthState(counts: ToolHealthCounts): ToolHealthState {
  if (counts.error > 0) return "error";
  if (counts.warning > 0) return "warning";
  return "clean";
}

const healthCards = computed<ToolHealthCard[]>(() => {
  if (!toolHealth) return [];

  return toolOrder.map((tool) => {
    const counts = toolHealth[tool] ?? { error: 0, warning: 0, info: 0, actionable: 0 };
    const state = healthState(counts);

    return {
      tool,
      icon: toolIcons[tool],
      href: `${projectPath.value}/${tool}`,
      counts,
      clean: counts.actionable === 0,
      state,
    };
  });
});

const stateIcons: Record<ToolHealthState, Component> = {
  error: CircleX,
  warning: AlertTriangle,
  clean: CircleCheck,
};

const stateClasses: Record<ToolHealthState, string> = {
  error: "text-red-500",
  warning: "text-yellow-500",
  clean: "text-emerald-500",
};

const overviewFailure = computed(() => {
  if (overviewStatus === "error") {
    return {
      kind: "error" as const,
      message: t("common.dashboard.overview_load_failed"),
      retryLabel: t("common.dashboard.retry"),
    };
  }

  if (overviewStatus === "stale") {
    return {
      kind: "stale" as const,
      message: t("common.dashboard.overview_stale"),
      retryLabel: t("common.dashboard.retry"),
    };
  }

  return undefined;
});

const activityIcons: Record<string, Component> = {
  sheet: FileText,
  flow: GitBranch,
  scene: MapIcon,
  node: Box,
};

function activityIcon(type: string) {
  return activityIcons[type] || Clock;
}

const activityTypeKeys: Record<string, string> = {
  sheet: "workspace.project_dashboard.activity_types.sheet",
  flow: "workspace.project_dashboard.activity_types.flow",
  scene: "workspace.project_dashboard.activity_types.scene",
};

// `stale` keeps the previously loaded rows on screen; `loading` and `error`
// have nothing truthful to show.
const showActivity = computed(() => overviewStatus !== "loading" && overviewStatus !== "error");

function retryOverview(): void {
  live.pushEvent("retry_dashboard_overview");
}

function retryHealth(): void {
  live.pushEvent("retry_dashboard_issues");
}
</script>

<template>
  <DashboardContent
    :loading="overviewStatus === 'loading'"
    :loading-label="$t('common.dashboard.loading_overview')"
    :failure="overviewFailure"
    @retry="retryOverview"
  >
    <!-- Project totals -->
    <div class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-3">
      <a
        v-for="stat in statCards"
        :key="stat.key"
        :href="stat.href"
        :data-testid="`project-stat-${stat.key}`"
        data-phx-link="redirect"
        data-phx-link-state="push"
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

    <template #supplementary>
      <!-- Per-tool health -->
      <section
        data-testid="project-tool-health"
        class="space-y-3"
        :aria-busy="issuesStatus === 'loading' || issuesStatus === 'refreshing'"
      >
        <div class="flex min-h-6 items-center justify-between gap-3">
          <h2 class="text-sm font-medium">
            {{ $t("workspace.project_dashboard.health.title") }}
          </h2>
          <div
            v-if="issuesStatus === 'refreshing'"
            data-testid="project-health-refreshing"
            class="inline-flex items-center gap-1.5 text-xs text-muted-foreground"
            role="status"
            aria-live="polite"
          >
            <LoaderCircle class="size-3.5 animate-spin" aria-hidden="true" />
            <span>{{ $t("common.dashboard.refreshing_issues") }}</span>
          </div>
        </div>

        <div
          v-if="issuesStatus === 'loading'"
          data-testid="project-health-loading"
          class="flex items-center justify-center rounded-lg border border-border py-8"
          role="status"
          aria-live="polite"
        >
          <LoaderCircle class="size-5 animate-spin text-muted-foreground" aria-hidden="true" />
          <span class="sr-only">{{ $t("common.dashboard.loading_issues") }}</span>
        </div>

        <div
          v-else-if="issuesStatus === 'error'"
          data-testid="project-health-error"
          class="flex flex-col items-center justify-center gap-3 rounded-lg border border-destructive/30 bg-destructive/5 px-4 py-8 text-center"
          role="alert"
        >
          <p class="text-sm text-destructive">
            {{ $t("common.dashboard.issues_load_failed") }}
          </p>
          <Button
            variant="outline"
            size="sm"
            data-testid="project-health-retry"
            @click="retryHealth"
          >
            {{ $t("common.dashboard.retry") }}
          </Button>
        </div>

        <template v-else>
          <div
            v-if="issuesStatus === 'stale'"
            data-testid="project-health-stale"
            class="flex items-center justify-between gap-3 rounded-lg border border-amber-500/30 bg-amber-500/5 px-4 py-3"
            role="status"
            aria-live="polite"
          >
            <p class="text-sm text-amber-700 dark:text-amber-300">
              {{ $t("common.dashboard.issues_stale") }}
            </p>
            <Button
              variant="outline"
              size="sm"
              class="shrink-0"
              data-testid="project-health-retry"
              @click="retryHealth"
            >
              {{ $t("common.dashboard.retry") }}
            </Button>
          </div>

          <div class="grid grid-cols-1 sm:grid-cols-3 gap-3">
            <a
              v-for="card in healthCards"
              :key="card.tool"
              :href="card.href"
              :data-testid="`project-health-${card.tool}`"
              :data-state="card.state"
              data-phx-link="redirect"
              data-phx-link-state="push"
              class="rounded-lg border border-border bg-surface p-4 space-y-2 transition-colors hover:bg-muted/30"
            >
              <div class="flex items-center justify-between gap-2">
                <span class="flex items-center gap-2 text-xs text-muted-foreground">
                  <component :is="card.icon" class="size-4" />
                  {{ $t(`workspace.project_dashboard.health.tools.${card.tool}`) }}
                </span>
                <component
                  :is="stateIcons[card.state]"
                  :class="['size-4 shrink-0', stateClasses[card.state]]"
                  aria-hidden="true"
                />
              </div>

              <p v-if="card.clean" class="text-sm font-medium">
                {{ $t("workspace.project_dashboard.health.clean") }}
              </p>
              <template v-else>
                <p class="text-sm font-medium">
                  {{
                    $t("workspace.project_dashboard.health.issues", {
                      count: card.counts.actionable,
                    })
                  }}
                </p>
                <p class="text-xs text-muted-foreground tabular-nums">
                  <span v-if="card.counts.error > 0">
                    {{
                      $t("workspace.project_dashboard.health.errors", {
                        count: card.counts.error,
                      })
                    }}
                  </span>
                  <span v-if="card.counts.error > 0 && card.counts.warning > 0"> &middot; </span>
                  <span v-if="card.counts.warning > 0">
                    {{
                      $t("workspace.project_dashboard.health.warnings", {
                        count: card.counts.warning,
                      })
                    }}
                  </span>
                </p>
              </template>
            </a>
          </div>
        </template>
      </section>

      <!-- Recent activity — loaded by the OVERVIEW, so it is gated on the
           overview having data. Rendering its "no activity yet" empty state
           next to an overview error told the reader the project was empty when
           the truth was that nothing had loaded.

           It sits in #supplementary, after health, purely for order: health is
           the actionable summary and belongs directly under the totals, not
           below a ten-row list. DashboardContent always paints #supplementary
           last, so this is the only way to reach totals -> health -> activity
           without gating health on the overview too. -->
      <div
        v-if="showActivity"
        data-testid="project-recent-activity"
        class="rounded-lg border border-border bg-surface p-4 space-y-3"
      >
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
    </template>
  </DashboardContent>
</template>
