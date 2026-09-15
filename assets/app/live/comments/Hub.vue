<script setup lang="ts">
import { LoaderCircle, MessageCircle, Search } from "@lucide/vue";
import { computed, onBeforeUnmount, onMounted, ref, watch } from "vue";
import { useI18n } from "vue-i18n";
import { Button } from "@components/ui/button";
import { useLive } from "@shared/composables/useLive";
import HubDetail from "./HubDetail.vue";
import HubFilters from "./HubFilters.vue";
import HubRow from "./HubRow.vue";
import type { HubFilters as Filters, HubState, HubThread } from "./types";

const { state, currentUserId } = defineProps<{ state: HubState; currentUserId: number }>();
const emit = defineEmits<{ close: [] }>();
const live = useLive();
const { t } = useI18n();
const filters = ref<Filters>({ ...state.filters });
const root = ref<HTMLElement | null>(null);
const listPanel = ref<HTMLElement | null>(null);
const refreshPending = ref(false);
const morePending = ref(false);
const filterPending = ref(false);
const selectingThreadId = ref<number | null>(null);
const interactionError = ref<string | null>(null);
let filterDraftDirty = false;
let expectedFilters: Filters | null = null;
let filterRequest: symbol | null = null;
let selectionRequest: symbol | null = null;
let searchTimer: ReturnType<typeof setTimeout> | null = null;

const selected = computed(() =>
  state.threads.find(
    (thread) =>
      thread.id === state.selectedThreadId && thread.project_id === state.selectedProjectId,
  ),
);
const detailVisible = computed(() => state.selectedThreadId != null);
const draftStorageKey = computed(() =>
  state.selectedProjectId != null && state.selectedThreadId != null
    ? `storyarn:comments-hub:draft:${currentUserId}:${state.selectedProjectId}:${state.selectedThreadId}`
    : null,
);
const hasFilters = computed(() =>
  Boolean(
    filters.value.tool ||
    filters.value.search ||
    filters.value.unread ||
    filters.value.following ||
    filters.value.status !== "all" ||
    filters.value.personal !== "all",
  ),
);
const listStorageKey = computed(
  () => `storyarn:comments-hub:scroll:${currentUserId}:${JSON.stringify(state.filters)}`,
);
const detailStorageKey = computed(
  () =>
    `storyarn:comments-hub:detail-scroll:${currentUserId}:${state.selectedProjectId}:${state.selectedThreadId}`,
);
const scopeName = computed(() => {
  const project = state.projects.find((item) => String(item.id) === state.filters.project_id);
  if (project) return project.name;
  const workspace = state.workspaces.find((item) => String(item.id) === state.filters.workspace_id);
  return workspace ? workspace.name : t("comments_hub.all_projects");
});
const activeFilterSummary = computed(() =>
  [
    state.filters.tool ? t(`comments_hub.tools.${state.filters.tool}`) : null,
    state.filters.status !== "all" ? t(`comments_hub.${state.filters.status}`) : null,
    state.filters.unread ? t("comments_hub.unread") : null,
    state.filters.personal !== "all" ? t(`comments_hub.${state.filters.personal}`) : null,
    state.filters.following ? t("comments_hub.following") : null,
  ]
    .filter((label): label is string => label != null)
    .join(" · "),
);
const noResultsCopy = computed(() =>
  state.filters.search
    ? t("comments_hub.no_results_detail", {
        scope: scopeName.value,
        query: state.filters.search,
        filters: activeFilterSummary.value || t("comments_hub.all"),
      })
    : t("comments_hub.no_results_scope", { scope: scopeName.value }),
);
const emptyScopeCopy = computed(() =>
  t("comments_hub.empty_project_hint", { project: scopeName.value }),
);

function cancelSearch() {
  if (searchTimer != null) clearTimeout(searchTimer);
  searchTimer = null;
}

