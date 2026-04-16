<script setup lang="ts">
import {
  AlertTriangle,
  ArrowDown,
  ArrowUp,
  ArrowUpDown,
  Box,
  ChevronLeft,
  ChevronRight,
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
import { Badge } from "@components/ui/badge/index.ts";
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
import { useLive } from "@composables/useLive";
import { formatRelativeTime } from "@utils/date-utils";
import DashboardContent from "@components/layout/DashboardContent.vue";

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
  severity: "warning" | "info";
}

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
      label: "Flows",
      value: stats.flow_count,
      color: "text-primary",
    },
    {
      icon: Box,
      label: "Nodes",
      value: stats.node_count,
      color: "text-blue-400",
    },
    {
      icon: MessageSquare,
      label: "Dialogue",
      value: stats.dialogue_count,
      color: "text-violet-400",
    },
    {
      icon: TextCursorInput,
      label: "Words",
      value: stats.word_count,
      color: "text-emerald-400",
    },
  ];
});

const columns: TableColumn[] = [
  { key: "name", label: "Name", align: "left" },
  { key: "node_count", label: "Nodes", align: "right" },
  {
    key: "dialogue_count",
    label: "Dialogue",
    align: "right",
    hiddenClass: "hidden sm:table-cell",
  },
  {
    key: "condition_count",
    label: "Conditions",
    align: "right",
    hiddenClass: "hidden sm:table-cell",
  },
  {
    key: "word_count",
    label: "Words",
    align: "right",
    hiddenClass: "hidden md:table-cell",
  },
  {
    key: "updated_at",
    label: "Modified",
    align: "right",
    hiddenClass: "hidden md:table-cell",
  },
];

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
    title="Flows"
    subtitle="Create visual narrative flows and dialogue trees"
    :loading="!stats"
    :is-empty="pagination.total === 0 && !stats"
    empty-message="No flows yet. Create your first flow to get started."
    :empty-icon="GitBranch"
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
      <h2 class="text-sm font-medium">All Flows</h2>
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
                  :href="flowHref(row)"
                  data-phx-link="patch"
                  data-phx-link-state="push"
                  class="inline-flex items-center gap-2 font-medium hover:underline"
                >
                  {{ row.name }}
                  <Badge v-if="row.is_main" variant="default" class="text-[10px] px-1.5 py-0">
                    Main
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
                      Set as main
                    </DropdownMenuItem>
                    <DropdownMenuItem
                      class="text-destructive gap-2 text-xs"
                      @select="requestDelete(row.id)"
                    >
                      <Trash2 class="size-3.5" />
                      Delete
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
        <span>{{ pagination.total }} flows</span>
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
      <h2 class="text-sm font-medium">Issues</h2>
      <div class="rounded-lg border border-border divide-y divide-border">
        <a
          v-for="(issue, i) in issues"
          :key="i"
          :href="issue.href"
          class="flex items-start gap-2 px-3 py-2 text-sm hover:bg-muted/30 transition-colors"
        >
          <AlertTriangle
            v-if="issue.severity === 'warning'"
            class="size-4 text-yellow-500 shrink-0 mt-0.5"
          />
          <Info v-else class="size-4 text-blue-400 shrink-0 mt-0.5" />
          <span class="text-muted-foreground">{{ issue.message }}</span>
        </a>
      </div>
    </div>
  </DashboardContent>
</template>
