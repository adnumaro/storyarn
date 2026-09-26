<script setup lang="ts">
import {
  AtSign,
  Bell,
  CheckCheck,
  ChevronDown,
  ChevronRight,
  ChevronsUpDown,
  CircleDot,
  Folder,
  MessagesSquare,
  RefreshCw,
  Search,
  SlidersHorizontal,
  X,
} from "@lucide/vue";
import { computed, ref } from "vue";
import { useI18n } from "vue-i18n";
import { commentTool, type CommentToolKey } from "@components/comments/commentTool";
import { Button } from "@components/ui/button";
import HubChip from "./HubChip.vue";
import type { HubCounts, HubFilters, HubProjectOption, HubWorkspaceOption } from "./types";

interface ActiveChip {
  key: string;
  label: string;
  clear: () => void;
}

/**
 * The hub header: title, scope, search and the visible, countable filter bar.
 * Every chip says how many conversations it would show if it were selected.
 */
const { filters, counts, workspaces, projects, refreshPending } = defineProps<{
  filters: HubFilters;
  counts: HubCounts | null;
  workspaces: HubWorkspaceOption[];
  projects: HubProjectOption[];
  refreshPending: boolean;
}>();
const emit = defineEmits<{
  change: [filters: HubFilters];
  search: [value: string];
  refresh: [];
  close: [];
}>();
const { t } = useI18n();
const tools: CommentToolKey[] = ["sheet", "flow", "scene", "brainstorming"];
const moreOpen = ref(false);

const scopeValue = computed(() => {
  if (filters.project_id) return `project:${filters.project_id}`;
  if (filters.workspace_id) return `workspace:${filters.workspace_id}`;
  return "all";
});
const scopeName = computed(() => {
  const project = projects.find((item) => String(item.id) === filters.project_id);
  if (project) return project.name;
  const workspace = workspaces.find((item) => String(item.id) === filters.workspace_id);
  return workspace ? workspace.name : t("comments_hub.all_projects");
});
const activeChips = computed<ActiveChip[]>(() => {
  const chips: ActiveChip[] = [];
  if (filters.tool)
    chips.push({
      key: "tool",
      label: t(`comments_hub.tools.${filters.tool}`),
      clear: () => patch({ tool: "" }),
    });
  if (filters.status !== "all")
    chips.push({
      key: "status",
      label: t(`comments_hub.${filters.status}`),
      clear: () => patch({ status: "all" }),
    });
  if (filters.unread === "1")
    chips.push({
      key: "unread",
      label: t("comments_hub.unread"),
      clear: () => patch({ unread: "" }),
    });
  if (filters.personal !== "all")
    chips.push({
      key: "personal",
      label: t(`comments_hub.${filters.personal}`),
      clear: () => patch({ personal: "all" }),
    });
  if (filters.following === "1")
    chips.push({
      key: "following",
      label: t("comments_hub.following"),
      clear: () => patch({ following: "" }),
    });
  return chips;
});
const hasFilters = computed(() => activeChips.value.length > 0 || filters.search.length > 0);

function patch(changes: Partial<HubFilters>) {
  emit("change", { ...filters, ...changes });
}

function changeScope(event: Event) {
  const [kind, id = ""] = (event.target as HTMLSelectElement).value.split(":");
  const project = projects.find((item) => String(item.id) === id);
  let workspaceId = "";
  if (kind === "workspace") workspaceId = id;
  else if (kind === "project" && project) workspaceId = String(project.workspace_id);
  patch({ project_id: kind === "project" ? id : "", workspace_id: workspaceId });
}

function toggleStatus(status: "open" | "resolved") {
  patch({ status: filters.status === status ? "all" : status });
}

function togglePersonal(value: "participated" | "mentioned") {
  patch({ personal: filters.personal === value ? "all" : value });
}

function reset() {
  patch({ tool: "", status: "all", personal: "all", unread: "", following: "", search: "" });
}

defineExpose({ reset });
</script>