function submitFilters() {
  cancelSearch();
  filterDraftDirty = true;
  filterRequest = null;
  expectedFilters = null;
  filterPending.value = false;
  if (new TextEncoder().encode(filters.value.search).length > 200) {
    interactionError.value = t("comments_hub.search_too_long");
    return;
  }
  const request = Symbol();
  filterRequest = request;
  expectedFilters = { ...filters.value, search: filters.value.search.trim() };
  filterPending.value = true;
  interactionError.value = null;
  live.pushEvent(
    "hub_filter",
    { ...filters.value },
    () => {
      if (filterRequest !== request) return;
      filterRequest = null;
      filterPending.value = false;
      syncFilters(state.filters);
    },
    () => {
      if (filterRequest !== request) return;
      filterRequest = null;
      filterPending.value = false;
      interactionError.value = t("comments_hub.filter_failed");
    },
  );
}

function syncFilters(value: Filters) {
  if (filterDraftDirty) {
    if (searchTimer != null || !expectedFilters) return;
    const matches = Object.entries(expectedFilters).every(
      ([key, expected]) => value[key as keyof Filters] === expected,
    );
    if (!matches) return;
  }
  filterDraftDirty = false;
  expectedFilters = null;
  filters.value = { ...value };
}

function changeFilters(next: Filters) {
  filters.value = next;
  submitFilters();
}

function search(value: string) {
  filters.value = { ...filters.value, search: value };
  cancelSearch();
  filterDraftDirty = true;
  searchTimer = setTimeout(submitFilters, 250);
}

function resetFilters() {
  changeFilters({
    workspace_id: filters.value.workspace_id,
    project_id: filters.value.project_id,
    tool: "",
    status: "all",
    personal: "all",
    unread: "",
    following: "",
    search: "",
  });
}

function selectThread(thread: HubThread) {
  rememberScroll(listStorageKey.value, listPanel.value);
  const request = Symbol();
  selectionRequest = request;
  selectingThreadId.value = thread.id;
  interactionError.value = null;
  live.pushEvent(
    "hub_select",
    { thread_id: thread.id, project_id: thread.project_id },
    () => {
      if (selectionRequest !== request) return;
      selectionRequest = null;
      selectingThreadId.value = null;
    },
    () => {
      if (selectionRequest !== request) return;
      selectionRequest = null;
      selectingThreadId.value = null;
      interactionError.value = t("comments_hub.selection_failed");
    },
  );
}

function refresh() {
  if (refreshPending.value) return;
  refreshPending.value = true;
  const complete = () => {
    refreshPending.value = false;
  };
  live.pushEvent("hub_refresh", {}, complete, complete);
}

function loadMore() {
  if (morePending.value) return;
  morePending.value = true;
  const complete = () => {
    morePending.value = false;
  };
  live.pushEvent("hub_load_more", {}, complete, complete);
}

function detailPanel(): HTMLElement | null {
  return root.value?.querySelector<HTMLElement>("#comments-hub-detail") ?? null;
}

function rememberScroll(key: string, panel: HTMLElement | null) {
  if (!panel || typeof window === "undefined") return;
  try {
    window.sessionStorage.setItem(key, String(panel.scrollTop));
  } catch {
    // Navigation remains available when browser storage is disabled.
  }
}

function restoreScroll(key: string, panel: HTMLElement | null) {
  if (!panel || typeof window === "undefined") return;
  try {
    const value = Number(window.sessionStorage.getItem(key));
    panel.scrollTop = Number.isFinite(value) && value > 0 ? value : 0;
  } catch {
    panel.scrollTop = 0;
  }
}

function onDetailScroll(event: Event) {
  if ((event.target as HTMLElement | null)?.id === "comments-hub-detail") {
    rememberScroll(detailStorageKey.value, event.target as HTMLElement);
  }
}

watch(() => state.filters, syncFilters, { deep: true });
watch(listStorageKey, (key) => restoreScroll(key, listPanel.value), { flush: "post" });
watch(detailStorageKey, (key) => restoreScroll(key, detailPanel()), { flush: "post" });
onMounted(() => {
  restoreScroll(listStorageKey.value, listPanel.value);
  restoreScroll(detailStorageKey.value, detailPanel());
});
onBeforeUnmount(() => {
  cancelSearch();
  rememberScroll(listStorageKey.value, listPanel.value);
  rememberScroll(detailStorageKey.value, detailPanel());
});
</script>

