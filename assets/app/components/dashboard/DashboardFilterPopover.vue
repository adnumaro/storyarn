<script setup lang="ts">
import { Check, ChevronDown } from "@lucide/vue";
import { computed, ref, watch } from "vue";
import { Button } from "@components/ui/button";
import {
  Command,
  CommandEmpty,
  CommandGroup,
  CommandInput,
  CommandItem,
  CommandList,
} from "@components/ui/command";
import { Popover, PopoverContent, PopoverTrigger } from "@components/ui/popover";
import { useBoundedSearch } from "@shared/composables/useBoundedSearch";
import type { DashboardFilterPopoverOption } from "./types";

const MAX_RENDERED_OPTIONS = 100;

const {
  id,
  modelValue,
  options,
  label,
  searchPlaceholder,
  emptyLabel,
  searchable = false,
  triggerClass = "",
} = defineProps<{
  id: string;
  modelValue: string;
  options: DashboardFilterPopoverOption[];
  label: string;
  searchPlaceholder: string;
  emptyLabel: string;
  searchable?: boolean;
  triggerClass?: string;
}>();

const emit = defineEmits<{
  "update:modelValue": [value: string];
}>();

const open = ref(false);
const selected = computed(
  () => options.find((option) => option.value === modelValue) ?? options[0] ?? null,
);
const selectedKey = computed(() => modelValue);
const optionSearch = useBoundedSearch({
  get items() {
    return options;
  },
  limit: MAX_RENDERED_OPTIONS,
  getText: (option) => `${option.label} ${option.searchText ?? ""} ${option.value}`,
  getKey: (option) => option.value,
  selectedKey,
});
const triggerAriaLabel = computed(() => {
  if (!selected.value) return label;
  return `${label}: ${selected.value.label} (${selected.value.count})`;
});

function optionDomId(value: string): string {
  return `${id}-option-${value.replace(/[^a-z0-9_-]/gi, "-")}`;
}

function selectOption(option: DashboardFilterPopoverOption): void {
  open.value = false;
  if (option.value !== modelValue) emit("update:modelValue", option.value);
}

watch(open, (isOpen) => {
  if (!isOpen) optionSearch.query.value = "";
});
</script>

<template>
  <Popover v-model:open="open">
    <PopoverTrigger as-child>
      <Button
        :id="id"
        type="button"
        variant="outline"
        size="sm"
        :aria-label="triggerAriaLabel"
        :aria-expanded="open"
        :data-testid="id"
        :class="['group min-w-0 max-w-full justify-between gap-2 px-3 font-normal', triggerClass]"
      >
        <span class="flex min-w-0 items-center gap-2">
          <span class="min-w-0 flex-1 truncate text-left">
            {{ selected?.label }}
          </span>
          <span
            v-if="selected"
            class="shrink-0 rounded-md bg-muted px-1.5 py-0.5 text-[10px] font-medium tabular-nums text-muted-foreground"
          >
            {{ selected.count }}
          </span>
        </span>
        <ChevronDown
          class="size-3.5 shrink-0 text-muted-foreground transition-transform duration-200 group-data-[state=open]:rotate-180"
          aria-hidden="true"
        />
      </Button>
    </PopoverTrigger>

    <PopoverContent
      align="start"
      :side-offset="4"
      class="w-(--reka-popover-trigger-width) min-w-56 max-w-[calc(100vw-2rem)] overflow-hidden p-0"
    >
      <Command :model-value="modelValue" :disable-filter="true" class="max-h-80">
        <CommandInput
          v-if="searchable"
          v-model="optionSearch.query.value"
          :placeholder="searchPlaceholder"
          :aria-label="searchPlaceholder"
        />
        <CommandList>
          <CommandEmpty v-if="!optionSearch.isSearching.value && optionSearch.query.value.trim()">
            {{ emptyLabel }}
          </CommandEmpty>
          <div
            v-if="optionSearch.isSearching.value && optionSearch.visibleItems.value.length === 0"
            class="py-6 text-center text-sm text-muted-foreground"
            role="status"
          >
            {{ $t("common.searching") }}
          </div>
          <CommandGroup>
            <CommandItem
              v-for="option in optionSearch.visibleItems.value"
              :id="optionDomId(option.value)"
              :key="option.value"
              :value="option.value"
              class="min-h-9 gap-2 px-3"
              @select="selectOption(option)"
            >
              <span class="min-w-0 flex-1 truncate">{{ option.label }}</span>
              <span
                class="shrink-0 text-xs tabular-nums text-muted-foreground"
                :aria-label="String(option.count)"
              >
                {{ option.count }}
              </span>
              <Check
                :class="[
                  'size-4 shrink-0 text-primary transition-opacity',
                  option.value === modelValue ? 'opacity-100' : 'opacity-0',
                ]"
                aria-hidden="true"
              />
            </CommandItem>
          </CommandGroup>
          <div
            v-if="optionSearch.isLimited.value"
            class="border-t border-border px-3 py-2 text-xs text-muted-foreground"
          >
            <template v-if="optionSearch.query.value.trim()">
              {{
                $t("common.limited_matches", {
                  shown: optionSearch.visibleItems.value.length,
                })
              }}
            </template>
            <template v-else>
              {{
                $t("common.limited_results", {
                  shown: optionSearch.visibleItems.value.length,
                  total: options.length,
                })
              }}
            </template>
          </div>
        </CommandList>
      </Command>
    </PopoverContent>
  </Popover>
</template>
