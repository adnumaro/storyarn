<script setup lang="ts">
/**
 * Inline sentence-slot combobox.
 *
 * Renders as an inline text with dashed underline (sentence-slot style).
 * On click, opens a searchable dropdown via Popover+Command.
 * Matches the existing CSS: .sentence-slot, .sentence-slot.filled, .sentence-slot:focus
 */

import { computed, nextTick, ref, useTemplateRef } from "vue";
import {
  Command,
  CommandEmpty,
  CommandGroup,
  CommandInput,
  CommandItem,
  CommandList,
} from "../ui/command";
import { Popover, PopoverContent, PopoverTrigger } from "../ui/popover";

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
  emptyText = "",
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
  /** Caller-supplied message shown when both `options` and `groups` are
   * empty before any search. Use this to give a context-specific reason
   * (e.g. "Sheets have no variables yet"). When unset we fall back to
   * the generic `common.variable_combobox.no_options` key. */
  emptyText?: string;
}>();

const emit = defineEmits<{
  "update:modelValue": [value: string];
}>();

const open = ref(false);
const triggerRef = useTemplateRef<HTMLButtonElement>("triggerEl");
const freeTextRef = useTemplateRef<HTMLInputElement>("freeTextEl");

/** Imperative focus API used by parent rows to auto-advance through a chain
 * of comboboxes (V1 condition_rule_row / assignment_row pattern). For
 * combobox mode: focus the trigger button AND open the popover so the user
 * lands on the search input. For free-text mode: focus the input. */
function focus(): void {
  if (freeText) {
    freeTextRef.value?.focus();
    return;
  }
  open.value = true;
  // The trigger button stays in the tab order; focus it so keyboard users
  // can dismiss with Esc / re-trigger with Space cleanly.
  nextTick(() => triggerRef.value?.focus());
}

defineExpose({ focus });

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

/** True when there's nothing to show before any search filtering happens.
 * `CommandEmpty` only fires when filtering yields 0 — when the source list
 * is empty to start with, the popover renders blank. We surface a static
 * "no options" message instead. */
const hasNoSource = computed(() => !hasGroups.value && options.length === 0 && !freeText);

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
    ref="freeTextEl"
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
        ref="triggerEl"
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
      <!-- Static empty-state when there's nothing to filter against. -->
      <div v-if="hasNoSource" class="py-3 px-3 text-xs text-muted-foreground italic text-center">
        {{ emptyText || $t("common.variable_combobox.no_options") }}
      </div>

      <Command v-else>
        <CommandInput :placeholder="$t('common.search')" class="h-8 text-xs" />
        <CommandList>
          <CommandEmpty class="py-3 text-xs">{{
            $t("common.variable_combobox.no_results")
          }}</CommandEmpty>

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
