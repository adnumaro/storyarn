<script setup lang="ts">
import { File, FileText, GitBranch, Map as MapIcon, Search, Trash2, Undo2 } from "@lucide/vue";
import { computed, ref, watch, type Component } from "vue";
import { useI18n } from "vue-i18n";
import ConfirmDialog from "@components/ConfirmDialog.vue";
import { SettingsEmptyState, SettingsPage, SettingsSection } from "@components/settings";
import { Button } from "@components/ui/button";
import { Input } from "@components/ui/input";
import { useLive } from "@shared/composables/useLive";

type TrashItemType = "sheet" | "flow" | "scene" | "asset";
type TrashFilter = "all" | TrashItemType;

interface TrashedItem {
  id: number;
  type: TrashItemType;
  name: string;
  deleted_at: string | null;
  deletion_generation: number | null;
  content_type: string | null;
  size: number | null;
  deletion_reason: "user" | "snapshot_restore" | "system" | null;
  purge_at: string | null;
}

interface TrashPagination {
  page: number;
  pageSize: number;
  totalCount: number;
  totalPages: number;
}

type TypeCounts = Record<TrashItemType, number>;

const {
  trashedItems = [],
  pagination = { page: 1, pageSize: 25, totalCount: 0, totalPages: 1 },
  typeCounts = { sheet: 0, flow: 0, scene: 0, asset: 0 },
  activeFilter = "all",
  searchQuery = "",
  canManage = false,
} = defineProps<{
  trashedItems?: TrashedItem[];
  pagination?: TrashPagination;
  typeCounts?: TypeCounts;
  activeFilter?: TrashFilter;
  searchQuery?: string;
  canManage?: boolean;
}>();

const live = useLive();
const { t, locale } = useI18n();

const localSearchQuery = ref(searchQuery);
const showDeleteConfirm = ref(false);
const showEmptyConfirm = ref(false);
const itemToDelete = ref<TrashedItem | null>(null);
let searchDebounce: ReturnType<typeof setTimeout> | undefined;

const filters: TrashFilter[] = ["all", "sheet", "flow", "scene", "asset"];

const typeConfig = {
  sheet: {
    icon: FileText,
    class: "border-sky-500/20 bg-sky-500/10 text-sky-600 dark:text-sky-400",
  },
  flow: {
    icon: GitBranch,
    class: "border-violet-500/20 bg-violet-500/10 text-violet-600 dark:text-violet-400",
  },
  scene: {
    icon: MapIcon,
    class: "border-emerald-500/20 bg-emerald-500/10 text-emerald-600 dark:text-emerald-400",
  },
  asset: {
    icon: File,
    class: "border-amber-500/20 bg-amber-500/10 text-amber-600 dark:text-amber-400",
  },
} satisfies Record<TrashItemType, { icon: Component; class: string }>;

const itemCounts = computed<Record<TrashFilter, number>>(() => {
  const counts = {
    sheet: typeCounts.sheet ?? 0,
    flow: typeCounts.flow ?? 0,
    scene: typeCounts.scene ?? 0,
    asset: typeCounts.asset ?? 0,
  };

  return {
    all: counts.sheet + counts.flow + counts.scene + counts.asset,
    ...counts,
  };
});

const visibleFilters = computed(() =>
  filters.filter(
    (filter) => filter === "all" || filter === activeFilter || itemCounts.value[filter] > 0,
  ),
);

const hasToolbar = computed(
  () => itemCounts.value.all > 0 || localSearchQuery.value !== "" || activeFilter !== "all",
);

const pristine = computed(
  () => itemCounts.value.all === 0 && localSearchQuery.value === "" && activeFilter === "all",
);

const emptyTitle = computed(() =>
  pristine.value
    ? t("project_settings.trash.empty_title")
    : t("project_settings.trash.no_results_title"),
);

const emptyDescription = computed(() =>
  pristine.value
    ? t("project_settings.trash.empty_description")
    : t("project_settings.trash.no_results_description"),
);

const deleteConfirmDescription = computed(() => {
  if (!itemToDelete.value) return "";

  return t("project_settings.trash.delete_confirm_description", {
    type: typeLabel(itemToDelete.value.type).toLocaleLowerCase(locale.value),
    name: itemName(itemToDelete.value),
  });
});

function typeLabel(type: TrashItemType): string {
  return t(`project_settings.trash.types.${type}`);
}

function filterLabel(filter: TrashFilter): string {
  return filter === "all" ? t("project_settings.trash.filters.all") : typeLabel(filter);
}

function itemName(item: TrashedItem): string {
  return item.name || t("project_settings.trash.untitled");
}

