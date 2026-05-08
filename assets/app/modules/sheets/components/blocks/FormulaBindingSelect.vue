<script setup lang="ts">
/**
 * Formula binding selector with server-side search + infinite scroll.
 *
 * Same-row columns are always shown (bounded by table columns).
 * Cross-sheet variables are searched server-side, loaded 20 at a time.
 *
 * Infinite scroll: scroll listener on CommandList $el, with pendingLoad
 * guard unlocked only after DOM settles (scroll position restored).
 */
import type { ComponentPublicInstance } from "vue";
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
import { useLive } from "../../../../shared/composables/useLive";
import { useServerSearch } from "../../../../shared/composables/useServerSearch";
import type { FormulaBindingOption, FormulaSearchGroup } from "../../types";
import { generateId } from "../../../../shared/domain/variables.ts";

const {
  modelValue = "",
  sameRowOptions = [],
  searchResults = [],
  hasMore = false,
} = defineProps<{
  modelValue?: string;
  sameRowOptions?: FormulaBindingOption[];
  searchResults?: FormulaSearchGroup[];
  hasMore?: boolean;
}>();

const emit = defineEmits<{
  "update:modelValue": [value: string];
}>();

const open = ref(false);
const live = useLive();
const pendingLoad = ref(false);
const listRef = ref<ComponentPublicInstance | null>(null);
let savedScrollTop = 0;

const { query, loading, search, reset } = useServerSearch({
  searchEvent: "search_formula_bindings",
  debounceMs: 250,
});

function getListEl(): HTMLElement | null {
  return (listRef.value?.$el ?? listRef.value) as HTMLElement | null;
}

function onScroll(): void {
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
  if (modelValue.startsWith("same_row:")) return modelValue.slice(9);
  return modelValue;
});

function onSelect(value: string): void {
  emit("update:modelValue", value);
  open.value = false;
}

function onSearchInput(q: string): void {
  pendingLoad.value = false;
  savedScrollTop = 0;
  search(q);
}
</script>

<template>
  <Popover v-model:open="open">
    <PopoverTrigger as-child>
      <button
        :id="`formula-binding-trigger-${generateId()}`"
        type="button"
        :title="displayLabel || ''"
        class="flex-1 min-w-0 h-9 px-3 py-1 rounded-md border border-input bg-card text-sm text-left truncate font-mono focus:outline-none focus:ring-2 focus:ring-ring"
      >
        <span v-if="displayLabel">{{ displayLabel }}</span>
        <span v-else class="text-muted-foreground/60 italic">{{
          $t("sheets.formula_binding.select_source")
        }}</span>
      </button>
    </PopoverTrigger>
    <PopoverContent class="w-65 p-0 z-50" align="start" :side-offset="4">
      <Command :should-filter="false">
        <CommandInput
          :placeholder="$t('sheets.formula_binding.search')"
          class="h-8 text-xs"
          :model-value="query"
          @update:model-value="onSearchInput"
        />
        <CommandList ref="listRef">
          <CommandEmpty class="py-3 text-xs text-center">
            <span v-if="loading">{{ $t("sheets.formula_binding.searching") }}</span>
            <span v-else>{{ $t("sheets.formula_binding.no_results") }}</span>
          </CommandEmpty>

          <!-- Same row columns (always shown) -->
          <CommandGroup
            v-if="sameRowOptions.length > 0"
            :heading="$t('sheets.formula_binding.same_row')"
          >
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
            {{ $t("sheets.formula_binding.loading") }}
          </div>
        </CommandList>
      </Command>
    </PopoverContent>
  </Popover>
</template>

<style scoped>
.sentence-slot-placeholder {
  color: color-mix(in oklch, var(--color-foreground, currentColor) 25%, transparent);
  font-weight: 400;
  font-style: italic;
}
</style>
