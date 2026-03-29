<script setup>
import {
	Cable,
	MapPin,
	Pentagon,
	Search,
	StickyNote,
	X,
} from "lucide-vue-next";
import { ref, watch } from "vue";
import { useLive } from "@/vue/composables/useLive";

const props = defineProps({
	searchQuery: { type: String, default: "" },
	searchFilter: { type: String, default: "all" },
	searchResults: { type: Array, default: () => [] },
});

const live = useLive();
const localQuery = ref(props.searchQuery);

watch(
	() => props.searchQuery,
	(v) => {
		localQuery.value = v;
	},
);

const filters = [
	{ label: "All", value: "all" },
	{ label: "Pins", value: "pin" },
	{ label: "Zones", value: "zone" },
	{ label: "Notes", value: "annotation" },
	{ label: "Lines", value: "connection" },
];

const resultIcons = {
	pin: MapPin,
	zone: Pentagon,
	connection: Cable,
	annotation: StickyNote,
};

let debounceTimer = null;

function onInput() {
	clearTimeout(debounceTimer);
	debounceTimer = setTimeout(() => {
		live.pushEvent("search_elements", { query: localQuery.value });
	}, 300);
}

function clearSearch() {
	localQuery.value = "";
	live.pushEvent("clear_search", {});
}

function setFilter(value) {
	live.pushEvent("set_search_filter", { filter: value });
}

function focusResult(result) {
	live.pushEvent("focus_search_result", {
		type: result.type,
		id: result.id,
	});
}

function getIcon(type) {
	return resultIcons[type] || Search;
}
</script>

<template>
  <div class="relative h-full">
    <!-- Input pill -->
    <div class="v2-surface-panel h-full">
      <div class="flex items-center gap-2 px-3 h-full">
        <Search class="size-4 text-muted-foreground/60 shrink-0" />
        <input
          v-model="localQuery"
          type="text"
          placeholder="Search elements..."
          autocomplete="off"
          class="flex-1 bg-transparent text-sm border-none outline-none placeholder:text-muted-foreground/40 p-0 w-40 h-8"
          @input="onInput"
          @keydown.escape="clearSearch"
        />
        <button
          v-if="localQuery"
          type="button"
          class="shrink-0 size-5 inline-flex items-center justify-center rounded hover:bg-accent text-muted-foreground hover:text-foreground"
          @click="clearSearch"
        >
          <X class="size-3" />
        </button>
      </div>
    </div>

    <!-- Dropdown: filter tabs + results -->
    <div
      v-if="localQuery"
      class="absolute top-full left-0 mt-1 w-full min-w-56 bg-surface rounded-xl border border-border shadow-md z-10"
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
      <div
        v-if="searchResults.length > 0"
        class="max-h-48 overflow-y-auto border-t border-border"
      >
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
      <div
        v-else
        class="px-3 py-2 text-xs text-muted-foreground/60 border-t border-border"
      >
        No results found
      </div>
    </div>
  </div>
</template>
