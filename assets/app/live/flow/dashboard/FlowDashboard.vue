<script setup lang="ts">
import {
  Box,
  GitBranch,
  MessageSquare,
  MoreHorizontal,
  Star,
  TextCursorInput,
  Trash2,
} from "lucide-vue-next";
import type { Component } from "vue";
import { computed } from "vue";
import { useI18n } from "vue-i18n";
import type { FlowDashboardIssue } from "@modules/flows/types/health";
import { interpolatableDetails } from "@components/health/health-details";
import { Badge } from "@components/ui/badge";
import { Button } from "@components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@components/ui/dropdown-menu";
import { TableCell } from "@components/ui/table";
import { useLive } from "@shared/composables/useLive";
import { formatRelativeTime } from "@shared/utils/date-utils";
import DashboardContent from "@shell/DashboardContent.vue";
import DashboardDataTable from "@components/dashboard/DashboardDataTable.vue";
import DashboardIssueFilters from "@components/dashboard/DashboardIssueFilters.vue";
import DashboardIssueList from "@components/dashboard/DashboardIssueList.vue";
import {
  emptyDashboardIssueFilterOptions,
  type DashboardIssuePagination,
  type DashboardLoadStatus,
  type DashboardIssueFilterOptions,
  type DashboardIssueFilterValues,
  type DashboardTableColumn,
  type DashboardTablePagination,
} from "@components/dashboard/types";

interface FlowStats {
  flow_count: number;
  node_count: number;
  dialogue_count: number;
  word_count: number;
}

interface FlowTableRow {
  id: number | string;
  name: string;
  href: string;
  is_main: boolean;
  node_count: number;
  dialogue_count: number;
  condition_count: number;
  word_count: number;
  updated_at: string;
}

interface StatCard {
  icon: Component;
  label: string;
  value: number;
  color: string;
}

const {
  stats = null,
  tableData = [],
  pagination = { sortBy: "name", sortDir: "asc", page: 1, totalPages: 1, total: 0 },
  issues = [],
  overviewStatus = "loading",
  issuesStatus = "loading",
  issuePagination,
  issueFilters = { severity: "all", code: "all", resource: "all" },
  issueFilterOptions = emptyDashboardIssueFilterOptions(),
  canEdit = false,
} = defineProps<{
  stats: FlowStats | null;
  tableData: FlowTableRow[];
  pagination: DashboardTablePagination;
  issues: FlowDashboardIssue[];
  overviewStatus?: DashboardLoadStatus;
  issuesStatus?: DashboardLoadStatus;
  issuePagination?: DashboardIssuePagination;
  issueFilters?: DashboardIssueFilterValues;
  issueFilterOptions?: DashboardIssueFilterOptions;
  canEdit: boolean;
}>();

const { t } = useI18n();

// The dashboard translates the SAME `flows.health.findings.*` keys the editor
// popover uses, so the two surfaces cannot word the same finding differently.
function healthFindingLabel(issue: FlowDashboardIssue): string {
  return t(`flows.health.findings.${issue.code}`, interpolatableDetails(issue.details));
}

function issueCodeLabel(code: string): string {
  return t(`flows.health.issue_types.${code}`);
}
const live = useLive();

const resolvedIssuePagination = computed<DashboardIssuePagination>(
  () =>
    issuePagination ?? {
      page: 1,
      totalPages: 1,
      total: issues.length,
      unfilteredTotal: issues.length,
    },
);

const overviewHasContent = computed(
  () => overviewStatus !== "loading" && overviewStatus !== "error",
);

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

function handleSort(column: string): void {
  live.pushEvent("sort_flows", { column });
}

function goToPage(page: number): void {
  live.pushEvent("page_flows", { page });
}

function goToIssuePage(page: number): void {
  live.pushEvent("page_flow_issues", { page });
}

function changeIssueFilter(payload: { filter: string; value: string }): void {
  live.pushEvent("filter_flow_issues", payload);
}

function retryOverview(): void {
  live.pushEvent("retry_dashboard_overview");
}

function retryIssues(): void {
  live.pushEvent("retry_dashboard_issues");
}

function setMain(id: number | string): void {
  live.pushEvent("set_main", { id });
}

