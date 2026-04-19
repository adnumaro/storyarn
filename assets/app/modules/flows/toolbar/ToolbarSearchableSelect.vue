<script setup lang="ts">
import { Check, ChevronDown } from "lucide-vue-next";
import { computed, ref } from "vue";
import {
  Command,
  CommandEmpty,
  CommandGroup,
  CommandInput,
  CommandItem,
  CommandList,
} from "@components/ui/command/index.ts";
import { Popover, PopoverContent, PopoverTrigger } from "@components/ui/popover/index.ts";

const {
  options = [],
  selectedValue = null,
  selectedLabel = null,
  placeholder = "Select...",
  disabled = false,
} = defineProps<{
  options?: [string, string | number][];
  selectedValue?: string | number | null;
  selectedLabel?: string | null;
  placeholder?: string;
  disabled?: boolean;
}>();

const emit = defineEmits<{
  select: [value: string | number];
}>();
const open = ref(false);

const displayLabel = computed(() => selectedLabel || null);

const hasSelection = computed(
  () => selectedValue !== null && selectedValue !== undefined && selectedValue !== "",
);

function isSelected(value: string | number): boolean {
  return hasSelection.value && String(value) === String(selectedValue);
}

function select(value: string | number) {
  emit("select", value);
  open.value = false;
}
</script>

<template>
  <Popover v-model:open="open">
    <PopoverTrigger as-child>
      <button type="button" class="toolbar-btn gap-1 text-xs max-w-35" :disabled="disabled">
        <span class="truncate" :class="displayLabel ? '' : 'opacity-50'">
          {{ displayLabel || placeholder }}
        </span>
        <ChevronDown class="size-3 opacity-50 shrink-0" />
      </button>
    </PopoverTrigger>
    <PopoverContent class="w-56 p-0" :side-offset="8" side="top">
      <Command>
        <CommandInput :placeholder="placeholder" />
        <CommandList>
          <CommandEmpty>{{ $t("flows.searchable_select.no_results") }}</CommandEmpty>
          <CommandGroup>
            <CommandItem value="__clear__" @select="select('')">
              <span class="text-muted-foreground">{{ $t("flows.searchable_select.none") }}</span>
              <Check v-if="!hasSelection" class="size-3 ml-auto" />
            </CommandItem>
            <CommandItem
              v-for="[label, value] in options"
              :key="value"
              :value="label"
              @select="select(value)"
            >
              <span class="truncate">{{ label }}</span>
              <Check v-if="isSelected(value)" class="size-3 ml-auto" />
            </CommandItem>
          </CommandGroup>
        </CommandList>
      </Command>
    </PopoverContent>
  </Popover>
</template>
