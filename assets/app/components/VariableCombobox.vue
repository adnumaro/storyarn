<script setup lang="ts">
/**
 * Inline sentence-slot combobox.
 *
 * Renders as an inline text with dashed underline (sentence-slot style).
 * On click, opens a searchable dropdown via Popover+Command.
 * Matches the existing CSS: .sentence-slot, .sentence-slot.filled, .sentence-slot:focus
 */

import { computed, nextTick, ref } from "vue";
import {
  Command,
  CommandEmpty,
  CommandGroup,
  CommandInput,
  CommandItem,
  CommandList,
} from "./ui/command";
import { Popover, PopoverContent, PopoverTrigger } from "./ui/popover";

interface SelectOption {
  value: string;
  label: string;
}

interface OptionGroup {
  heading: string;
  items: SelectOption[];
}

const {
  modelValue = "",
  options = [],
  groups = [],
  placeholder = "...",
  disabled = false,
  freeText = false,
  inputType = "text",
} = defineProps<{
  /** Currently selected value */
  modelValue?: string;
  /** Flat options: [{ value, label }] */
  options?: SelectOption[];
  /** Grouped options: [{ heading, items: [{ value, label }] }] */
  groups?: OptionGroup[];
  /** Placeholder text */
  placeholder?: string;
  disabled?: boolean;
  /** Allow free-text input (no dropdown, just a text input) */
  freeText?: boolean;
  /** Input type for free-text mode */
  inputType?: string;
}>();

const emit = defineEmits<{
  "update:modelValue": [value: string];
}>();

const open = ref(false);

/** Display label for the current selection */
const displayLabel = computed(() => {
  if (!modelValue) return "";

  for (const opt of options) {
    if (opt.value === modelValue) return opt.label;
  }
  for (const group of groups) {
    for (const item of group.items) {
      if (item.value === modelValue) return item.label;
    }
  }
  return modelValue;
});

const hasGroups = computed(() => groups.length > 0);

function onSelect(value: string) {
  emit("update:modelValue", value);
  open.value = false;
}

function onFreeTextInput(e: Event) {
  emit("update:modelValue", (e.target as HTMLInputElement).value);
}

function onFreeTextBlur(e: Event) {
  emit("update:modelValue", (e.target as HTMLInputElement).value);
}

/** Auto-size an input based on content */
function autoSize(el: HTMLInputElement | null) {
  if (!el) return;
  const text = el.value || el.placeholder || "";
  const charCount = Math.max(text.length, 3);
  el.style.width = `${charCount + 2}ch`;
}
</script>

<template>
  <!-- Free-text mode: just an input -->
  <input
    v-if="freeText"
    :type="inputType"
    :value="modelValue || ''"
    :placeholder="placeholder"
    :disabled="disabled"
    :class="['sentence-slot', { filled: !!modelValue }]"
    :style="{ width: `${Math.max((modelValue || placeholder || '').length, 3) + 2}ch` }"
    autocomplete="off"
    spellcheck="false"
    @input="onFreeTextInput"
    @blur="onFreeTextBlur"
  />

  <!-- Combobox mode: sentence-slot trigger + dropdown -->
  <Popover v-else v-model:open="open">
    <PopoverTrigger as-child>
      <button
        type="button"
        :disabled="disabled"
        :class="['sentence-slot', { filled: !!modelValue }]"
        :style="{ minWidth: `${Math.max((displayLabel || placeholder).length, 3) + 1}ch` }"
      >
        <span v-if="displayLabel">{{ displayLabel }}</span>
        <span v-else class="sentence-slot-placeholder">{{ placeholder }}</span>
      </button>
    </PopoverTrigger>
    <PopoverContent class="w-[200px] p-0" align="start" :side-offset="4">
      <Command>
        <CommandInput :placeholder="$t('common.search')" class="h-8 text-xs" />
        <CommandList>
          <CommandEmpty class="py-3 text-xs">{{ $t("common.variable_combobox.no_results") }}</CommandEmpty>

          <template v-if="hasGroups">
            <CommandGroup v-for="group in groups" :key="group.heading" :heading="group.heading">
              <CommandItem
                v-for="item in group.items"
                :key="item.value"
                :value="item.label"
                @select="onSelect(item.value)"
              >
                {{ item.label }}
              </CommandItem>
            </CommandGroup>
          </template>

          <template v-else>
            <CommandGroup>
              <CommandItem
                v-for="item in options"
                :key="item.value"
                :value="item.label"
                @select="onSelect(item.value)"
              >
                {{ item.label }}
              </CommandItem>
            </CommandGroup>
          </template>
        </CommandList>
      </Command>
    </PopoverContent>
  </Popover>
</template>

<style scoped>
/* Placeholder style inside the sentence-slot button */
.sentence-slot-placeholder {
  color: color-mix(in oklch, var(--color-foreground, currentColor) 25%, transparent);
  font-weight: 400;
  font-style: italic;
}
</style>