function requestDelete(id: number | string): void {
  live.pushEvent("set_pending_delete", { id });
  live.pushEvent("confirm_delete", {});
}

const statCards = computed<StatCard[]>(() => {
  if (!stats) {
    return [];
  }
  return [
    {
      icon: GitBranch,
      label: t("flows.dashboard.title"),
      value: stats.flow_count,
      color: "text-primary",
    },
    {
      icon: Box,
      label: t("flows.dashboard.columns.nodes"),
      value: stats.node_count,
      color: "text-blue-400",
    },
    {
      icon: MessageSquare,
      label: t("flows.dashboard.columns.dialogue"),
      value: stats.dialogue_count,
      color: "text-violet-400",
    },
    {
      icon: TextCursorInput,
      label: t("flows.dashboard.columns.words"),
      value: stats.word_count,
      color: "text-emerald-400",
    },
  ];
});

const columns = computed<DashboardTableColumn[]>(() => [
  { key: "name", label: t("flows.dashboard.columns.name"), align: "left" },
  { key: "node_count", label: t("flows.dashboard.columns.nodes"), align: "right" },
  {
    key: "dialogue_count",
    label: t("flows.dashboard.columns.dialogue"),
    align: "right",
    hiddenClass: "hidden sm:table-cell",
  },
  {
    key: "condition_count",
    label: t("flows.dashboard.columns.conditions"),
    align: "right",
    hiddenClass: "hidden sm:table-cell",
  },
  {
    key: "word_count",
    label: t("flows.dashboard.columns.words"),
    align: "right",
    hiddenClass: "hidden md:table-cell",
  },
  {
    key: "updated_at",
    label: t("flows.dashboard.columns.modified"),
    align: "right",
    hiddenClass: "hidden md:table-cell",
  },
]);
</script>

