<script setup lang="ts">
import {
  FileText,
  Layers,
  Link,
  MoreHorizontal,
  TextCursorInput,
  Trash2,
  Variable,
} from "lucide-vue-next";
import { computed } from "vue";
import { Button } from "@components/ui/button/index.ts";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@components/ui/dropdown-menu/index.ts";
import { TableCell } from "@components/ui/table/index.ts";
import { useLive } from "@shared/composables/useLive.ts";
import { formatRelativeTime } from "@shared/utils/date-utils.ts";
import { interpolatableDetails } from "@components/health/health-details";
import { useI18n } from "vue-i18n";
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
import type { DashboardIssue, DashboardRow, DashboardStats, StatCard } from "@modules/sheets/types";

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
  stats?: DashboardStats | null;
  tableData?: DashboardRow[];
  pagination?: DashboardTablePagination;
  issues?: DashboardIssue[];
  overviewStatus?: DashboardLoadStatus;
  issuesStatus?: DashboardLoadStatus;
  issuePagination?: DashboardIssuePagination;
  issueFilters?: DashboardIssueFilterValues;
  issueFilterOptions?: DashboardIssueFilterOptions;
  canEdit?: boolean;
}>();

const live = useLive();
const { t } = useI18n();

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

function sortBy(column: string): void {
  live.pushEvent("sort_sheets", { column });
}

function goToPage(page: number): void {
  live.pushEvent("page_sheets", { page });
}

function goToIssuePage(page: number): void {
  live.pushEvent("page_sheet_issues", { page });
}

function changeIssueFilter(payload: { filter: string; value: string }): void {
  live.pushEvent("filter_sheet_issues", payload);
}

function retryOverview(): void {
  live.pushEvent("retry_dashboard_overview");
}

function retryIssues(): void {
  live.pushEvent("retry_dashboard_issues");
}

function requestDelete(id: number | string): void {
  live.pushEvent("set_pending_delete_sheet", { id });
  live.pushEvent("confirm_delete_sheet", {});
}

function healthFindingLabel(issue: DashboardIssue): string {
  return t(`sheets.health.findings.${issue.code}`, interpolatableDetails(issue.details));
}

function issueCodeLabel(code: string): string {
  return t(`sheets.health.issue_types.${code}`);
}

const statCards = computed<StatCard[]>(() => {
  if (!stats) {
    return [];
  }
  return [
    {
      icon: FileText,
      label: t("sheets.dashboard.stats.sheets"),
      value: stats.sheet_count,
      color: "text-primary",
    },
    {
      icon: Layers,
      label: t("sheets.dashboard.stats.blocks"),
      value: stats.block_count,
      color: "text-blue-400",
    },
    {
      icon: Variable,
      label: t("sheets.dashboard.stats.variables"),
      value: stats.variable_count,
      color: "text-violet-400",
    },
    {
      icon: Link,
      label: t("sheets.dashboard.stats.vars_in_use"),
      value: stats.variables_in_use,
      color: "text-amber-400",
    },
    {
      icon: TextCursorInput,
      label: t("sheets.dashboard.stats.words"),
      value: stats.word_count,
      color: "text-emerald-400",
    },
  ];
});

const columns = computed<DashboardTableColumn[]>(() => [
  { key: "name", label: t("sheets.dashboard.columns.name"), align: "left" },
  { key: "block_count", label: t("sheets.dashboard.columns.blocks"), align: "right" },
  { key: "variable_count", label: t("sheets.dashboard.columns.variables"), align: "right" },
  { key: "word_count", label: t("sheets.dashboard.columns.words"), align: "right" },
  { key: "updated_at", label: t("sheets.dashboard.columns.modified"), align: "right" },
]);
</script>

<template>
  <DashboardContent
    :title="$t('sheets.dashboard.title')"
    :subtitle="$t('sheets.dashboard.subtitle')"
    :loading="overviewStatus === 'loading'"
    :loading-label="$t('common.dashboard.loading_overview')"
    :failure="overviewFailure"
    :is-empty="overviewHasContent && pagination.total === 0"
    :empty-icon="FileText"
    :empty-message="$t('sheets.dashboard.empty')"
    @retry="retryOverview"
  >
    <!-- Stats row -->
    <div class="grid grid-cols-2 md:grid-cols-3 xl:grid-cols-5 gap-3">
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
      :title="$t('sheets.dashboard.all_sheets')"
      :rows="tableData"
      :columns="columns"
      :pagination="pagination"
      :total-label="$t('sheets.dashboard.total_sheets', pagination.total)"
      :previous-label="$t('common.dashboard.previous_page')"
      :next-label="$t('common.dashboard.next_page')"
      :has-actions="canEdit"
      @sort="sortBy"
      @page="goToPage"
    >
      <template #row="{ row }">
        <TableCell>
          <a
            :href="row.href"
            data-phx-link="redirect"
            data-phx-link-state="push"
            class="font-medium hover:underline"
          >
            {{ row.name }}
          </a>
        </TableCell>
        <TableCell class="text-right tabular-nums">{{ row.block_count }}</TableCell>
        <TableCell class="text-right tabular-nums">{{ row.variable_count }}</TableCell>
        <TableCell class="text-right tabular-nums">{{ row.word_count }}</TableCell>
        <TableCell class="text-right text-muted-foreground text-xs">
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
            <DropdownMenuItem
              class="text-destructive gap-2 text-xs"
              @select="requestDelete(row.id)"
            >
              <Trash2 class="size-3.5" />
              {{ $t("sheets.dashboard.delete") }}
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
        data-testid="sheet-dashboard-issues"
        class="space-y-3"
        :aria-busy="issuesStatus === 'loading' || issuesStatus === 'refreshing'"
      >
        <h2 class="text-sm font-medium">{{ $t("sheets.dashboard.issues") }}</h2>

        <div
          v-if="issuesStatus === 'loading'"
          data-testid="sheet-issues-loading"
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
          data-testid="sheet-issues-error"
          class="flex flex-col items-center justify-center gap-3 rounded-lg border border-destructive/30 bg-destructive/5 px-4 py-8 text-center"
          role="alert"
        >
          <p class="text-sm text-destructive">
            {{ $t("common.dashboard.issues_load_failed") }}
          </p>
          <button
            type="button"
            data-testid="sheet-issues-retry"
            class="inline-flex h-8 items-center justify-center rounded-md border border-border bg-background px-3 text-sm font-medium transition-colors hover:bg-accent focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring/50"
            @click="retryIssues"
          >
            {{ $t("common.dashboard.retry") }}
          </button>
        </div>

        <template v-else>
          <div
            v-if="issuesStatus === 'stale'"
            data-testid="sheet-issues-stale"
            class="flex items-center justify-between gap-3 rounded-lg border border-amber-500/30 bg-amber-500/5 px-4 py-3"
            role="status"
            aria-live="polite"
          >
            <p class="text-sm text-amber-700 dark:text-amber-300">
              {{ $t("common.dashboard.issues_stale") }}
            </p>
            <button
              type="button"
              data-testid="sheet-issues-retry"
              class="inline-flex h-8 shrink-0 items-center justify-center rounded-md border border-border bg-background px-3 text-sm font-medium transition-colors hover:bg-accent focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring/50"
              @click="retryIssues"
            >
              {{ $t("common.dashboard.retry") }}
            </button>
          </div>

          <DashboardIssueFilters
            :filters="issueFilters"
            :options="issueFilterOptions"
            :all-resources-label="$t('sheets.dashboard.all_sheets')"
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
