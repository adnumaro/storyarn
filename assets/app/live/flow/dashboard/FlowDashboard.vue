<script setup lang="ts">
import {
  AlertTriangle,
  ArrowDown,
  ArrowUp,
  ArrowUpDown,
  Box,
  ChevronLeft,
  ChevronRight,
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
import DashboardPanel from "@shell/DashboardPanel.vue";
import DashboardStatCard from "@shell/DashboardStatCard.vue";

interface FlowStats {
  flow_count: number;
  node_count: number;
  dialogue_count: number;
  word_count: number;
}

interface FlowTableRow {
  id: number | string;
  name: string;
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

interface FlowIssue {
  href: string;
  message: string;
  severity: "error" | "warning" | "info";
}

interface StatCard {
  icon: Component;
  label: string;
  testId: string;
  value: number;
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
  canEdit = false,
  workspaceSlug,
  projectSlug,
} = defineProps<{
  stats: FlowStats | null;
  tableData: FlowTableRow[];
  pagination: FlowPagination;
  issues: FlowIssue[];
  canEdit: boolean;
  workspaceSlug: string;
  projectSlug: string;
}>();

const { t } = useI18n();
const live = useLive();

function flowHref(row: FlowTableRow): string {
  return `/workspaces/${workspaceSlug}/projects/${projectSlug}/flows/${row.id}`;
}

function handleSort(column: string): void {
  live.pushEvent("sort_flows", { column });
}

function goToPage(page: number): void {
  live.pushEvent("page_flows", { page });
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
      testId: "flow-stat-total",
      value: stats.flow_count,
    },
    {
      icon: Box,
      label: t("flows.dashboard.columns.nodes"),
      testId: "flow-stat-nodes",
      value: stats.node_count,
    },
    {
      icon: MessageSquare,
      label: t("flows.dashboard.columns.dialogue"),
      testId: "flow-stat-dialogue",
      value: stats.dialogue_count,
    },
    {
      icon: TextCursorInput,
      label: t("flows.dashboard.columns.words"),
      testId: "flow-stat-words",
      value: stats.word_count,
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

const pages = computed(() => {
  const result = [];
  for (let i = 1; i <= pagination.totalPages; i++) {
    result.push(i);
  }
  return result;
});
</script>

<template>
  <DashboardContent
    :title="$t('flows.dashboard.title')"
    :subtitle="$t('flows.dashboard.subtitle')"
    :icon="GitBranch"
    :loading="!stats"
    :is-empty="pagination.total === 0 && !stats"
    :empty-message="$t('flows.dashboard.empty')"
    :empty-icon="GitBranch"
  >
    <div class="grid grid-cols-2 gap-3 md:grid-cols-4">
      <DashboardStatCard
        v-for="stat in statCards"
        :key="stat.label"
        :icon="stat.icon"
        :label="stat.label"
        :test-id="stat.testId"
        :value="stat.value"
      />
    </div>

    <DashboardPanel :title="$t('flows.dashboard.all_flows')" :icon="GitBranch" :padded="false">
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
            <TableRow
              v-for="row in tableData"
              :key="row.id"
              class="transition-colors hover:bg-primary/[0.035]"
            >
              <TableCell>
                <a
                  :href="flowHref(row)"
                  data-phx-link="patch"
                  data-phx-link-state="push"
                  class="inline-flex items-center gap-2 font-medium transition-colors hover:text-primary"
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

      <!-- Pagination -->
      <template v-if="pagination.totalPages > 1" #footer>
        <div class="flex items-center justify-between text-xs text-muted-foreground">
          <span>{{ $t("flows.dashboard.total_flows", pagination.total) }}</span>
          <div class="flex items-center gap-1">
            <Button
              variant="ghost"
              size="icon-sm"
              class="size-7"
              :disabled="pagination.page <= 1"
              :aria-label="$t('flows.dashboard.previous_page')"
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
              :aria-label="$t('flows.dashboard.next_page')"
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
      :title="$t('flows.dashboard.issues')"
      :icon="AlertTriangle"
      :padded="false"
    >
      <div class="divide-y divide-border/60">
        <a
          v-for="(issue, i) in issues"
          :key="i"
          :href="issue.href"
          :data-severity="issue.severity"
          data-phx-link="redirect"
          data-phx-link-state="push"
          class="group flex items-start gap-3 px-4 py-3 text-sm transition-colors hover:bg-primary/[0.035] sm:px-5"
        >
          <CircleX
            v-if="issue.severity === 'error'"
            data-testid="flow-issue-error-icon"
            class="mt-0.5 size-4 shrink-0 text-red-500"
          />
          <AlertTriangle
            v-else-if="issue.severity === 'warning'"
            data-testid="flow-issue-warning-icon"
            class="mt-0.5 size-4 shrink-0 text-yellow-500"
          />
          <Info
            v-else
            data-testid="flow-issue-info-icon"
            class="mt-0.5 size-4 shrink-0 text-blue-400"
          />
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
