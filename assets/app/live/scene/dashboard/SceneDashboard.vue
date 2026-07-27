<script setup lang="ts">
import type { Component } from "vue";
import { computed, ref } from "vue";
import { Image, Map as MapIcon, MapPin, MoreHorizontal, Pentagon, Trash2 } from "lucide-vue-next";
import { Button } from "@components/ui/button";
import DashboardDataTable from "@components/dashboard/DashboardDataTable.vue";
import DashboardIssueFilters from "@components/dashboard/DashboardIssueFilters.vue";
import DashboardIssueList from "@components/dashboard/DashboardIssueList.vue";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@components/ui/dialog";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@components/ui/dropdown-menu";
import { TableCell } from "@components/ui/table";
import { useI18n } from "vue-i18n";
import { useLive } from "@shared/composables/useLive.ts";
import { formatRelativeTime } from "@shared/utils/date-utils.ts";
import { interpolatableDetails } from "@components/health/health-details";
import DashboardContent from "@shell/DashboardContent.vue";
import type { SceneHealthDetails, SceneHealthSeverity } from "@modules/scenes/types/health";
import {
  emptyDashboardIssueFilterOptions,
  type DashboardIssuePagination,
  type DashboardLoadStatus,
  type DashboardIssueFilterOptions,
  type DashboardIssueFilterValues,
  type DashboardTableColumn,
  type DashboardTablePagination,
} from "@components/dashboard/types";

const { t } = useI18n();

interface StatCard {
  icon: Component;
  label: string;
  value: number;
  color: string;
}

interface TableDataRow {
  id: number | string;
  name: string;
  href: string;
  zone_count: number;
  pin_count: number;
  connection_count: number;
  updated_at: string;
}

interface DashboardStats {
  scene_count: number;
  zone_count: number;
  pin_count: number;
  background_count: number;
}

interface Issue {
  id: string;
  href: string;
  severity: SceneHealthSeverity;
  code: string;
  label: string;
  scene_id: number | string;
  entity_type: string;
  entity_id?: number | string | null;
  resource_id: number | string;
  resource_label: string;
  details?: SceneHealthDetails;
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
  stats?: DashboardStats | null;
  tableData?: TableDataRow[];
  pagination?: DashboardTablePagination;
  issues?: Issue[];
  overviewStatus?: DashboardLoadStatus;
  issuesStatus?: DashboardLoadStatus;
  issuePagination?: DashboardIssuePagination;
  issueFilters?: DashboardIssueFilterValues;
  issueFilterOptions?: DashboardIssueFilterOptions;
  canEdit?: boolean;
}>();

const live = useLive();
const deleteDialogOpen = ref(false);
const pendingDeleteScene = ref<TableDataRow | null>(null);

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
  live.pushEvent("sort_scenes", { column });
}

function goToPage(page: number): void {
  live.pushEvent("page_scenes", { page });
}

function goToIssuePage(page: number): void {
  live.pushEvent("page_scene_issues", { page });
}

function changeIssueFilter(payload: { filter: string; value: string }): void {
  live.pushEvent("filter_scene_issues", payload);
}

function retryOverview(): void {
  live.pushEvent("retry_dashboard_overview");
}

function retryIssues(): void {
  live.pushEvent("retry_dashboard_issues");
}

function requestDelete(scene: TableDataRow): void {
  pendingDeleteScene.value = scene;
  deleteDialogOpen.value = true;
}

function confirmDelete(): void {
  if (!pendingDeleteScene.value) return;

  live.pushEvent("set_pending_delete_scene", { id: pendingDeleteScene.value.id });
  live.pushEvent("confirm_delete_scene", {});
  deleteDialogOpen.value = false;
  pendingDeleteScene.value = null;
}

function healthFindingLabel(issue: Issue): string {
  return t(`scenes.health.findings.${issue.code}`, interpolatableDetails(issue.details));
}

function issueCodeLabel(code: string): string {
  return t(`scenes.health.issue_types.${code}`);
}

function cancelDelete(): void {
  deleteDialogOpen.value = false;
  pendingDeleteScene.value = null;
}

const statCards = computed<StatCard[]>(() => {
  if (!stats) {
    return [];
  }
  return [
    {
      icon: MapIcon,
      label: t("scenes.dashboard.title"),
      value: stats.scene_count,
      color: "text-primary",
    },
    {
      icon: Pentagon,
      label: t("scenes.dashboard.zones"),
      value: stats.zone_count,
      color: "text-blue-400",
    },
    {
      icon: MapPin,
      label: t("scenes.dashboard.pins"),
      value: stats.pin_count,
      color: "text-violet-400",
    },
    {
      icon: Image,
      label: t("scenes.dashboard.backgrounds"),
      value: stats.background_count,
      color: "text-emerald-400",
    },
  ];
});

