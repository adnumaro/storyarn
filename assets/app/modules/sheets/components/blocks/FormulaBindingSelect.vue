<script setup>
/**
 * Formula binding selector with server-side search + infinite scroll.
 *
 * Same-row columns are always shown (bounded by table columns).
 * Cross-sheet variables are searched server-side, loaded 20 at a time.
 *
 * Infinite scroll: scroll listener on CommandList $el, with pendingLoad
 * guard unlocked only after DOM settles (scroll position restored).
 */
import { computed, nextTick, onBeforeUnmount, onBeforeUpdate, ref, watch } from "vue";
import {
  Command,
  CommandEmpty,
  CommandGroup,
  CommandInput,
  CommandItem,
  CommandList,
} from "@components/ui/command/index.ts";
import { Popover, PopoverContent, PopoverTrigger } from "@components/ui/popover/index.ts";
import { useLive } from "@composables/useLive";
import { useServerSearch } from "@composables/useServerSearch";

const { modelValue, sameRowOptions, searchResults, hasMore } = defineProps({
  modelValue: { type: String, default: "" },
  sameRowOptions: { type: Array, default: () => [] },
  searchResults: { type: Array, default: () => [] },
  hasMore: { type: Boolean, default: false },
});

const emit = defineEmits(["update:modelValue"]);

const open = ref(false);
const live = useLive();
const pendingLoad = ref(false);
const listRef = ref(null);
let savedScrollTop = 0;

const { query, loading, search, reset } = useServerSearch({
  searchEvent: "search_formula_bindings",
  debounceMs: 250,
});

function getListEl() {
  return listRef.value?.$el ?? listRef.value;
}

function onScroll() {
  if (!hasMore || pendingLoad.value) return;
  const el = getListEl();
  if (!el) return;
  if (el.scrollHeight - el.scrollTop - el.clientHeight < 40) {
    pendingLoad.value = true;
    live.pushEvent("load_more_formula_bindings", {});
  }
}

// Save scroll position before Vue re-renders
onBeforeUpdate(() => {
  const el = getListEl();
  if (el) savedScrollTop = el.scrollTop;
});

// After new results arrive: restore scroll, then unlock
watch(
  () => searchResults,
  () => {
    nextTick(() => {
      const el = getListEl();
      if (el && savedScrollTop > 0) {
        el.scrollTop = savedScrollTop;
      }
      pendingLoad.value = false;
    });
  },
);

// Attach scroll listener when popover opens
watch(open, (v) => {
  if (v) {
    pendingLoad.value = false;
    savedScrollTop = 0;
    reset();
    search("");
    nextTick(() => {
      const el = getListEl();
      if (el) el.addEventListener("scroll", onScroll);
    });
  } else {
    const el = getListEl();
    if (el) el.removeEventListener("scroll", onScroll);
  }
});

onBeforeUnmount(() => {
  const el = getListEl();
  if (el) el.removeEventListener("scroll", onScroll);
});

// Display label for the currently selected binding
const displayLabel = computed(() => {
  if (!modelValue) return "";
  for (const opt of sameRowOptions) {
    if (opt.value === modelValue) return opt.label;
  }
  for (const group of searchResults) {
    for (const item of group.items) {
      if (item.value === modelValue) return item.label;
    }
  }
  if (modelValue.startsWith("same_row:")) return modelValue.slice(9);
  return modelValue;
});

function onSelect(value) {
  emit("update:modelValue", value);
  open.value = false;
}

function onSearchInput(q) {
  pendingLoad.value = false;
  savedScrollTop = 0;
  search(q);
}
</script>

<template>
  <Popover v-model:open="open">
    <PopoverTrigger as-child>
      <button
        type="button"
        :class="['sentence-slot', { filled: !!modelValue }]"
        :style="{ minWidth: `${Math.max((displayLabel || 'Select source...').length, 3) + 1}ch` }"
      >
        <span v-if="displayLabel">{{ displayLabel }}</span>
        <span v-else class="sentence-slot-placeholder">Select source...</span>
      </button>
    </PopoverTrigger>
    <PopoverContent class="w-[260px] p-0 z-50" align="start" :side-offset="4">
      <Command :should-filter="false">
        <CommandInput
          placeholder="Search variables..."
          class="h-8 text-xs"
          :model-value="query"
          @update:model-value="onSearchInput"
        />
        <CommandList ref="listRef">
          <CommandEmpty class="py-3 text-xs text-center">
            <span v-if="loading">Searching...</span>
            <span v-else>No results.</span>
          </CommandEmpty>

          <!-- Same row columns (always shown) -->
          <CommandGroup v-if="sameRowOptions.length > 0" heading="Same row">
            <CommandItem
              v-for="item in sameRowOptions"
              :key="item.value"
              :value="item.label"
              @select="onSelect(item.value)"
            >
              {{ item.label }}
            </CommandItem>
          </CommandGroup>

          <!-- Cross-sheet variables (paginated from server) -->
          <CommandGroup
            v-for="group in searchResults"
            :key="group.heading"
            :heading="group.heading"
          >
            <CommandItem
              v-for="item in group.items"
              :key="item.value"
              :value="item.label"
              @select="onSelect(item.value)"
            >
              {{ item.label }}
            </CommandItem>
          </CommandGroup>

          <!-- Loading indicator -->
          <div v-if="pendingLoad" class="py-2 text-center text-xs text-muted-foreground">
            Loading...
          </div>
        </CommandList>
      </Command>
    </PopoverContent>
  </Popover>
</template>

<style scoped>
.sentence-slot-placeholder {
  color: color-mix(in oklch, var(--color-base-content, currentColor) 25%, transparent);
  font-weight: 400;
  font-style: italic;
}
</style>