<template>
  <section
    id="comments-hub-content"
    ref="root"
    class="flex h-full min-h-0 flex-col bg-card"
    :aria-label="$t('comments_hub.title')"
  >
    <HubFilters
      :class="detailVisible ? 'hidden md:block' : ''"
      :filters="filters"
      :counts="state.counts ?? null"
      :workspaces="state.workspaces"
      :projects="state.projects"
      :refresh-pending="refreshPending"
      @change="changeFilters"
      @search="search"
      @refresh="refresh"
      @close="emit('close')"
    />

    <p
      v-if="state.error || interactionError"
      role="alert"
      class="shrink-0 border-b border-destructive/20 bg-destructive/5 px-5 py-2.5 text-sm text-destructive"
    >
      {{ interactionError || state.error }}
    </p>

    <div class="flex min-h-0 flex-1">
      <div
        class="min-h-0 w-full shrink-0 flex-col border-border md:flex md:w-[400px] md:border-r"
        :class="detailVisible ? 'hidden' : 'flex'"
      >
        <div
          v-if="state.threads.length"
          class="flex h-9 shrink-0 items-center gap-2 border-b border-border px-4 text-[11px] text-muted-foreground"
        >
          <span class="font-medium text-foreground">{{
            $t("comments_hub.thread_count", {
              count: state.counts?.[state.filters.status] ?? state.threads.length,
            })
          }}</span>
          <span aria-hidden="true">·</span>
          <span class="truncate">{{ $t("comments_hub.list_hint") }}</span>
          <LoaderCircle
            v-if="filterPending"
            class="ml-auto size-3 shrink-0 animate-spin"
            :aria-label="$t('comments_hub.loading')"
          />
        </div>
        <div
          id="comments-hub-list"
          ref="listPanel"
          :aria-busy="filterPending"
          class="min-h-0 flex-1 overflow-y-auto overscroll-contain"
          @scroll="rememberScroll(listStorageKey, listPanel)"
        >
          <ol
            v-if="state.threads.length"
            :aria-label="$t('comments_hub.threads')"
            class="divide-y divide-border"
          >
            <li v-for="thread in state.threads" :key="`${thread.project_id}:${thread.id}`">
              <HubRow
                :thread="thread"
                :selected="selected?.id === thread.id"
                :busy="selectingThreadId === thread.id"
                @select="selectThread"
              />
            </li>
          </ol>
          <div
            v-else
            id="comments-hub-empty"
            class="flex flex-col items-center gap-2.5 px-8 py-16 text-center"
          >
            <div
              class="flex size-11 items-center justify-center rounded-xl bg-muted text-muted-foreground"
            >
              <Search v-if="hasFilters" class="size-5" />
              <MessageCircle v-else class="size-5" />
            </div>
            <h3 class="text-[15px] font-semibold">
              {{ $t(hasFilters ? "comments_hub.no_results" : "comments_hub.empty") }}
            </h3>
            <p class="max-w-xs text-[13px] leading-relaxed text-muted-foreground">
              {{ hasFilters ? noResultsCopy : emptyScopeCopy }}
            </p>
            <Button
              v-if="hasFilters"
              id="comments-hub-clear"
              variant="outline"
              size="sm"
              class="mt-1"
              @click="resetFilters"
              >{{ $t("comments_hub.clear_filters") }}</Button
            >
          </div>
          <div v-if="state.nextCursor" class="flex justify-center p-3">
            <Button
              id="comments-hub-load-more"
              variant="ghost"
              size="sm"
              class="text-xs"
              :disabled="morePending"
              @click="loadMore"
              >{{ $t("comments_hub.load_threads") }}</Button
            >
          </div>
        </div>
      </div>

      <div
        class="min-h-0 min-w-0 flex-1 flex-col md:flex"
        :class="detailVisible ? 'flex' : 'hidden'"
        @scroll.capture="onDetailScroll"
      >
        <HubDetail
          :state="state"
          :selected="selected ?? null"
          :current-user-id="currentUserId"
          :draft-storage-key="draftStorageKey"
          :detail-visible="detailVisible"
          @back="live.pushEvent('hub_clear_selection', {})"
        />
      </div>
    </div>
  </section>
</template>
