<script setup lang="ts">
import { ChevronDown } from "@lucide/vue";
import { computed } from "vue";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuRadioGroup,
  DropdownMenuRadioItem,
  DropdownMenuTrigger,
} from "@components/ui/dropdown-menu";
import { TONES, type Tone } from "../../domain/status";

export interface FilterOption {
  value: string;
  label: string;
  tone?: Tone;
}

/**
 * One filter of the list as a chip: shows its name when unset and the chosen
 * option when set; opens a single-choice menu.
 */
const { label, modelValue, options, allLabel } = defineProps<{
  label: string;
  modelValue: string;
  options: FilterOption[];
  allLabel: string;
}>();

const emit = defineEmits<{ "update:modelValue": [value: string] }>();

const ALL = "__all__";

const selected = computed(() => options.find((option) => option.value === modelValue) ?? null);
const active = computed(() => selected.value !== null);

function select(value: string): void {
  emit("update:modelValue", value === ALL ? "" : value);
}
</script>

<template>
  <DropdownMenu>
    <DropdownMenuTrigger as-child>
      <button
        type="button"
        :class="[
          'inline-flex items-center gap-1 rounded-full border py-[3px] pr-2 pl-2.5 text-xs transition-colors outline-none focus-visible:ring-2 focus-visible:ring-ring/50',
          active
            ? 'border-primary/60 bg-primary/10 text-foreground'
            : 'border-border text-muted-foreground hover:bg-accent hover:text-foreground',
        ]"
      >
        <span
          v-if="selected?.tone"
          :class="['size-[7px] rounded-full', TONES[selected.tone].dot]"
          aria-hidden="true"
        />
        <span v-if="selected" class="sr-only">{{ label }}:</span>
        {{ selected ? selected.label : label }}
        <ChevronDown class="size-3" />
      </button>
    </DropdownMenuTrigger>
    <DropdownMenuContent align="start" class="min-w-44">
      <DropdownMenuRadioGroup :model-value="modelValue || ALL" @update:model-value="select">
        <DropdownMenuRadioItem :value="ALL">{{ allLabel }}</DropdownMenuRadioItem>
        <DropdownMenuRadioItem v-for="option in options" :key="option.value" :value="option.value">
          <span class="inline-flex items-center gap-2">
            <span
              v-if="option.tone"
              :class="['size-[7px] rounded-full', TONES[option.tone].dot]"
              aria-hidden="true"
            />
            {{ option.label }}
          </span>
        </DropdownMenuRadioItem>
      </DropdownMenuRadioGroup>
    </DropdownMenuContent>
  </DropdownMenu>
</template>
