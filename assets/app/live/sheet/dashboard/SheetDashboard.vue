<script setup lang="ts">
import {
  FileText,
  Layers,
  Link,
  MoreHorizontal,
  TextCursorInput,
  Trash2,
  Variable,
} from "@lucide/vue";
import { computed, ref } from "vue";
import ConfirmDialog from "@components/ConfirmDialog.vue";
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
import DashboardIssuesSection from "@components/dashboard/DashboardIssuesSection.vue";
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
const pendingDeleteSheet = ref<DashboardRow | null>(null);
const deleteDialogOpen = computed({
  get: () => pendingDeleteSheet.value !== null,
  set: (open: boolean) => {
    if (!open) {
      pendingDeleteSheet.value = null;
    }
  },
});

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

function requestDelete(sheet: DashboardRow): void {
  pendingDeleteSheet.value = sheet;
}

function confirmDelete(): void {
  if (!pendingDeleteSheet.value) return;

  live.pushEvent("set_pending_delete_sheet", { id: pendingDeleteSheet.value.id });
  live.pushEvent("confirm_delete_sheet", {});
  pendingDeleteSheet.value = null;
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
            <Button
              variant="ghost"
              size="icon-sm"
              class="size-7"
              :aria-label="$t('sheets.dashboard.sheet_actions')"
              :title="$t('sheets.dashboard.sheet_actions')"
            >
              <MoreHorizontal class="size-4" />
            </Button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end">
            <DropdownMenuItem
              data-testid="sheet-dashboard-delete-row"
              class="text-destructive gap-2 text-xs"
              @select="requestDelete(row)"
            >
              <Trash2 class="size-3.5" />
              {{ $t("sheets.dashboard.delete") }}
            </DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>
      </template>
    </DashboardDataTable>

    <template #supplementary>
      <DashboardIssuesSection
        :title="$t('sheets.dashboard.issues')"
        test-id-prefix="sheet"
        :status="issuesStatus"
        :issues="issues"
        :pagination="resolvedIssuePagination"
        :filters="issueFilters"
        :filter-options="issueFilterOptions"
        :all-resources-label="$t('sheets.dashboard.all_sheets')"
        :code-label="issueCodeLabel"
        @retry="retryIssues"
        @filter="changeIssueFilter"
        @page="goToIssuePage"
      >
        <template #description="{ issue }">
          {{ healthFindingLabel(issue) }}
        </template>
      </DashboardIssuesSection>
    </template>
  </DashboardContent>

  <ConfirmDialog
    v-model:open="deleteDialogOpen"
    :title="$t('sheets.tree.delete_title')"
    :description="
      $t('sheets.tree.delete_description', {
        name: pendingDeleteSheet?.name ?? '',
      })
    "
    :confirm-text="$t('sheets.tree.delete')"
    :cancel-text="$t('sheets.tree.cancel')"
    variant="destructive"
    :icon="Trash2"
    @confirm="confirmDelete"
  />
</template>