const columns = computed<DashboardTableColumn[]>(() => [
  { key: "name", label: t("scenes.dashboard.name"), align: "left" },
  { key: "zone_count", label: t("scenes.dashboard.zones"), align: "right" },
  { key: "pin_count", label: t("scenes.dashboard.pins"), align: "right" },
  { key: "connection_count", label: t("scenes.dashboard.connections"), align: "right" },
  { key: "updated_at", label: t("scenes.dashboard.modified"), align: "right" },
]);
</script>

<template>
  <DashboardContent
    :title="$t('scenes.dashboard.title')"
    :subtitle="$t('scenes.dashboard.subtitle')"
    :loading="overviewStatus === 'loading'"
    :loading-label="$t('common.dashboard.loading_overview')"
    :failure="overviewFailure"
    :is-empty="overviewHasContent && pagination.total === 0"
    :empty-icon="MapIcon"
    :empty-message="$t('scenes.dashboard.empty')"
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
      :title="$t('scenes.dashboard.all_scenes')"
      :rows="tableData"
      :columns="columns"
      :pagination="pagination"
      :total-label="$t('scenes.dashboard.total_scenes', pagination.total)"
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
            class="font-medium hover:underline"
          >
            {{ row.name }}
          </a>
        </TableCell>
        <TableCell class="text-right tabular-nums">{{ row.zone_count }}</TableCell>
        <TableCell class="text-right tabular-nums">{{ row.pin_count }}</TableCell>
        <TableCell class="text-right tabular-nums">{{ row.connection_count }}</TableCell>
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
              :aria-label="$t('scenes.dashboard.scene_actions')"
              :title="$t('scenes.dashboard.scene_actions')"
            >
              <MoreHorizontal class="size-4" />
            </Button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end">
            <DropdownMenuItem class="text-destructive gap-2 text-xs" @select="requestDelete(row)">
              <Trash2 class="size-3.5" />
              {{ $t("scenes.dashboard.delete") }}
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
        data-testid="scene-dashboard-issues"
        class="space-y-3"
        :aria-busy="issuesStatus === 'loading' || issuesStatus === 'refreshing'"
      >
        <h2 class="text-sm font-medium">{{ $t("scenes.dashboard.issues") }}</h2>

        <div
          v-if="issuesStatus === 'loading'"
          data-testid="scene-issues-loading"
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
          data-testid="scene-issues-error"
          class="flex flex-col items-center justify-center gap-3 rounded-lg border border-destructive/30 bg-destructive/5 px-4 py-8 text-center"
          role="alert"
        >
          <p class="text-sm text-destructive">
            {{ $t("common.dashboard.issues_load_failed") }}
          </p>
          <button
            type="button"
            data-testid="scene-issues-retry"
            class="inline-flex h-8 items-center justify-center rounded-md border border-border bg-background px-3 text-sm font-medium transition-colors hover:bg-accent focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring/50"
            @click="retryIssues"
          >
            {{ $t("common.dashboard.retry") }}
          </button>
        </div>

        <template v-else>
          <div
            v-if="issuesStatus === 'stale'"
            data-testid="scene-issues-stale"
            class="flex items-center justify-between gap-3 rounded-lg border border-amber-500/30 bg-amber-500/5 px-4 py-3"
            role="status"
            aria-live="polite"
          >
            <p class="text-sm text-amber-700 dark:text-amber-300">
              {{ $t("common.dashboard.issues_stale") }}
            </p>
            <button
              type="button"
              data-testid="scene-issues-retry"
              class="inline-flex h-8 shrink-0 items-center justify-center rounded-md border border-border bg-background px-3 text-sm font-medium transition-colors hover:bg-accent focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring/50"
              @click="retryIssues"
            >
              {{ $t("common.dashboard.retry") }}
            </button>
          </div>

          <DashboardIssueFilters
            :filters="issueFilters"
            :options="issueFilterOptions"
            :all-resources-label="$t('scenes.dashboard.all_scenes')"
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

    <Dialog v-model:open="deleteDialogOpen">
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{{ $t("scenes.dashboard.delete_title") }}</DialogTitle>
          <DialogDescription>
            {{
              $t("scenes.dashboard.delete_description", {
                name: pendingDeleteScene?.name,
              })
            }}
          </DialogDescription>
        </DialogHeader>
        <DialogFooter>
          <Button variant="outline" size="sm" @click="cancelDelete">
            {{ $t("scenes.dashboard.cancel") }}
          </Button>
          <Button variant="destructive" size="sm" @click="confirmDelete">
            {{ $t("scenes.dashboard.delete") }}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  </DashboardContent>
</template>
