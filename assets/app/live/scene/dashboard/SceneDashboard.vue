<script setup lang="ts">
import type { Component } from "vue";
import { computed, ref } from "vue";
import {
  AlertTriangle,
  ArrowDown,
  ArrowUp,
  ArrowUpDown,
  ChevronLeft,
  ChevronRight,
  Image,
  Info,
  Map as MapIcon,
  MapPin,
  MoreHorizontal,
  Pentagon,
  Trash2,
} from "lucide-vue-next";
import { Button } from "@components/ui/button";
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
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@components/ui/table";
import { useI18n } from "vue-i18n";
import { useLive } from "@shared/composables/useLive.ts";
import { formatRelativeTime } from "@shared/utils/date-utils.ts";
import DashboardContent from "@shell/DashboardContent.vue";

const { t } = useI18n();

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
}

interface TableDataRow {
  id: number | string;
  name: string;
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

interface Pagination {
  sortBy: string;
  sortDir: "asc" | "desc";
  page: number;
  totalPages: number;
  total: number;
}

interface Issue {
  href: string;
  severity: string;
  message: string;
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
  stats: DashboardStats | null;
  tableData: TableDataRow[];
  pagination: Pagination;
  issues: Issue[];
  canEdit: boolean;
  workspaceSlug: string;
  projectSlug: string;
}>();

const live = useLive();
const deleteDialogOpen = ref(false);
const pendingDeleteScene = ref<TableDataRow | null>(null);

function sceneHref(row: TableDataRow): string {
  return `/workspaces/${workspaceSlug}/projects/${projectSlug}/scenes/${row.id}`;
}

function handleSort(column: string): void {
  live.pushEvent("sort_scenes", { column });
}

function goToPage(page: number): void {
  live.pushEvent("page_scenes", { page });
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

function cancelDelete(): void {
  deleteDialogOpen.value = false;
  pendingDeleteScene.value = null;
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

const columns = computed<TableColumn[]>(() => [
  { key: "name", label: t("scenes.dashboard.name"), align: "left" },
  { key: "zone_count", label: t("scenes.dashboard.zones"), align: "right" },
  { key: "pin_count", label: t("scenes.dashboard.pins"), align: "right" },
  { key: "connection_count", label: t("scenes.dashboard.connections"), align: "right" },
  { key: "updated_at", label: t("scenes.dashboard.modified"), align: "right" },
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
    :title="$t('scenes.dashboard.title')"
    :subtitle="$t('scenes.dashboard.subtitle')"
    :loading="!stats"
    :is-empty="pagination.total === 0 && !stats"
    :empty-icon="MapIcon"
    :empty-message="$t('scenes.dashboard.empty')"
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
      <h2 class="text-sm font-medium">{{ $t("scenes.dashboard.all_scenes") }}</h2>
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
                  :href="sceneHref(row)"
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
              <TableCell v-if="canEdit" class="text-right w-10">
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
                    <DropdownMenuItem
                      class="text-destructive gap-2 text-xs"
                      @select="requestDelete(row)"
                    >
                      <Trash2 class="size-3.5" />
                      {{ $t("scenes.dashboard.delete") }}
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
        <span>{{ pagination.total }} scenes</span>
        <div class="flex items-center gap-1">
          <Button
            variant="ghost"
            size="icon-sm"
            class="size-7"
            :disabled="pagination.page <= 1"
            :aria-label="$t('scenes.dashboard.previous_page')"
            :title="$t('scenes.dashboard.previous_page')"
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
            :aria-label="$t('scenes.dashboard.next_page')"
            :title="$t('scenes.dashboard.next_page')"
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
          data-phx-link="patch"
          data-phx-link-state="push"
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
