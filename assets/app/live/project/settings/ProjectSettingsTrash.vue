<script setup lang="ts">
import {
  AlertTriangle,
  FileText,
  GitBranch,
  Map as MapIcon,
  ScrollText,
  Search,
  Trash2,
  Undo2,
} from "lucide-vue-next";
import { computed, ref, watch, type Component } from "vue";
import { useI18n } from "vue-i18n";
import { Button } from "@components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@components/ui/dialog";
import { useLive } from "@shared/composables/useLive";

type TrashItemType = "sheet" | "flow" | "scene" | "screenplay";
type TrashFilter = "all" | TrashItemType;

interface TrashedItem {
  id: number;
  type: TrashItemType;
  name: string;
  deleted_at: string | null;
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
  typeCounts = { sheet: 0, flow: 0, scene: 0, screenplay: 0 },
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

const filters: TrashFilter[] = ["all", "sheet", "flow", "scene", "screenplay"];

const typeConfig = {
  sheet: {
    icon: FileText,
    class: "border-sky-500/20 bg-sky-500/10 text-sky-400",
  },
  flow: {
    icon: GitBranch,
    class: "border-violet-500/20 bg-violet-500/10 text-violet-400",
  },
  scene: {
    icon: MapIcon,
    class: "border-emerald-500/20 bg-emerald-500/10 text-emerald-400",
  },
  screenplay: {
    icon: ScrollText,
    class: "border-amber-500/20 bg-amber-500/10 text-amber-400",
  },
} satisfies Record<TrashItemType, { icon: Component; class: string }>;

const itemCounts = computed<Record<TrashFilter, number>>(() => {
  const counts = {
    sheet: typeCounts.sheet ?? 0,
    flow: typeCounts.flow ?? 0,
    scene: typeCounts.scene ?? 0,
    screenplay: typeCounts.screenplay ?? 0,
  };

  return {
    all: counts.sheet + counts.flow + counts.scene + counts.screenplay,
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

const emptyTitle = computed(() =>
  itemCounts.value.all === 0 && localSearchQuery.value === "" && activeFilter === "all"
    ? t("project_settings.trash.empty_title")
    : t("project_settings.trash.no_results_title"),
);

const emptyDescription = computed(() =>
  itemCounts.value.all === 0 && localSearchQuery.value === "" && activeFilter === "all"
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

function typeLabel(type: TrashItemType) {
  return t(`project_settings.trash.types.${type}`);
}

function filterLabel(filter: TrashFilter) {
  return filter === "all" ? t("project_settings.trash.filters.all") : typeLabel(filter);
}

function itemName(item: TrashedItem) {
  return item.name || t("project_settings.trash.untitled");
}

function formatRelativeTime(datetime: string | null) {
  if (!datetime) return "";

  const diffSeconds = Math.max(0, Math.floor((Date.now() - new Date(datetime).getTime()) / 1000));
  const formatter = new Intl.RelativeTimeFormat(locale.value, { numeric: "auto" });

  if (diffSeconds < 60) return t("project_settings.trash.just_now");
  if (diffSeconds < 3600) return formatter.format(-Math.floor(diffSeconds / 60), "minute");
  if (diffSeconds < 86400) return formatter.format(-Math.floor(diffSeconds / 3600), "hour");

  return formatter.format(-Math.floor(diffSeconds / 86400), "day");
}

function deletedLabel(item: TrashedItem) {
  return t("project_settings.trash.deleted_label", {
    time: formatRelativeTime(item.deleted_at),
  });
}

function restoreItem(item: TrashedItem) {
  live.pushEvent("restore_item", { type: item.type, id: item.id });
}

function setFilter(filter: TrashFilter) {
  live.pushEvent("set_trash_filter", { type: filter });
}

function onSearchInput(event: Event) {
  localSearchQuery.value = (event.target as HTMLInputElement).value;

  if (searchDebounce) clearTimeout(searchDebounce);

  searchDebounce = setTimeout(() => {
    live.pushEvent("search_trash", { query: localSearchQuery.value });
  }, 250);
}

function goToPage(page: number) {
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

function openDeleteConfirm(item: TrashedItem) {
  itemToDelete.value = item;
  showDeleteConfirm.value = true;
}

function closeDeleteConfirm() {
  showDeleteConfirm.value = false;
  itemToDelete.value = null;
}

function confirmDelete() {
  if (!itemToDelete.value) return;

  live.pushEvent("delete_item", {
    type: itemToDelete.value.type,
    id: itemToDelete.value.id,
  });

  closeDeleteConfirm();
}

function emptyTrash() {
  live.pushEvent("empty_trash", {});
  showEmptyConfirm.value = false;
}

watch(
  () => searchQuery,
  (value) => {
    localSearchQuery.value = value;
  },
);
</script>

<template>
  <div class="space-y-4">
    <div v-if="hasToolbar" class="space-y-3">
      <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <p class="text-sm text-muted-foreground">
          {{ t("project_settings.trash.count_summary", { count: pagination.totalCount }) }}
        </p>

        <Button
          v-if="canManage && itemCounts.all > 0"
          variant="destructive"
          @click="showEmptyConfirm = true"
        >
          <Trash2 class="mr-2 size-4" />
          {{ t("project_settings.trash.empty_trash") }}
        </Button>
      </div>

      <div class="flex flex-col gap-3 lg:flex-row lg:items-center lg:justify-between">
        <label class="relative block min-w-0 flex-1">
          <Search
            class="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground"
          />
          <input
            :value="localSearchQuery"
            type="search"
            class="h-9 w-full rounded-md border border-border bg-background pl-9 pr-3 text-sm outline-none transition-colors placeholder:text-muted-foreground/70 focus:border-ring focus:ring-2 focus:ring-ring/20"
            :placeholder="t('project_settings.trash.search_placeholder')"
            @input="onSearchInput"
          />
        </label>

        <div class="flex flex-wrap items-center gap-1">
          <button
            v-for="filter in visibleFilters"
            :key="filter"
            type="button"
            :class="[
              'inline-flex h-8 items-center gap-1.5 rounded-md border px-2.5 text-xs font-medium transition-colors',
              activeFilter === filter
                ? 'border-border bg-muted text-foreground'
                : 'border-transparent text-muted-foreground hover:bg-muted/70 hover:text-foreground',
            ]"
            @click="setFilter(filter)"
          >
            <span>{{ filterLabel(filter) }}</span>
            <span class="text-muted-foreground">{{ itemCounts[filter] }}</span>
          </button>
        </div>
      </div>
    </div>

    <div
      v-if="trashedItems.length === 0"
      class="flex flex-col items-center justify-center py-20 text-center"
    >
      <Trash2 class="mb-4 size-10 text-muted-foreground/40" />
      <h3 class="text-lg font-medium text-muted-foreground">
        {{ emptyTitle }}
      </h3>
      <p class="mt-1 max-w-md text-sm text-muted-foreground/70">
        {{ emptyDescription }}
      </p>
    </div>

    <div v-else class="space-y-2">
      <article
        v-for="item in trashedItems"
        :key="`${item.type}-${item.id}`"
        class="flex items-center justify-between gap-4 rounded-lg border border-border/60 bg-muted/35 p-3 transition-colors hover:bg-muted/55"
      >
        <div class="flex min-w-0 items-center gap-3">
          <div
            :class="[
              'flex size-10 shrink-0 items-center justify-center rounded-lg border',
              typeConfig[item.type].class,
            ]"
          >
            <component :is="typeConfig[item.type].icon" class="size-4" />
          </div>

          <div class="min-w-0">
            <div class="mb-1 flex min-w-0 items-center gap-2">
              <p class="truncate font-medium">{{ itemName(item) }}</p>
              <span
                :class="[
                  'inline-flex items-center rounded-md border px-1.5 py-0.5 text-xs font-medium',
                  typeConfig[item.type].class,
                ]"
              >
                {{ typeLabel(item.type) }}
              </span>
            </div>
            <p class="text-sm text-muted-foreground">
              <time :datetime="item.deleted_at || undefined">{{ deletedLabel(item) }}</time>
            </p>
          </div>
        </div>

        <div v-if="canManage" class="flex shrink-0 items-center gap-2">
          <Button variant="ghost" size="sm" @click="restoreItem(item)">
            <Undo2 class="mr-1 size-4" />
            {{ t("project_settings.trash.restore") }}
          </Button>
          <Button
            variant="ghost"
            size="sm"
            class="text-destructive hover:bg-destructive/10"
            @click="openDeleteConfirm(item)"
          >
            <Trash2 class="mr-1 size-4" />
            {{ t("project_settings.trash.delete") }}
          </Button>
        </div>
      </article>
    </div>

    <div
      v-if="pagination.totalPages > 1"
      class="flex flex-col gap-3 border-t border-border/60 pt-4 sm:flex-row sm:items-center sm:justify-between"
    >
      <span class="text-sm text-muted-foreground">
        {{
          t("project_settings.trash.page_of", {
            page: pagination.page,
            total: pagination.totalPages,
          })
        }}
      </span>

      <div class="flex items-center gap-1">
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
          :variant="page === pagination.page ? 'default' : 'ghost'"
          size="sm"
          class="min-w-9"
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
      </div>
    </div>

    <Dialog v-model:open="showDeleteConfirm">
      <DialogContent>
        <DialogHeader>
          <DialogTitle class="flex items-center gap-2">
            <AlertTriangle class="size-5 text-destructive" />
            {{ t("project_settings.trash.delete_confirm_title") }}
          </DialogTitle>
          <DialogDescription>
            {{ deleteConfirmDescription }}
          </DialogDescription>
        </DialogHeader>
        <DialogFooter>
          <Button variant="outline" @click="closeDeleteConfirm">
            {{ t("project_settings.trash.cancel") }}
          </Button>
          <Button variant="destructive" @click="confirmDelete">
            {{ t("project_settings.trash.delete") }}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>

    <Dialog v-model:open="showEmptyConfirm">
      <DialogContent>
        <DialogHeader>
          <DialogTitle class="flex items-center gap-2">
            <AlertTriangle class="size-5 text-destructive" />
            {{ t("project_settings.trash.empty_confirm_title") }}
          </DialogTitle>
          <DialogDescription>
            {{ t("project_settings.trash.empty_confirm_description") }}
          </DialogDescription>
        </DialogHeader>
        <DialogFooter>
          <Button variant="outline" @click="showEmptyConfirm = false">
            {{ t("project_settings.trash.cancel") }}
          </Button>
          <Button variant="destructive" @click="emptyTrash">
            {{ t("project_settings.trash.empty_trash") }}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  </div>
</template>