function formatRelativeTime(datetime: string | null): string {
  if (!datetime) return "";

  const diffSeconds = Math.max(0, Math.floor((Date.now() - new Date(datetime).getTime()) / 1000));
  const formatter = new Intl.RelativeTimeFormat(locale.value, { numeric: "auto" });

  if (diffSeconds < 60) return t("project_settings.trash.just_now");
  if (diffSeconds < 3600) return formatter.format(-Math.floor(diffSeconds / 60), "minute");
  if (diffSeconds < 86400) return formatter.format(-Math.floor(diffSeconds / 3600), "hour");

  return formatter.format(-Math.floor(diffSeconds / 86400), "day");
}

function deletedLabel(item: TrashedItem): string {
  return t("project_settings.trash.deleted_label", {
    time: formatRelativeTime(item.deleted_at),
  });
}

function formatSize(bytes: number | null): string {
  if (bytes == null) return "";
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

function formatDateTime(datetime: string | null): string {
  if (!datetime) return "";

  return new Intl.DateTimeFormat(locale.value, {
    dateStyle: "medium",
    timeStyle: "short",
  }).format(new Date(datetime));
}

function deletionActorLabel(item: TrashedItem): string {
  if (item.deletion_reason === "snapshot_restore") {
    return t("project_settings.trash.deleted_by_snapshot_restore");
  }

  if (item.deletion_reason === "user") {
    return t("project_settings.trash.deleted_by_user");
  }

  return t("project_settings.trash.deleted_by_system");
}

function mutationPayload(item: TrashedItem) {
  const payload: { type: TrashItemType; id: number; generation?: number } = {
    type: item.type,
    id: item.id,
  };

  if (item.type === "asset" && item.deletion_generation != null) {
    payload.generation = item.deletion_generation;
  }

  return payload;
}

function restoreItem(item: TrashedItem): void {
  live.pushEvent("restore_item", mutationPayload(item));
}

function setFilter(filter: TrashFilter): void {
  live.pushEvent("set_trash_filter", { type: filter });
}

function onSearchInput(event: Event): void {
  localSearchQuery.value = (event.target as HTMLInputElement).value;

  if (searchDebounce) clearTimeout(searchDebounce);

  searchDebounce = setTimeout(() => {
    live.pushEvent("search_trash", { query: localSearchQuery.value });
  }, 250);
}

function goToPage(page: number): void {
  if (page < 1 || page > pagination.totalPages || page === pagination.page) return;

  live.pushEvent("change_trash_page", { page });
}

const paginationPages = computed(() => {
  const total = pagination.totalPages;
  const current = pagination.page;

  if (total <= 7) {
    return Array.from({ length: total }, (_, index) => index + 1);
  }

  const start = Math.max(1, Math.min(current - 3, total - 6));
  return Array.from({ length: 7 }, (_, index) => start + index);
});

function openDeleteConfirm(item: TrashedItem): void {
  itemToDelete.value = item;
  showDeleteConfirm.value = true;
}

function confirmDelete(): void {
  if (!itemToDelete.value) return;

  live.pushEvent("delete_item", mutationPayload(itemToDelete.value));
  itemToDelete.value = null;
}

function emptyTrash(): void {
  live.pushEvent("empty_trash", {});
}

watch(
  () => searchQuery,
  (value) => {
    localSearchQuery.value = value;
  },
);
</script>

<template>
  <SettingsPage :title="t('project_settings.trash.page_title')">
    <template #actions>
      <Button
        v-if="canManage && itemCounts.all > 0"
        variant="destructive"
        size="sm"
        data-testid="empty-trash-trigger"
        @click="showEmptyConfirm = true"
      >
        <Trash2 class="size-4" aria-hidden="true" />
        {{ t("project_settings.trash.empty_trash") }}
      </Button>
    </template>

    <div v-if="hasToolbar" class="flex flex-col gap-3 lg:flex-row lg:items-center">
      <div class="relative min-w-0 flex-1">
        <Search
          class="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground"
          aria-hidden="true"
        />
        <Input
          :model-value="localSearchQuery"
          type="search"
          class="pl-9"
          :placeholder="t('project_settings.trash.search_placeholder')"
          :aria-label="t('project_settings.trash.search_placeholder')"
          @input="onSearchInput"
        />
      </div>

      <div
        class="flex flex-wrap items-center gap-1 rounded-lg border border-border bg-muted/40 p-1"
        role="group"
      >
        <button
          v-for="filter in visibleFilters"
          :key="filter"
          :data-testid="`trash-filter-${filter}`"
          type="button"
          :aria-pressed="activeFilter === filter"
          :class="[
            'inline-flex h-7 items-center gap-1.5 rounded-md px-2.5 text-xs font-medium transition-colors',
            activeFilter === filter
              ? 'bg-background text-foreground shadow-sm'
              : 'text-muted-foreground hover:text-foreground',
          ]"
          @click="setFilter(filter)"
        >
          <span>{{ filterLabel(filter) }}</span>
          <span class="tabular-nums text-muted-foreground">{{ itemCounts[filter] }}</span>
        </button>
      </div>
    </div>

    <SettingsSection
      :title="t('project_settings.trash.items_section')"
      :hint="t('project_settings.trash.count_summary', { count: pagination.totalCount })"
    >
      <SettingsEmptyState
        v-if="trashedItems.length === 0"
        :icon="Trash2"
        :title="emptyTitle"
        :text="emptyDescription"
      />

      <div
        v-for="item in trashedItems"
        :key="`${item.type}-${item.id}`"
        :data-testid="`trash-item-${item.type}-${item.id}`"
        class="grid grid-cols-1 items-center gap-x-6 gap-y-2 px-4 py-3 sm:grid-cols-[minmax(0,1fr)_auto]"
      >
        <div class="flex min-w-0 items-center gap-3">
          <div
            :class="[
              'flex size-9 shrink-0 items-center justify-center rounded-lg border',
              typeConfig[item.type].class,
            ]"
          >
            <component :is="typeConfig[item.type].icon" class="size-4" aria-hidden="true" />
          </div>

          <div class="min-w-0">
            <div class="flex min-w-0 items-center gap-2">
              <span class="truncate font-medium">{{ itemName(item) }}</span>
              <span
                :class="[
                  'inline-flex items-center rounded-md border px-1.5 py-0.5 text-[11px] font-medium',
                  typeConfig[item.type].class,
                ]"
              >
                {{ typeLabel(item.type) }}
              </span>
            </div>
            <div class="text-[13px] text-muted-foreground">
              <time :datetime="item.deleted_at || undefined">{{ deletedLabel(item) }}</time>
              <template v-if="item.type === 'asset'">
                <span aria-hidden="true"> · </span>
                <span v-if="item.content_type">{{ item.content_type }}</span>
                <span v-if="item.content_type && item.size != null" aria-hidden="true"> · </span>
                <span v-if="item.size != null">{{ formatSize(item.size) }}</span>
                <span aria-hidden="true"> · </span>
                <span>{{ deletionActorLabel(item) }}</span>
              </template>
            </div>
            <div v-if="item.purge_at" class="text-[13px] text-muted-foreground">
              {{
                t("project_settings.trash.recoverable_until", {
                  date: formatDateTime(item.purge_at),
                })
              }}
            </div>
          </div>
        </div>

        <div v-if="canManage" class="flex items-center justify-end gap-1">
          <Button
            variant="ghost"
            size="sm"
            :data-testid="`restore-${item.type}-${item.id}`"
            @click="restoreItem(item)"
          >
            <Undo2 class="size-4" aria-hidden="true" />
            {{ t("project_settings.trash.restore") }}
          </Button>
          <Button
            variant="ghost"
            size="sm"
            class="text-destructive hover:bg-destructive/10 hover:text-destructive"
            :data-testid="`delete-${item.type}-${item.id}`"
            @click="openDeleteConfirm(item)"
          >
            <Trash2 class="size-4" aria-hidden="true" />
            {{ t("project_settings.trash.delete") }}
          </Button>
        </div>
      </div>

      <template v-if="pagination.totalPages > 1" #footer>
        <span class="flex flex-wrap items-center justify-between gap-2">
          <span>
            {{
              t("project_settings.trash.page_of", {
                page: pagination.page,
                total: pagination.totalPages,
              })
            }}
          </span>
          <span class="flex items-center gap-1">
            <Button
              variant="ghost"
              size="sm"
              :disabled="pagination.page <= 1"
              @click="goToPage(pagination.page - 1)"
            >
              {{ t("project_settings.trash.previous") }}
            </Button>
            <Button
              v-for="page in paginationPages"
              :key="page"
              :variant="page === pagination.page ? 'secondary' : 'ghost'"
              size="sm"
              class="min-w-8"
              @click="goToPage(page)"
            >
              {{ page }}
            </Button>
            <Button
              variant="ghost"
              size="sm"
              :disabled="pagination.page >= pagination.totalPages"
              @click="goToPage(pagination.page + 1)"
            >
              {{ t("project_settings.trash.next") }}
            </Button>
          </span>
        </span>
      </template>
    </SettingsSection>

    <ConfirmDialog
      v-model:open="showDeleteConfirm"
      :title="t('project_settings.trash.delete_confirm_title')"
      :description="deleteConfirmDescription"
      :confirm-text="t('project_settings.trash.delete')"
      :cancel-text="t('project_settings.trash.cancel')"
      variant="destructive"
      :icon="Trash2"
      @confirm="confirmDelete"
      @cancel="itemToDelete = null"
    />

    <ConfirmDialog
      v-model:open="showEmptyConfirm"
      :title="t('project_settings.trash.empty_confirm_title')"
      :description="t('project_settings.trash.empty_confirm_description')"
      :confirm-text="t('project_settings.trash.empty_trash')"
      :cancel-text="t('project_settings.trash.cancel')"
      variant="destructive"
      :icon="Trash2"
      @confirm="emptyTrash"
    />
  </SettingsPage>
</template>