<template>
  <header class="shrink-0 border-b border-border bg-card">
    <div class="flex h-12 items-center gap-3 px-3 sm:px-5">
      <MessagesSquare class="hidden size-4 shrink-0 text-muted-foreground sm:block" />
      <h1 class="shrink-0 text-[15px] font-semibold tracking-tight">
        {{ $t("comments_hub.title") }}
      </h1>
      <span class="hidden h-5 w-px shrink-0 bg-border sm:block" aria-hidden="true" />
      <div class="relative min-w-0 max-w-56 sm:max-w-64">
        <Folder
          class="pointer-events-none absolute left-2.5 top-2 size-3.5 text-muted-foreground"
        />
        <select
          id="comments-hub-scope"
          :value="scopeValue"
          :aria-label="$t('comments_hub.scope')"
          class="h-8 w-full appearance-none truncate rounded-md border border-input bg-background py-1 pl-8 pr-8 text-xs font-medium outline-none transition-colors hover:bg-accent focus-visible:ring-2 focus-visible:ring-ring dark:bg-input/30"
          @change="changeScope"
        >
          <option value="all">{{ $t("comments_hub.all_projects") }}</option>
          <optgroup v-for="workspace in workspaces" :key="workspace.id" :label="workspace.name">
            <option :value="`workspace:${workspace.id}`">
              {{ $t("comments_hub.workspace_scope", { name: workspace.name }) }}
            </option>
            <option
              v-for="project in projects.filter((item) => item.workspace_id === workspace.id)"
              :key="project.id"
              :value="`project:${project.id}`"
            >
              {{ project.name }}
            </option>
          </optgroup>
        </select>
        <ChevronsUpDown
          class="pointer-events-none absolute right-2.5 top-2 size-3.5 text-muted-foreground"
        />
      </div>
      <div class="ml-auto flex shrink-0 items-center gap-1">
        <Button
          id="comments-hub-refresh"
          variant="ghost"
          size="icon-sm"
          class="hidden text-muted-foreground sm:inline-flex"
          :disabled="refreshPending"
          :aria-label="$t('comments_hub.refresh')"
          @click="emit('refresh')"
        >
          <RefreshCw class="size-4" :class="{ 'animate-spin': refreshPending }" />
        </Button>
        <Button
          id="comments-hub-close"
          variant="ghost"
          size="icon-sm"
          class="text-muted-foreground"
          :aria-label="$t('comments_hub.close')"
          @click="emit('close')"
          ><X class="size-4"
        /></Button>
      </div>
    </div>

    <form
      class="flex flex-wrap items-center gap-2 px-3 py-2.5 sm:px-5"
      role="search"
      @submit.prevent="patch({})"
    >
      <div class="relative min-w-0 flex-1 basis-60">
        <Search
          class="pointer-events-none absolute left-3 top-2.5 size-3.5 text-muted-foreground"
        />
        <input
          id="comments-hub-search"
          :value="filters.search"
          type="search"
          maxlength="200"
          autocomplete="off"
          :aria-label="$t('comments_hub.search')"
          :placeholder="$t('comments_hub.search')"
          class="h-9 w-full rounded-md border border-input bg-background pl-9 pr-24 text-sm outline-none transition-shadow placeholder:text-muted-foreground focus-visible:ring-2 focus-visible:ring-ring dark:bg-input/30"
          @input="emit('search', ($event.target as HTMLInputElement).value)"
        />
        <span
          class="pointer-events-none absolute right-2 top-2 max-w-20 truncate rounded bg-muted px-1.5 py-0.5 text-[11px] text-muted-foreground"
          >{{ scopeName }}</span
        >
      </div>
      <div
        class="flex max-w-full items-center gap-1 overflow-x-auto rounded-full border border-border p-0.5"
      >
        <HubChip
          id="comments-hub-tool-all"
          :active="!filters.tool"
          :count="counts?.all ?? null"
          @click="patch({ tool: '' })"
          >{{ $t("comments_hub.all") }}</HubChip
        >
        <HubChip
          v-for="tool in tools"
          :id="`comments-hub-tool-${tool}`"
          :key="tool"
          :active="filters.tool === tool"
          :count="counts?.tools?.[tool] ?? null"
          :icon="commentTool(tool === 'brainstorming' ? 'ideation_session' : `${tool}_canvas`).icon"
          :icon-class="
            commentTool(tool === 'brainstorming' ? 'ideation_session' : `${tool}_canvas`).colorClass
          "
          @click="patch({ tool: filters.tool === tool ? '' : tool })"
          >{{ $t(`comments_hub.tools.${tool}`) }}</HubChip
        >
      </div>
      <div class="flex items-center gap-1 rounded-full border border-border p-0.5">
        <HubChip
          id="comments-hub-status-open"
          :active="filters.status === 'open'"
          :count="counts?.open ?? null"
          :icon="CircleDot"
          @click="toggleStatus('open')"
          >{{ $t("comments_hub.open") }}</HubChip
        >
        <HubChip
          id="comments-hub-status-resolved"
          :active="filters.status === 'resolved'"
          :count="counts?.resolved ?? null"
          :icon="CheckCheck"
          @click="toggleStatus('resolved')"
          >{{ $t("comments_hub.resolved") }}</HubChip
        >
      </div>
      <HubChip
        id="comments-hub-unread"
        class="border border-border"
        :active="filters.unread === '1'"
        :count="counts?.unread ?? null"
        dot
        @click="patch({ unread: filters.unread === '1' ? '' : '1' })"
        >{{ $t("comments_hub.unread") }}</HubChip
      >
      <HubChip
        id="comments-hub-mentioned"
        class="border border-border"
        :active="filters.personal === 'mentioned'"
        :count="counts?.mentioned ?? null"
        :icon="AtSign"
        @click="togglePersonal('mentioned')"
        >{{ $t("comments_hub.mentions_me") }}</HubChip
      >
      <Button
        id="comments-hub-filters"
        type="button"
        variant="ghost"
        size="sm"
        class="gap-1.5 text-muted-foreground"
        :aria-expanded="moreOpen"
        @click="moreOpen = !moreOpen"
      >
        <SlidersHorizontal class="size-3.5" />{{
          $t(moreOpen ? "comments_hub.less" : "comments_hub.more")
        }}<ChevronDown v-if="moreOpen" class="size-3" /><ChevronRight v-else class="size-3" />
      </Button>
    </form>

    <div
      v-if="moreOpen || hasFilters"
      id="comments-hub-more"
      class="flex flex-wrap items-center gap-2 border-t border-border bg-muted/30 px-3 py-2 sm:px-5"
    >
      <span class="text-[11px] uppercase tracking-wider text-muted-foreground">{{
        $t("comments_hub.participation")
      }}</span>
      <div class="flex items-center gap-1 rounded-full border border-border p-0.5">
        <HubChip
          id="comments-hub-personal-all"
          :active="filters.personal === 'all'"
          @click="patch({ personal: 'all' })"
          >{{ $t("comments_hub.everyone") }}</HubChip
        >
        <HubChip
          id="comments-hub-personal-participated"
          :active="filters.personal === 'participated'"
          :count="counts?.participated ?? null"
          @click="togglePersonal('participated')"
          >{{ $t("comments_hub.participated") }}</HubChip
        >
        <HubChip
          id="comments-hub-personal-mentioned"
          :active="filters.personal === 'mentioned'"
          :count="counts?.mentioned ?? null"
          @click="togglePersonal('mentioned')"
          >{{ $t("comments_hub.mentioned") }}</HubChip
        >
      </div>
      <HubChip
        id="comments-hub-following"
        class="border border-border"
        :active="filters.following === '1'"
        :count="counts?.following ?? null"
        :icon="Bell"
        @click="patch({ following: filters.following === '1' ? '' : '1' })"
        >{{ $t("comments_hub.following") }}</HubChip
      >
      <template v-if="activeChips.length">
        <span class="mx-1 hidden h-5 w-px bg-border sm:block" aria-hidden="true" />
        <span class="text-[11px] uppercase tracking-wider text-muted-foreground">{{
          $t("comments_hub.active_filters")
        }}</span>
        <button
          v-for="chip in activeChips"
          :key="chip.key"
          type="button"
          class="inline-flex h-7 items-center gap-1.5 rounded-full bg-primary/12 pl-2.5 pr-1.5 text-xs text-primary"
          @click="chip.clear()"
        >
          {{ chip.label }}<X class="size-3" />
        </button>
      </template>
      <Button
        v-if="hasFilters"
        id="comments-hub-reset"
        type="button"
        variant="link"
        size="xs"
        @click="reset"
        >{{ $t("comments_hub.clear_all") }}</Button
      >
    </div>
  </header>
</template>
