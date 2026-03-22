<script setup>
/**
 * Inline sentence-slot combobox.
 *
 * Renders as an inline text with dashed underline (sentence-slot style).
 * On click, opens a searchable dropdown via Popover+Command.
 * Matches the existing CSS: .sentence-slot, .sentence-slot.filled, .sentence-slot:focus
 */

import { computed, ref, nextTick } from "vue";
import { Popover, PopoverContent, PopoverTrigger } from "./ui/popover";
import {
	Command,
	CommandEmpty,
	CommandGroup,
	CommandInput,
	CommandItem,
	CommandList,
} from "./ui/command";

const props = defineProps({
	/** Currently selected value */
	modelValue: { type: String, default: "" },
	/** Flat options: [{ value, label }] */
	options: { type: Array, default: () => [] },
	/** Grouped options: [{ heading, items: [{ value, label }] }] */
	groups: { type: Array, default: () => [] },
	/** Placeholder text */
	placeholder: { type: String, default: "..." },
	disabled: { type: Boolean, default: false },
	/** Allow free-text input (no dropdown, just a text input) */
	freeText: { type: Boolean, default: false },
	/** Input type for free-text mode */
	inputType: { type: String, default: "text" },
});

const emit = defineEmits(["update:modelValue"]);

const open = ref(false);

/** Display label for the current selection */
const displayLabel = computed(() => {
	if (!props.modelValue) return "";

	for (const opt of props.options) {
		if (opt.value === props.modelValue) return opt.label;
	}
	for (const group of props.groups) {
		for (const item of group.items) {
			if (item.value === props.modelValue) return item.label;
		}
	}
	return props.modelValue;
});

const hasGroups = computed(() => props.groups.length > 0);

function onSelect(value) {
	emit("update:modelValue", value);
	open.value = false;
}

function onFreeTextInput(e) {
	emit("update:modelValue", e.target.value);
}

function onFreeTextBlur(e) {
	emit("update:modelValue", e.target.value);
}

/** Auto-size an input based on content */
function autoSize(el) {
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
        <CommandInput :placeholder="`Search...`" class="h-8 text-xs" />
        <CommandList>
          <CommandEmpty class="py-3 text-xs">No results.</CommandEmpty>

          <template v-if="hasGroups">
            <CommandGroup
              v-for="group in groups"
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
  color: color-mix(in oklch, var(--color-base-content, currentColor) 25%, transparent);
  font-weight: 400;
  font-style: italic;
}
</style>