<template>
  <DashboardContent
    :title="$t('flows.dashboard.title')"
    :subtitle="$t('flows.dashboard.subtitle')"
    :loading="overviewStatus === 'loading'"
    :loading-label="$t('common.dashboard.loading_overview')"
    :failure="overviewFailure"
    :is-empty="overviewHasContent && pagination.total === 0"
    :empty-message="$t('flows.dashboard.empty')"
    :empty-icon="GitBranch"
    @retry="retryOverview"
  >
    <!-- Stats row -->
    <div class="grid grid-cols-2 md:grid-cols-4 gap-3">
      <div
        v-for="stat in statCards"
        :key="stat.label"
        class="rounded-lg border border-border bg-surface p-4 space-y-2"
      >
        <div class="flex items-center gap-2 text-xs text-muted-foreground">
          <component :is="stat.icon" :class="['size-4', stat.color]" />
          {{ stat.label }}
        </div>
        <p class="text-2xl font-bold tabular-nums">{{ stat.value }}</p>
      </div>
    </div>

    <!-- Table section -->
    <DashboardDataTable
      :title="$t('flows.dashboard.all_flows')"
      :rows="tableData"
      :columns="columns"
      :pagination="pagination"
      :total-label="$t('flows.dashboard.total_flows', pagination.total)"
      :previous-label="$t('common.dashboard.previous_page')"
      :next-label="$t('common.dashboard.next_page')"
      :has-actions="canEdit"
      @sort="handleSort"
      @page="goToPage"
    >
      <template #row="{ row }">
        <TableCell>
          <a
            :href="row.href"
            data-phx-link="patch"
            data-phx-link-state="push"
            class="inline-flex items-center gap-2 font-medium hover:underline"
          >
            {{ row.name }}
            <Badge v-if="row.is_main" variant="default" class="text-[10px] px-1.5 py-0">
              {{ $t("flows.dashboard.main") }}
            </Badge>
          </a>
        </TableCell>
        <TableCell class="text-right tabular-nums">{{ row.node_count }}</TableCell>
        <TableCell class="text-right tabular-nums hidden sm:table-cell">
          {{ row.dialogue_count }}
        </TableCell>
        <TableCell class="text-right tabular-nums hidden sm:table-cell">
          {{ row.condition_count }}
        </TableCell>
        <TableCell class="text-right tabular-nums hidden md:table-cell">
          {{ row.word_count }}
        </TableCell>
        <TableCell class="text-right text-muted-foreground text-xs hidden md:table-cell">
          {{ formatRelativeTime(row.updated_at) }}
        </TableCell>
      </template>

      <template #actions="{ row }">
        <DropdownMenu>
          <DropdownMenuTrigger as-child>
            <Button variant="ghost" size="icon-sm" class="size-7">
              <MoreHorizontal class="size-4" />
            </Button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end">
            <DropdownMenuItem v-if="!row.is_main" class="gap-2 text-xs" @select="setMain(row.id)">
              <Star class="size-3.5" />
              {{ $t("flows.dashboard.set_main") }}
            </DropdownMenuItem>
            <DropdownMenuItem
              class="text-destructive gap-2 text-xs"
              @select="requestDelete(row.id)"
            >
              <Trash2 class="size-3.5" />
              {{ $t("flows.dashboard.delete") }}
            </DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>
      </template>
    </DashboardDataTable>

    <template #supplementary>
      <!-- Issues -->
      <div
        v-if="
          issuesStatus === 'loading' ||
          issuesStatus === 'error' ||
          issuesStatus === 'stale' ||
          resolvedIssuePagination.unfilteredTotal > 0
        "
        data-testid="flow-dashboard-issues"
        class="space-y-3"
        :aria-busy="issuesStatus === 'loading' || issuesStatus === 'refreshing'"
      >
        <h2 class="text-sm font-medium">{{ $t("flows.dashboard.issues") }}</h2>

        <div
          v-if="issuesStatus === 'loading'"
          data-testid="flow-issues-loading"
          class="flex items-center justify-center rounded-lg border border-border py-8"
          role="status"
          aria-live="polite"
        >
          <div
            class="size-5 animate-spin rounded-full border-2 border-muted-foreground/20 border-t-muted-foreground/60"
            aria-hidden="true"
          />
          <span class="sr-only">{{ $t("common.dashboard.loading_issues") }}</span>
        </div>

        <div
          v-else-if="issuesStatus === 'error'"
          data-testid="flow-issues-error"
          class="flex flex-col items-center justify-center gap-3 rounded-lg border border-destructive/30 bg-destructive/5 px-4 py-8 text-center"
          role="alert"
        >
          <p class="text-sm text-destructive">
            {{ $t("common.dashboard.issues_load_failed") }}
          </p>
          <button
            type="button"
            data-testid="flow-issues-retry"
            class="inline-flex h-8 items-center justify-center rounded-md border border-border bg-background px-3 text-sm font-medium transition-colors hover:bg-accent focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring/50"
            @click="retryIssues"
          >
            {{ $t("common.dashboard.retry") }}
          </button>
        </div>

        <template v-else>
          <div
            v-if="issuesStatus === 'stale'"
            data-testid="flow-issues-stale"
            class="flex items-center justify-between gap-3 rounded-lg border border-amber-500/30 bg-amber-500/5 px-4 py-3"
            role="status"
            aria-live="polite"
          >
            <p class="text-sm text-amber-700 dark:text-amber-300">
              {{ $t("common.dashboard.issues_stale") }}
            </p>
            <button
              type="button"
              data-testid="flow-issues-retry"
              class="inline-flex h-8 shrink-0 items-center justify-center rounded-md border border-border bg-background px-3 text-sm font-medium transition-colors hover:bg-accent focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring/50"
              @click="retryIssues"
            >
              {{ $t("common.dashboard.retry") }}
            </button>
          </div>

          <DashboardIssueFilters
            :filters="issueFilters"
            :options="issueFilterOptions"
            :all-resources-label="$t('flows.dashboard.all_flows')"
            :code-label="issueCodeLabel"
            :disabled="issuesStatus === 'refreshing'"
            @change="changeIssueFilter"
          />

          <DashboardIssueList
            :issues="issues"
            :pagination="resolvedIssuePagination"
            @page="goToIssuePage"
          >
            <template #description="{ issue }">
              {{ healthFindingLabel(issue) }}
            </template>
          </DashboardIssueList>
        </template>
      </div>
    </template>
  </DashboardContent>
</template>
