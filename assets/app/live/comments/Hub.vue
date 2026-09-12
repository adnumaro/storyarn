<script setup lang="ts">
import {
  ArrowLeft,
  ArrowUpRight,
  CheckCheck,
  ChevronRight,
  FileText,
  GitBranch,
  Lightbulb,
  LoaderCircle,
  Map,
  MessageCircle,
  MessagesSquare,
  RefreshCw,
  Search,
  X,
} from "@lucide/vue";
import { computed, onBeforeUnmount, onMounted, ref, watch } from "vue";
import { useI18n } from "vue-i18n";
import CommentConversation from "@components/comments/CommentConversation.vue";
import type { CommentUiConfig } from "@components/comments/types";
import LiveLink from "@components/navigation/LiveLink.vue";
import { Button } from "@components/ui/button";
import { useLive } from "@shared/composables/useLive";
import type { HubFilters, HubState, HubThread } from "./types";

const { state, currentUserId } = defineProps<{ state: HubState; currentUserId: number }>();
const live = useLive();
const { t, locale } = useI18n();
const filters = ref<HubFilters>({ ...state.filters });
const listPanel = ref<HTMLElement | null>(null);
const detailPanel = ref<HTMLElement | null>(null);
const refreshPending = ref(false);
const morePending = ref(false);
const filterPending = ref(false);
const selectingThreadId = ref<number | null>(null);
const interactionError = ref<string | null>(null);
let filterDraftDirty = false;
let expectedFilters: HubFilters | null = null;
let filterRequest: symbol | null = null;
let selectionRequest: symbol | null = null;
let searchTimer: ReturnType<typeof setTimeout> | null = null;
const filterClass =
  "h-8 min-w-0 rounded-md border border-input bg-background px-2 text-xs outline-none transition-colors hover:bg-accent focus-visible:ring-2 focus-visible:ring-ring";
const tools = ["sheet", "flow", "scene", "brainstorming"];
const ui: CommentUiConfig = {
  persistReplyDraft: true,
  domScope: "hub",
  i18nPrefix: "comments_hub",
  canvasSourceType: "__hub_source_label__",
  scopeThreadsKey: "threads",
  selectedSourceFallbackKey: "source_label",
};

