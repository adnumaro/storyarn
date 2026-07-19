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
import DashboardPanel from "@shell/DashboardPanel.vue";
import DashboardStatCard from "@shell/DashboardStatCard.vue";

const { t } = useI18n();

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
      testId: "scene-stat-total",
      value: stats.scene_count,
    },
    {
      icon: Pentagon,
      label: t("scenes.dashboard.zones"),
      testId: "scene-stat-zones",
      value: stats.zone_count,
    },
    {
      icon: MapPin,
      label: t("scenes.dashboard.pins"),
      testId: "scene-stat-pins",
      value: stats.pin_count,
    },
    {
      icon: Image,
      label: t("scenes.dashboard.backgrounds"),
      testId: "scene-stat-backgrounds",
      value: stats.background_count,
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
    :icon="MapIcon"
    :loading="!stats"
    :is-empty="pagination.total === 0 && !stats"
    :empty-icon="MapIcon"
    :empty-message="$t('scenes.dashboard.empty')"
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

    <DashboardPanel :title="$t('scenes.dashboard.all_scenes')" :icon="MapIcon" :padded="false">
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
                  :href="sceneHref(row)"
                  data-phx-link="patch"
                  data-phx-link-state="push"
                  class="font-medium transition-colors hover:text-primary"
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
      <template v-if="pagination.totalPages > 1" #footer>
        <div class="flex items-center justify-between text-xs text-muted-foreground">
          <span>{{ $t("scenes.dashboard.total_scenes", pagination.total) }}</span>
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
      </template>
    </DashboardPanel>

    <DashboardPanel
      v-if="issues.length > 0"
      :title="$t('scenes.dashboard.issues')"
      :icon="AlertTriangle"
      :padded="false"
    >
      <div class="divide-y divide-border/60">
        <a
          v-for="(issue, i) in issues"
          :key="i"
          :href="issue.href"
          data-phx-link="patch"
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
