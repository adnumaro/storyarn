<script setup lang="ts">
import { Check, ChevronsUpDown } from "lucide-vue-next";
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

export interface PreferenceComboboxOption {
  value: string;
  label: string;
  badge?: string;
  searchText?: string;
}

const {
  id,
  modelValue = "",
  options,
  label,
  placeholder,
  searchPlaceholder,
  emptyLabel,
  disabled = false,
  ariaDescribedby,
} = defineProps<{
  id: string;
  modelValue?: string;
  options: PreferenceComboboxOption[];
  label: string;
  placeholder: string;
  searchPlaceholder: string;
  emptyLabel: string;
  disabled?: boolean;
  ariaDescribedby?: string;
}>();

const emit = defineEmits<{
  "update:modelValue": [value: string];
}>();

const open = ref(false);
const selected = computed(() => options.find((option) => option.value === modelValue) ?? null);

function selectOption(option: PreferenceComboboxOption): void {
  open.value = false;
  if (option.value !== modelValue) emit("update:modelValue", option.value);
}

watch(
  () => disabled,
  (isDisabled) => {
    if (isDisabled) open.value = false;
  },
);
</script>

<template>
  <Popover v-model:open="open">
    <PopoverTrigger as-child>
      <Button
        :id="id"
        type="button"
        variant="outline"
        :disabled="disabled"
        :aria-label="selected ? `${label}: ${selected.label}` : label"
        :aria-expanded="open"
        :aria-describedby="ariaDescribedby"
        class="group w-full min-w-0 justify-between gap-2 px-3 font-normal"
      >
        <span
          :class="[
            'flex min-w-0 items-center gap-2 truncate',
            !selected && 'text-muted-foreground',
          ]"
        >
          <span class="truncate">{{ selected?.label ?? placeholder }}</span>
          <span
            v-if="selected?.badge"
            class="shrink-0 rounded-full bg-sky-500/10 px-1.5 py-0.5 text-[9px] font-medium text-sky-700 dark:text-sky-300"
          >
            {{ selected.badge }}
          </span>
        </span>
        <ChevronsUpDown
          class="size-3.5 shrink-0 text-muted-foreground transition-transform duration-200 group-data-[state=open]:rotate-180"
          aria-hidden="true"
        />
      </Button>
    </PopoverTrigger>

    <PopoverContent
      align="start"
      :side-offset="4"
      class="w-(--reka-popover-trigger-width) min-w-56 overflow-hidden p-0"
    >
      <Command>
        <CommandInput :placeholder="searchPlaceholder" />
        <CommandList>
          <CommandEmpty>{{ emptyLabel }}</CommandEmpty>
          <CommandGroup>
            <CommandItem
              v-for="option in options"
              :key="option.value"
              :value="`${option.label} ${option.searchText ?? ''} ${option.value}`"
              class="min-h-9 gap-2 px-3"
              @select="selectOption(option)"
            >
              <span class="min-w-0 flex-1 truncate">{{ option.label }}</span>
              <span class="sr-only">{{ option.searchText }} {{ option.value }}</span>
              <span
                v-if="option.badge"
                class="shrink-0 rounded-full bg-sky-500/10 px-1.5 py-0.5 text-[9px] font-medium text-sky-700 dark:text-sky-300"
              >
                {{ option.badge }}
              </span>
              <Check
                :class="[
                  'size-4 shrink-0 text-primary',
                  option.value === modelValue ? 'opacity-100' : 'opacity-0',
                ]"
                aria-hidden="true"
              />
            </CommandItem>
          </CommandGroup>
        </CommandList>
      </Command>
    </PopoverContent>
  </Popover>
</template>