const projects = computed(() =>
  state.projects.filter(
    (project) =>
      !filters.value.workspace_id || String(project.workspace_id) === filters.value.workspace_id,
  ),
);
const selected = computed(() =>
  state.threads.find(
    (thread) =>
      thread.id === state.selectedThreadId && thread.project_id === state.selectedProjectId,
  ),
);
const conversation = computed(() => state.conversation.thread);
const detailVisible = computed(() => state.selectedThreadId != null);
const draftStorageKey = computed(() =>
  state.selectedProjectId != null && state.selectedThreadId != null
    ? `storyarn:comments-hub:draft:${currentUserId}:${state.selectedProjectId}:${state.selectedThreadId}`
    : null,
);
const hasFilters = computed(() =>
  Boolean(
    filters.value.workspace_id ||
    filters.value.project_id ||
    filters.value.tool ||
    filters.value.search ||
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

function toolName(sourceType: string) {
  if (sourceType.startsWith("flow_")) return "flow";
  if (sourceType.startsWith("sheet_")) return "sheet";
  if (sourceType.startsWith("scene_")) return "scene";
  return "brainstorming";
}

function toolIcon(sourceType: string) {
  switch (toolName(sourceType)) {
    case "flow":
      return GitBranch;
    case "sheet":
      return FileText;
    case "scene":
      return Map;
    default:
      return Lightbulb;
  }
}

function formatDate(value: string) {
  const date = new Date(value);
  return Number.isNaN(date.valueOf())
    ? ""
    : new Intl.DateTimeFormat(locale.value, { month: "short", day: "numeric" }).format(date);
}

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

function syncFilters(value: HubFilters) {
  if (filterDraftDirty) {
    if (searchTimer != null || !expectedFilters) return;
    const matches = Object.entries(expectedFilters).every(
      ([key, expected]) => value[key as keyof HubFilters] === expected,
    );
    if (!matches) return;
  }
  filterDraftDirty = false;
  expectedFilters = null;
  filters.value = { ...value };
}

function search() {
  cancelSearch();
  filterDraftDirty = true;
  searchTimer = setTimeout(submitFilters, 250);
}

function changeWorkspace() {
  filters.value.project_id = "";
  submitFilters();
}

function resetFilters() {
  filters.value = {
    workspace_id: "",
    project_id: "",
    tool: "",
    status: "all",
    personal: "all",
    search: "",
  };
  submitFilters();
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

watch(() => state.filters, syncFilters, { deep: true });
watch(listStorageKey, (key) => restoreScroll(key, listPanel.value), { flush: "post" });
watch(detailStorageKey, (key) => restoreScroll(key, detailPanel.value), { flush: "post" });
onMounted(() => {
  restoreScroll(listStorageKey.value, listPanel.value);
  restoreScroll(detailStorageKey.value, detailPanel.value);
});
onBeforeUnmount(() => {
  cancelSearch();
  rememberScroll(listStorageKey.value, listPanel.value);
  rememberScroll(detailStorageKey.value, detailPanel.value);
});
</script>

<template>
  <section
    id="comments-hub-content"
    class="flex h-full min-h-0 flex-col bg-background"
    :aria-label="$t('comments_hub.title')"
  >
    <header class="shrink-0 border-b border-border px-4 py-5 sm:px-6">
      <div class="flex items-start justify-between gap-4">
        <div>
          <h1 class="text-xl font-semibold tracking-tight">{{ $t("comments_hub.title") }}</h1>
          <p class="mt-1 text-sm text-muted-foreground">{{ $t("comments_hub.subtitle") }}</p>
        </div>
        <Button
          id="comments-hub-refresh"
          variant="ghost"
          size="icon"
          :disabled="refreshPending"
          :aria-label="$t('comments_hub.refresh')"
          @click="refresh"
        >
          <RefreshCw class="size-4" :class="{ 'animate-spin': refreshPending }" />
        </Button>
      </div>
      <form class="mt-5 space-y-3" role="search" @submit.prevent="submitFilters">
        <div class="relative max-w-xl">
          <Search
            class="pointer-events-none absolute left-3 top-2.5 size-4 text-muted-foreground"
          />
          <input
            id="comments-hub-search"
            v-model="filters.search"
            type="search"
            maxlength="200"
            autocomplete="off"
            :aria-label="$t('comments_hub.search')"
            :placeholder="$t('comments_hub.search')"
            class="h-9 w-full rounded-md border border-input bg-muted/30 pl-9 pr-3 text-sm outline-none transition-shadow placeholder:text-muted-foreground focus-visible:ring-2 focus-visible:ring-ring"
            @input="search"
          />
        </div>
        <div class="flex flex-wrap items-center gap-2">
          <select
            id="comments-hub-workspace"
            v-model="filters.workspace_id"
            :class="filterClass"
            :aria-label="$t('comments_hub.workspace')"
            @change="changeWorkspace"
          >
            <option value="">{{ $t("comments_hub.all_workspaces") }}</option>
            <option
              v-for="workspace in state.workspaces"
              :key="workspace.id"
              :value="String(workspace.id)"
            >
              {{ workspace.name }}
            </option>
          </select>
          <select
            id="comments-hub-project"
            v-model="filters.project_id"
            :class="filterClass"
            :aria-label="$t('comments_hub.project')"
            @change="submitFilters"
          >
            <option value="">{{ $t("comments_hub.all_projects") }}</option>
            <option v-for="project in projects" :key="project.id" :value="String(project.id)">
              {{ project.name }}
            </option>
          </select>
          <select
            id="comments-hub-tool"
            v-model="filters.tool"
            :class="filterClass"
            :aria-label="$t('comments_hub.tool')"
            @change="submitFilters"
          >
            <option value="">{{ $t("comments_hub.all_tools") }}</option>
            <option v-for="tool in tools" :key="tool" :value="tool">
              {{ $t(`comments_hub.tools.${tool}`) }}
            </option>
          </select>
          <select
            id="comments-hub-status"
            v-model="filters.status"
            :class="filterClass"
            :aria-label="$t('comments_hub.status')"
            @change="submitFilters"
          >
            <option value="all">{{ $t("comments_hub.all_statuses") }}</option>
            <option value="open">{{ $t("comments_hub.open") }}</option>
            <option value="resolved">{{ $t("comments_hub.resolved") }}</option>
          </select>
          <select
            id="comments-hub-personal"
            v-model="filters.personal"
            :class="filterClass"
            :aria-label="$t('comments_hub.participation')"
            @change="submitFilters"
          >
            <option value="all">{{ $t("comments_hub.everyone") }}</option>
            <option value="participated">{{ $t("comments_hub.participated") }}</option>
            <option value="mentioned">{{ $t("comments_hub.mentioned") }}</option>
          </select>
          <Button
            v-if="hasFilters"
            id="comments-hub-reset"
            type="button"
            variant="ghost"
            size="sm"
            class="h-8 gap-1 text-xs text-muted-foreground"
            @click="resetFilters"
          >
            <X class="size-3" />{{ $t("comments_hub.clear_filters") }}
          </Button>
        </div>
      </form>
    </header>

    <p
      v-if="state.error || interactionError"
      role="alert"
      class="shrink-0 border-b border-destructive/20 bg-destructive/5 px-6 py-3 text-sm text-destructive"
    >
      {{ interactionError || state.error }}
    </p>

    <div class="flex min-h-0 flex-1">
      <div
        class="min-h-0 w-full shrink-0 flex-col border-border md:flex md:w-80 md:border-r lg:w-96"
        :class="detailVisible ? 'hidden' : 'flex'"
      >
        <div class="flex h-11 shrink-0 items-center justify-between border-b border-border/60 px-4">
          <h2 class="text-xs font-medium text-muted-foreground">
            {{ $t("comments_hub.recent_activity") }}
          </h2>
          <LoaderCircle
            v-if="filterPending"
            class="ml-2 size-3 animate-spin text-muted-foreground"
            :aria-label="$t('comments_hub.loading')"
          />
          <span class="text-[11px] text-muted-foreground">{{
            $t("comments_hub.thread_count", {
              count: state.counts?.[state.filters.status] ?? state.threads.length,
            })
          }}</span>
        </div>
        <div
          id="comments-hub-list"
          :aria-busy="filterPending"
          ref="listPanel"
          class="min-h-0 flex-1 overflow-y-auto overscroll-contain"
          @scroll="rememberScroll(listStorageKey, listPanel)"
        >
          <ol
            v-if="state.threads.length"
            :aria-label="$t('comments_hub.threads')"
            class="divide-y divide-border/60"
          >
            <li v-for="thread in state.threads" :key="`${thread.project_id}:${thread.id}`">
              <button
                :id="`comments-hub-thread-${thread.id}`"
                type="button"
                :aria-pressed="selected?.id === thread.id"
                :aria-busy="selectingThreadId === thread.id"
                class="group relative w-full px-4 py-4 text-left outline-none transition-colors hover:bg-muted/50 focus-visible:z-10 focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-ring"
                :class="
                  selected?.id === thread.id
                    ? 'bg-primary/5 after:absolute after:inset-y-0 after:left-0 after:w-0.5 after:bg-primary'
                    : ''
                "
                @click="selectThread(thread)"
              >
                <div class="mb-2 flex items-center gap-1.5 text-[11px] text-muted-foreground">
                  <span
                    class="truncate"
                    :title="`${thread.workspace_name} / ${thread.project_name}`"
                    >{{ thread.project_name }}</span
                  >
                  <ChevronRight class="size-3 shrink-0 opacity-50" />
                  <component :is="toolIcon(thread.source.type)" class="size-3 shrink-0" />
                  <span class="truncate">{{ thread.source.label }}</span>
                </div>
                <div class="flex items-start gap-2">
                  <span
                    v-if="thread.unread"
                    class="mt-1.5 size-1.5 shrink-0 rounded-full bg-primary"
                    :aria-label="$t('comments_hub.unread')"
                  />
                  <p
                    class="min-w-0 flex-1 line-clamp-2 break-words text-sm leading-relaxed"
                    :class="thread.unread ? 'font-medium' : ''"
                  >
                    {{ thread.preview || $t("comments_hub.empty_preview") }}
                  </p>
                </div>
                <p v-if="thread.context" class="mt-1.5 truncate text-xs text-muted-foreground">
                  {{ thread.context.label
                  }}<span v-if="thread.context.status === 'unavailable'">
                    · {{ $t("comments_hub.context_unavailable") }}</span
                  >
                </p>
                <div class="mt-3 flex items-center gap-2 text-[11px] text-muted-foreground">
                  <span class="min-w-0 truncate">{{ thread.author.display_name }}</span>
                  <time :datetime="thread.last_activity_at" class="shrink-0"
                    >· {{ formatDate(thread.last_activity_at) }}</time
                  >
                  <span
                    class="ml-auto inline-flex shrink-0 items-center gap-1"
                    :aria-label="$t('comments_hub.message_count', { count: thread.message_count })"
                    ><MessageCircle class="size-3" />{{ thread.message_count }}</span
                  >
                  <CheckCheck
                    v-if="thread.status === 'resolved'"
                    class="size-3.5 shrink-0"
                    :aria-label="$t('comments_hub.resolved')"
                  />
                  <LoaderCircle
                    v-if="selectingThreadId === thread.id"
                    class="size-3.5 shrink-0 animate-spin"
                  />
                </div>
                <p
                  v-if="thread.source.status === 'unavailable'"
                  class="mt-2 text-[11px] text-muted-foreground"
                >
                  {{ $t("comments_hub.source_unavailable") }}
                </p>
              </button>
            </li>
          </ol>
          <div v-else id="comments-hub-empty" class="px-6 py-16 text-center">
            <Search v-if="hasFilters" class="mx-auto mb-3 size-7 text-muted-foreground/50" />
            <MessageCircle v-else class="mx-auto mb-3 size-7 text-muted-foreground/50" />
            <h3 class="text-sm font-medium">
              {{ $t(hasFilters ? "comments_hub.no_results" : "comments_hub.empty") }}
            </h3>
            <p class="mt-2 text-xs leading-relaxed text-muted-foreground">
              {{ $t(hasFilters ? "comments_hub.no_results_hint" : "comments_hub.empty_hint") }}
            </p>
            <Button
              v-if="hasFilters"
              variant="ghost"
              size="sm"
              class="mt-3 text-xs"
              @click="resetFilters"
              >{{ $t("comments_hub.clear_filters") }}</Button
            >
          </div>
          <div v-if="state.nextCursor" class="p-3">
            <Button
              id="comments-hub-load-more"
              variant="ghost"
              size="sm"
              class="w-full text-xs"
              :disabled="morePending"
              @click="loadMore"
              >{{ $t("comments_hub.load_threads") }}</Button
            >
          </div>
        </div>
      </div>

      <div
        class="min-h-0 min-w-0 flex-1 flex-col bg-muted/10 md:flex"
        :class="detailVisible ? 'flex' : 'hidden'"
      >
        <template v-if="conversation">
          <div
            class="flex min-h-14 shrink-0 items-center gap-3 border-b border-border bg-background px-4 py-3 sm:px-6"
          >
            <Button
              id="comments-hub-back"
              variant="ghost"
              size="icon"
              class="-ml-2 shrink-0 md:hidden"
              :aria-label="$t('comments_hub.all_threads')"
              @click="live.pushEvent('hub_clear_selection', {})"
              ><ArrowLeft class="size-4"
            /></Button>
            <div class="min-w-0 flex-1">
              <p class="truncate text-xs font-medium">
                {{
                  selected?.project_name ||
                  state.projects.find((project) => project.id === state.selectedProjectId)?.name
                }}
              </p>
              <p class="mt-0.5 truncate text-[11px] text-muted-foreground">
                {{ selected?.workspace_name }}<span v-if="selected?.workspace_name"> · </span
                >{{ $t(`comments_hub.tools.${toolName(conversation.source.type)}`) }}
              </p>
            </div>
            <LiveLink
              v-if="state.contextUrl && conversation.source.status === 'available'"
              id="comments-hub-context"
              :to="state.contextUrl"
              class="inline-flex h-8 shrink-0 items-center gap-1.5 rounded-md border border-input bg-background px-3 text-xs font-medium transition-colors hover:bg-accent focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
              >{{ $t("comments_hub.view_context") }}<ArrowUpRight class="size-3.5"
            /></LiveLink>
            <span v-else class="text-xs text-muted-foreground">{{
              $t("comments_hub.source_unavailable")
            }}</span>
          </div>
          <div
            id="comments-hub-detail"
            ref="detailPanel"
            class="min-h-0 flex-1 overflow-y-auto overscroll-contain px-4 py-6 sm:px-6"
            @scroll="rememberScroll(detailStorageKey, detailPanel)"
          >
            <div class="mx-auto max-w-3xl">
              <CommentConversation
                :key="`${currentUserId}:${state.selectedProjectId}:${state.selectedThreadId}`"
                :state="state.conversation"
                :ui="ui"
                :draft-storage-key="draftStorageKey"
                embedded
              />
            </div>
          </div>
        </template>
        <div
          v-else
          class="flex min-h-0 flex-1 flex-col items-center justify-center px-8 py-16 text-center"
        >
          <div
            class="mb-5 flex size-16 items-center justify-center rounded-2xl border border-border/70 bg-background shadow-sm"
          >
            <MessagesSquare class="size-7 text-muted-foreground/60" />
          </div>
          <h2 class="text-base font-medium">
            {{
              $t(detailVisible ? "comments_hub.unavailable_title" : "comments_hub.select_thread")
            }}
          </h2>
          <p class="mt-2 max-w-xs text-sm leading-relaxed text-muted-foreground">
            {{ $t(detailVisible ? "comments_hub.unavailable" : "comments_hub.select_thread_hint") }}
          </p>
          <Button
            v-if="detailVisible"
            variant="ghost"
            size="sm"
            class="mt-4 gap-1.5 md:hidden"
            @click="live.pushEvent('hub_clear_selection', {})"
            ><ArrowLeft class="size-3.5" />{{ $t("comments_hub.all_threads") }}</Button
          >
        </div>
      </div>
    </div>
  </section>
</template>
