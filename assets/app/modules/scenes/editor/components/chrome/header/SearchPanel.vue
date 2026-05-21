<script setup lang="ts">
import type { Component } from "vue";
import { Cable, MapPin, Pentagon, Search, StickyNote, X } from "lucide-vue-next";
import { computed, ref, watch } from "vue";
import { useI18n } from "vue-i18n";
import { Popover, PopoverAnchor, PopoverContent } from "@components/ui/popover";
import { useLive } from "@shared/composables/useLive.ts";

const { t } = useI18n();

interface SearchResult {
  id: number | string;
  type: string;
  label: string;
}

interface FilterOption {
  label: string;
  value: string;
}

const {
  searchQuery = "",
  searchFilter = "all",
  searchResults = [],
} = defineProps<{
  searchQuery: string;
  searchFilter: string;
  searchResults: SearchResult[];
}>();

const live = useLive();
const localQuery = ref(searchQuery);
const searchOpen = computed(() => localQuery.value.length > 0);

watch(
  () => searchQuery,
  (v) => {
    localQuery.value = v;
  },
);

const filters = computed<FilterOption[]>(() => [
  { label: t("scenes.search.all"), value: "all" },
  { label: t("scenes.search.pins"), value: "pin" },
  { label: t("scenes.search.zones"), value: "zone" },
  { label: t("scenes.search.notes"), value: "annotation" },
  { label: t("scenes.search.lines"), value: "connection" },
]);

const resultIcons: Record<string, Component> = {
  pin: MapPin,
  zone: Pentagon,
  connection: Cable,
  annotation: StickyNote,
};

let debounceTimer: ReturnType<typeof setTimeout> | undefined;

function onInput(): void {
  clearTimeout(debounceTimer);
  debounceTimer = setTimeout(() => {
    live.pushEvent("search_elements", { query: localQuery.value });
  }, 300);
}

function clearSearch(): void {
  localQuery.value = "";
  live.pushEvent("clear_search", {});
}

function setFilter(value: string): void {
  live.pushEvent("set_search_filter", { filter: value });
}

function focusResult(result: SearchResult): void {
  live.pushEvent("focus_search_result", {
    type: result.type,
    id: result.id,
  });
}

function getIcon(type: string): Component {
  return resultIcons[type] || Search;
}
</script>

<template>
  <Popover :open="searchOpen">
    <PopoverAnchor as-child>
      <div class="h-full">
        <div class="flex items-center gap-2 px-3 h-full">
          <Search class="size-4 text-muted-foreground/60 shrink-0" />
          <input
            v-model="localQuery"
            type="text"
            :placeholder="$t('scenes.search.placeholder')"
            autocomplete="off"
            class="flex-1 bg-transparent text-sm border-none outline-none placeholder:text-muted-foreground/40 p-0 w-40 h-8"
            @input="onInput"
            @keydown.escape="clearSearch"
          />
          <button
            v-if="localQuery"
            type="button"
            class="shrink-0 size-5 inline-flex items-center justify-center rounded hover:bg-accent text-muted-foreground hover:text-foreground"
            :aria-label="$t('scenes.search.clear')"
            :title="$t('scenes.search.clear')"
            @click="clearSearch"
          >
            <X class="size-3" />
          </button>
        </div>
      </div>
    </PopoverAnchor>

    <PopoverContent
      v-if="localQuery"
      align="start"
      :side-offset="4"
      :collision-padding="8"
      class="w-72 min-w-56 rounded-xl bg-surface p-0 shadow-md"
      @open-auto-focus.prevent
    >
      <!-- Type filter tabs -->
      <div class="flex gap-1 px-2 py-1.5 flex-wrap">
        <button
          v-for="f in filters"
          :key="f.value"
          type="button"
          :class="[
            'inline-flex items-center h-6 px-2 text-xs rounded-md transition-colors',
            searchFilter === f.value
              ? 'bg-primary text-primary-foreground'
              : 'bg-transparent text-muted-foreground hover:bg-accent hover:text-foreground',
          ]"
          @click="setFilter(f.value)"
        >
          {{ f.label }}
        </button>
      </div>

      <!-- Search results -->
      <div v-if="searchResults.length > 0" class="max-h-48 overflow-y-auto border-t border-border">
        <button
          v-for="result in searchResults"
          :key="result.type + '-' + result.id"
          type="button"
          class="w-full flex items-center gap-2 px-3 py-1.5 hover:bg-accent text-left transition-colors"
          @click="focusResult(result)"
        >
          <component :is="getIcon(result.type)" class="size-3.5 text-muted-foreground/60" />
          <span class="text-xs truncate">{{ result.label }}</span>
        </button>
      </div>

      <!-- No results -->
      <div v-else class="px-3 py-2 text-xs text-muted-foreground/60 border-t border-border">
        {{ $t("scenes.search.no_results") }}
      </div>
    </PopoverContent>
  </Popover>
</template>
