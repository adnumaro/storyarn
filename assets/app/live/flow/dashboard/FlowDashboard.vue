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
import { computed, ref } from "vue";
import { useI18n } from "vue-i18n";
import type { FlowDashboardIssue } from "@modules/flows/types/health";
import { interpolatableDetails } from "@components/health/health-details";
import ConfirmDialog from "@components/ConfirmDialog.vue";
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

interface NodeDistItem {
  type: string;
  count: number;
  percentage: number;
}

interface Speaker {
  sheet_id: number | null;
  name: string | null;
  count: number;
  href: string | null;
}

// The node histogram and the speaker ranking ride inside `stats` rather than as
// two more props: they ARE flow overview statistics, and the component is at the
// 10-prop ceiling the linter enforces.
interface FlowStats {
  flow_count: number;
  node_count: number;
  dialogue_count: number;
  word_count: number;
  node_dist: NodeDistItem[];
  speakers: Speaker[];
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
const pendingDeleteFlow = ref<FlowTableRow | null>(null);
const deleteDialogOpen = computed({
  get: () => pendingDeleteFlow.value !== null,
  set: (open: boolean) => {
    if (!open) {
      pendingDeleteFlow.value = null;
    }
  },
});

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

function requestDelete(flow: FlowTableRow): void {
  pendingDeleteFlow.value = flow;
}

function confirmDelete(): void {
  if (!pendingDeleteFlow.value) return;

  live.pushEvent("set_pending_delete", { id: pendingDeleteFlow.value.id });
  live.pushEvent("confirm_delete", {});
  pendingDeleteFlow.value = null;
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

const nodeDist = computed<NodeDistItem[]>(() => stats?.node_dist ?? []);
const speakers = computed<Speaker[]>(() => stats?.speakers ?? []);

// The server sends the raw node type, so the histogram resolves the SAME
// `flows.node_types.*` catalog the canvas palette uses instead of carrying its
// own copy of every label.
function nodeTypeLabel(type: string): string {
  return t(`flows.node_types.${type}`);
}

// A speaker whose sheet was deleted keeps its dialogue lines but loses its name.
function speakerLabel(speaker: Speaker): string {
  return speaker.name ?? t("flows.dashboard.unknown_speaker");
}

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

    <!-- Content breakdown -->
    <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
      <div
        data-testid="flow-node-distribution"
        class="rounded-lg border border-border bg-surface p-4 space-y-3"
      >
        <h2 class="text-sm font-medium">{{ $t("flows.dashboard.node_distribution") }}</h2>
        <div v-if="nodeDist.length === 0" class="text-sm text-muted-foreground/50 py-2 text-center">
          {{ $t("flows.dashboard.no_nodes") }}
        </div>
        <div v-else class="space-y-1.5">
          <div
            v-for="item in nodeDist"
            :key="item.type"
            class="flex items-center justify-between text-sm"
          >
            <span class="text-muted-foreground">{{ nodeTypeLabel(item.type) }}</span>
            <div class="flex items-center gap-2">
              <span class="tabular-nums font-medium">{{ item.count }}</span>
              <span class="text-xs text-muted-foreground/60 tabular-nums w-10 text-right">
                {{ item.percentage }}%
              </span>
            </div>
          </div>
        </div>
      </div>

      <div
        data-testid="flow-top-speakers"
        class="rounded-lg border border-border bg-surface p-4 space-y-3"
      >
        <h2 class="text-sm font-medium">{{ $t("flows.dashboard.top_speakers") }}</h2>
        <div v-if="speakers.length === 0" class="text-sm text-muted-foreground/50 py-2 text-center">
          {{ $t("flows.dashboard.no_speakers") }}
        </div>
        <div v-else class="space-y-1.5">
          <div
            v-for="speaker in speakers"
            :key="speaker.sheet_id ?? speakerLabel(speaker)"
            class="flex items-center justify-between text-sm"
          >
            <a
              v-if="speaker.href"
              :href="speaker.href"
              data-phx-link="redirect"
              data-phx-link-state="push"
              class="text-muted-foreground hover:text-foreground hover:underline transition-colors"
            >
              {{ speakerLabel(speaker) }}
            </a>
            <span v-else class="text-muted-foreground">{{ speakerLabel(speaker) }}</span>
            <span class="tabular-nums font-medium">{{ speaker.count }}</span>
          </div>
        </div>
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
            <Button
              variant="ghost"
              size="icon-sm"
              class="size-7"
              :aria-label="$t('flows.dashboard.flow_actions')"
              :title="$t('flows.dashboard.flow_actions')"
            >
              <MoreHorizontal class="size-4" />
            </Button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end">
            <DropdownMenuItem v-if="!row.is_main" class="gap-2 text-xs" @select="setMain(row.id)">
              <Star class="size-3.5" />
              {{ $t("flows.dashboard.set_main") }}
            </DropdownMenuItem>
            <DropdownMenuItem class="text-destructive gap-2 text-xs" @select="requestDelete(row)">
              <Trash2 class="size-3.5" />
              {{ $t("flows.dashboard.delete") }}
            </DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>
      </template>
    </DashboardDataTable>

    <template #supplementary>
      <DashboardIssuesSection
        :title="$t('flows.dashboard.issues')"
        test-id-prefix="flow"
        :status="issuesStatus"
        :issues="issues"
        :pagination="resolvedIssuePagination"
        :filters="issueFilters"
        :filter-options="issueFilterOptions"
        :all-resources-label="$t('flows.dashboard.all_flows')"
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
    :title="$t('flows.tree.delete_title')"
    :description="
      $t('flows.tree.delete_description', {
        name: pendingDeleteFlow?.name,
      })
    "
    :confirm-text="$t('flows.tree.delete')"
    :cancel-text="$t('flows.tree.cancel')"
    variant="destructive"
    :icon="Trash2"
    @confirm="confirmDelete"
  />
</template>
