<script setup lang="ts">
import {
  AlertTriangle,
  ArrowDown,
  ArrowUp,
  ArrowUpDown,
  ChevronLeft,
  ChevronRight,
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
import DashboardPanel from "@shell/DashboardPanel.vue";
import DashboardStatCard from "@shell/DashboardStatCard.vue";
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
      testId: "sheet-stat-total",
      value: stats.sheet_count,
    },
    {
      icon: Layers,
      label: t("sheets.dashboard.stats.blocks"),
      testId: "sheet-stat-blocks",
      value: stats.block_count,
    },
    {
      icon: Variable,
      label: t("sheets.dashboard.stats.variables"),
      testId: "sheet-stat-variables",
      value: stats.variable_count,
    },
    {
      icon: Link,
      label: t("sheets.dashboard.stats.vars_in_use"),
      testId: "sheet-stat-variables-in-use",
      value: stats.variables_in_use,
    },
    {
      icon: TextCursorInput,
      label: t("sheets.dashboard.stats.words"),
      testId: "sheet-stat-words",
      value: stats.word_count,
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
    :icon="FileText"
    :loading="!stats"
    :is-empty="pagination.total === 0 && !stats"
    :empty-icon="FileText"
    :empty-message="$t('sheets.dashboard.empty')"
  >
    <div class="grid grid-cols-2 gap-3 md:grid-cols-3 xl:grid-cols-5">
      <DashboardStatCard
        v-for="stat in statCards"
        :key="stat.label"
        :icon="stat.icon"
        :label="stat.label"
        :test-id="stat.testId"
        :value="stat.value"
      />
    </div>

    <DashboardPanel :title="$t('sheets.dashboard.all_sheets')" :icon="FileText" :padded="false">
      <div class="max-h-[60vh] overflow-auto">
        <Table>
          <TableHeader>
            <TableRow class="sticky top-0 z-10 bg-muted/70 hover:bg-muted/70">
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
            <TableRow
              v-for="row in tableData"
              :key="row.id"
              class="transition-colors hover:bg-primary/[0.035]"
            >
              <TableCell>
                <a
                  :href="sheetHref(row)"
                  data-phx-link="redirect"
                  data-phx-link-state="push"
                  class="font-medium transition-colors hover:text-primary"
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
      <template v-if="pagination.totalPages > 1" #footer>
        <div class="flex items-center justify-between text-xs text-muted-foreground">
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
      </template>
    </DashboardPanel>

    <DashboardPanel
      v-if="issues.length > 0"
      :title="$t('sheets.dashboard.issues')"
      :icon="AlertTriangle"
      :padded="false"
    >
      <div class="divide-y divide-border/60">
        <a
          v-for="(issue, i) in issues"
          :key="i"
          :href="issue.href"
          data-phx-link="redirect"
          data-phx-link-state="push"
          class="group flex items-start gap-3 px-4 py-3 text-sm transition-colors hover:bg-primary/[0.035] sm:px-5"
        >
          <AlertTriangle
            v-if="issue.severity === 'warning'"
            class="mt-0.5 size-4 shrink-0 text-yellow-500"
          />
          <Info v-else class="mt-0.5 size-4 shrink-0 text-blue-400" />
          <span
            class="leading-6 text-muted-foreground transition-colors group-hover:text-foreground"
          >
            {{ issue.message }}
          </span>
        </a>
      </div>
    </DashboardPanel>
  </DashboardContent>
</template>
