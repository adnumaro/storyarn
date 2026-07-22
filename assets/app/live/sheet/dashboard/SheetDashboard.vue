<script setup lang="ts">
import {
  AlertTriangle,
  ArrowDown,
  ArrowUp,
  ArrowUpDown,
  ChevronLeft,
  ChevronRight,
  CircleX,
  FileText,
  Info,
  Layers,
  Link,
  MoreHorizontal,
  TextCursorInput,
  Trash2,
  Variable,
} from "lucide-vue-next";
import type { FunctionalComponent } from "vue";
import { computed } from "vue";
import { Button } from "@components/ui/button/index.ts";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@components/ui/dropdown-menu/index.ts";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@components/ui/table/index.ts";
import { useLive } from "@shared/composables/useLive.ts";
import { formatRelativeTime } from "@shared/utils/date-utils.ts";
import { useI18n } from "vue-i18n";
import DashboardContent from "@shell/DashboardContent.vue";
import type {
  DashboardColumn,
  DashboardIssue,
  DashboardPagination,
  DashboardRow,
  DashboardStats,
  StatCard,
} from "@modules/sheets/types";

const {
  stats = null,
  tableData = [],
  pagination = { sortBy: "name", sortDir: "asc", page: 1, totalPages: 1, total: 0 },
  issues = [],
  canEdit = false,
  workspaceSlug,
  projectSlug,
} = defineProps<{
  stats?: DashboardStats | null;
  tableData?: DashboardRow[];
  pagination?: DashboardPagination;
  issues?: DashboardIssue[];
  canEdit?: boolean;
  workspaceSlug: string;
  projectSlug: string;
}>();

const live = useLive();
const { t } = useI18n();

function sheetHref(row: DashboardRow): string {
  return `/workspaces/${workspaceSlug}/projects/${projectSlug}/sheets/${row.id}`;
}

function sortBy(column: string): void {
  live.pushEvent("sort_sheets", { column });
}

function goToPage(page: number): void {
  live.pushEvent("page_sheets", { page });
}

function requestDelete(id: number | string): void {
  live.pushEvent("set_pending_delete_sheet", { id });
  live.pushEvent("confirm_delete_sheet", {});
}

function healthFindingLabel(issue: DashboardIssue): string {
  return t(`sheets.health.findings.${issue.code}`, issue.details || {});
}

function sortIcon(column: string): FunctionalComponent {
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

const columns = computed<DashboardColumn[]>(() => [
  { key: "name", label: t("sheets.dashboard.columns.name"), align: "left" },
  { key: "block_count", label: t("sheets.dashboard.columns.blocks"), align: "right" },
  { key: "variable_count", label: t("sheets.dashboard.columns.variables"), align: "right" },
  { key: "word_count", label: t("sheets.dashboard.columns.words"), align: "right" },
  { key: "updated_at", label: t("sheets.dashboard.columns.modified"), align: "right" },
]);

const pages = computed<number[]>(() => {
  const result: number[] = [];
  for (let i = 1; i <= pagination.totalPages; i++) {
    result.push(i);
  }
  return result;
});
</script>

<template>
  <DashboardContent
    :title="$t('sheets.dashboard.title')"
    :subtitle="$t('sheets.dashboard.subtitle')"
    :loading="!stats"
    :is-empty="pagination.total === 0 && !stats"
    :empty-icon="FileText"
    :empty-message="$t('sheets.dashboard.empty')"
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
    <div class="space-y-2">
      <h2 class="text-sm font-medium">{{ $t("sheets.dashboard.all_sheets") }}</h2>
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
                ]"
              >
                <button
                  type="button"
                  class="inline-flex items-center gap-1 hover:text-foreground transition-colors"
                  :class="col.align === 'right' && 'ml-auto'"
                  @click="sortBy(col.key)"
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
                  :href="sheetHref(row)"
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
              <TableCell v-if="canEdit" class="text-right w-10">
                <DropdownMenu>
                  <DropdownMenuTrigger as-child>
                    <Button variant="ghost" size="icon-sm" class="size-7">
                      <MoreHorizontal class="size-4" />
                    </Button>
                  </DropdownMenuTrigger>
                  <DropdownMenuContent align="end" class="">
                    <DropdownMenuItem
                      class="text-destructive gap-2 text-xs"
                      @select="requestDelete(row.id)"
                    >
                      <Trash2 class="size-3.5" />
                      {{ $t("sheets.dashboard.delete") }}
                    </DropdownMenuItem>
                  </DropdownMenuContent>
                </DropdownMenu>
              </TableCell>
            </TableRow>
          </TableBody>
        </Table>
      </div>

      <!-- Pagination -->
      <div
        v-if="pagination.totalPages > 1"
        class="flex items-center justify-between text-xs text-muted-foreground pt-1"
      >
        <span>{{ $t("sheets.dashboard.total_sheets", pagination.total) }}</span>
        <div class="flex items-center gap-1">
          <Button
            variant="ghost"
            size="icon-sm"
            class="size-7"
            :disabled="pagination.page <= 1"
            @click="goToPage(pagination.page - 1)"
          >
            <ChevronLeft class="size-4" />
          </Button>
          <Button
            v-for="p in pages"
            :key="p"
            :variant="p === pagination.page ? 'default' : 'ghost'"
            size="sm"
            class="h-7 min-w-7 px-2 text-xs"
            @click="goToPage(p)"
          >
            {{ p }}
          </Button>
          <Button
            variant="ghost"
            size="icon-sm"
            class="size-7"
            :disabled="pagination.page >= pagination.totalPages"
            @click="goToPage(pagination.page + 1)"
          >
            <ChevronRight class="size-4" />
          </Button>
        </div>
      </div>
    </div>

    <!-- Issues -->
    <div v-if="issues.length > 0" class="space-y-2">
      <h2 class="text-sm font-medium">{{ $t("sheets.dashboard.issues") }}</h2>
      <div class="rounded-lg border border-border divide-y divide-border">
        <a
          v-for="(issue, i) in issues"
          :key="i"
          :href="issue.href"
          :data-severity="issue.severity"
          data-phx-link="redirect"
          data-phx-link-state="push"
          class="flex items-start gap-2 px-3 py-2 text-sm hover:bg-muted/30 transition-colors"
        >
          <CircleX
            v-if="issue.severity === 'error'"
            data-testid="sheet-issue-error-icon"
            class="size-4 text-red-500 shrink-0 mt-0.5"
          />
          <AlertTriangle
            v-else-if="issue.severity === 'warning'"
            data-testid="sheet-issue-warning-icon"
            class="size-4 text-yellow-500 shrink-0 mt-0.5"
          />
          <Info
            v-else
            data-testid="sheet-issue-info-icon"
            class="size-4 text-blue-400 shrink-0 mt-0.5"
          />
          <span class="text-muted-foreground">
            <span class="text-foreground">{{ issue.label }}</span>
            · {{ healthFindingLabel(issue) }}
          </span>
        </a>
      </div>
    </div>
  </DashboardContent>
</template>
