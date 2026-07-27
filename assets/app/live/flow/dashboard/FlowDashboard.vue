<script setup lang="ts">
import {
  AlertTriangle,
  ArrowDown,
  ArrowUp,
  ArrowUpDown,
  Box,
  CircleX,
  GitBranch,
  Info,
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
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@components/ui/table";
import { useLive } from "@shared/composables/useLive";
import { formatRelativeTime } from "@shared/utils/date-utils";
import DashboardContent from "@shell/DashboardContent.vue";
import DashboardIssueFilters from "@components/dashboard/DashboardIssueFilters.vue";
import DashboardPagination from "@components/dashboard/DashboardPagination.vue";
import {
  emptyDashboardIssueFilterOptions,
  type DashboardIssueFilterOptions,
  type DashboardIssueFilterValues,
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

interface FlowPagination {
  sortBy: string;
  sortDir: "asc" | "desc";
  page: number;
  totalPages: number;
  total: number;
}

interface IssuePagination {
  page: number;
  totalPages: number;
  total: number;
  unfilteredTotal: number;
}

type DashboardLoadStatus = "loading" | "ready" | "refreshing" | "error" | "stale";

interface StatCard {
  icon: Component;
  label: string;
  value: number;
  color: string;
}

interface TableColumn {
  key: string;
  label: string;
  align: "left" | "right";
  hiddenClass?: string;
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
  pagination: FlowPagination;
  issues: FlowDashboardIssue[];
  overviewStatus?: DashboardLoadStatus;
  issuesStatus?: DashboardLoadStatus;
  issuePagination?: IssuePagination;
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

const resolvedIssuePagination = computed<IssuePagination>(
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

function sortIcon(column: string): Component {
  if (pagination.sortBy !== column) {
    return ArrowUpDown;
  }
  return pagination.sortDir === "asc" ? ArrowUp : ArrowDown;
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

const columns = computed<TableColumn[]>(() => [
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
    <div class="space-y-2">
      <h2 class="text-sm font-medium">{{ $t("flows.dashboard.all_flows") }}</h2>
      <div class="rounded-lg border border-border bg-surface overflow-auto max-h-[60vh]">
        <Table>
          <TableHeader>
            <TableRow class="bg-muted/40 hover:bg-muted/40 sticky top-0 z-10">
              <TableHead
                v-for="col in columns"
                :key="col.key"
                :class="[
                  'font-medium text-xs text-muted-foreground uppercase',
                  col.align === 'right' ? 'text-right' : 'text-left',
                  col.hiddenClass,
                ]"
              >
                <button
                  type="button"
                  class="inline-flex items-center gap-1 hover:text-foreground transition-colors"
                  :class="col.align === 'right' && 'ml-auto'"
                  @click="handleSort(col.key)"
                >
                  {{ col.label }}
                  <component :is="sortIcon(col.key)" class="size-3" />
                </button>
              </TableHead>
              <TableHead v-if="canEdit" class="w-10" />
            </TableRow>
          </TableHeader>
          <TableBody>
            <TableRow v-for="row in tableData" :key="row.id">
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
              <TableCell class="text-right tabular-nums hidden sm:table-cell"
                >{{ row.dialogue_count }}
              </TableCell>
              <TableCell class="text-right tabular-nums hidden sm:table-cell"
                >{{ row.condition_count }}
              </TableCell>
              <TableCell class="text-right tabular-nums hidden md:table-cell"
                >{{ row.word_count }}
              </TableCell>
              <TableCell class="text-right text-muted-foreground text-xs hidden md:table-cell">
                {{ formatRelativeTime(row.updated_at) }}
              </TableCell>
              <TableCell v-if="canEdit" class="text-right w-10">
                <DropdownMenu>
                  <DropdownMenuTrigger as-child>
                    <Button variant="ghost" size="icon-sm" class="size-7">
                      <MoreHorizontal class="size-4" />
                    </Button>
                  </DropdownMenuTrigger>
                  <DropdownMenuContent align="end">
                    <DropdownMenuItem
                      v-if="!row.is_main"
                      class="gap-2 text-xs"
                      @select="setMain(row.id)"
                    >
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
              </TableCell>
            </TableRow>
          </TableBody>
        </Table>
      </div>

      <DashboardPagination
        v-if="pagination.total > 0"
        :pagination="pagination"
        :total-label="$t('flows.dashboard.total_flows', pagination.total)"
        :previous-label="$t('common.dashboard.previous_page')"
        :next-label="$t('common.dashboard.next_page')"
        @page="goToPage"
      />
    </div>

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

          <div
            v-if="issues.length > 0"
            class="rounded-lg border border-border divide-y divide-border"
          >
            <a
              v-for="issue in issues"
              :key="issue.id"
              :href="issue.href"
              :data-severity="issue.severity"
              data-phx-link="redirect"
              data-phx-link-state="push"
              class="flex items-start gap-2 px-3 py-2 text-sm hover:bg-muted/30 transition-colors"
            >
              <CircleX
                v-if="issue.severity === 'error'"
                data-testid="flow-issue-error-icon"
                class="size-4 text-red-500 shrink-0 mt-0.5"
              />
              <AlertTriangle
                v-else-if="issue.severity === 'warning'"
                data-testid="flow-issue-warning-icon"
                class="size-4 text-yellow-500 shrink-0 mt-0.5"
              />
              <Info
                v-else
                data-testid="flow-issue-info-icon"
                class="size-4 text-blue-400 shrink-0 mt-0.5"
              />
              <span class="sr-only">
                {{ $t(`common.dashboard.issue_severity.${issue.severity}`) }}:
              </span>
              <span class="text-muted-foreground">
                <span class="text-foreground">{{ issue.label }}</span>
                · {{ healthFindingLabel(issue) }}
              </span>
            </a>
          </div>

          <p
            v-else
            data-testid="flow-issues-empty-filter"
            class="rounded-lg border border-dashed border-border px-4 py-8 text-center text-sm text-muted-foreground"
          >
            {{ $t("common.dashboard.no_matching_issues") }}
          </p>

          <DashboardPagination
            v-if="resolvedIssuePagination.total > 0"
            :pagination="resolvedIssuePagination"
            :total-label="
              $t('common.dashboard.total_issues', { count: resolvedIssuePagination.total })
            "
            :previous-label="$t('common.dashboard.previous_page')"
            :next-label="$t('common.dashboard.next_page')"
            @page="goToIssuePage"
          />
        </template>
      </div>
    </template>
  </DashboardContent>
</template>
