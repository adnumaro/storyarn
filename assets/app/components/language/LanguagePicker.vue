<script setup lang="ts">
import { Check, ChevronDown } from "lucide-vue-next";
import { computed, ref } from "vue";
import LiveLink from "@components/navigation/LiveLink.vue";
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
import LanguageFlag from "./LanguageFlag.vue";
import type { LanguagePickerOption } from "./types";

interface PickerText {
  placeholder?: string;
  searchPlaceholder?: string;
  emptyLabel?: string;
}

interface PickerAppearance {
  compact?: boolean;
  searchable?: boolean;
  align?: "start" | "center" | "end";
  triggerVariant?: "default" | "destructive" | "outline" | "secondary" | "ghost" | "link";
  triggerSize?: "default" | "xs" | "sm" | "lg";
  triggerClass?: string;
  contentClass?: string;
}

const {
  id,
  modelValue = null,
  options,
  label,
  selectedOption = null,
  mode = "select",
  disabled = false,
  text = {},
  appearance = {},
} = defineProps<{
  id: string;
  modelValue?: string | null;
  options: LanguagePickerOption[];
  label: string;
  selectedOption?: LanguagePickerOption | null;
  mode?: "select" | "navigate";
  disabled?: boolean;
  text?: PickerText;
  appearance?: PickerAppearance;
}>();

const emit = defineEmits<{
  "update:modelValue": [value: string];
  select: [option: LanguagePickerOption];
}>();

const open = ref(false);
const compact = computed(() => appearance.compact ?? false);
const searchable = computed(() => appearance.searchable ?? true);
const align = computed(() => appearance.align ?? "start");
const triggerVariant = computed(() => appearance.triggerVariant ?? "outline");
const triggerSize = computed(() => appearance.triggerSize ?? "default");
const triggerClass = computed(() => appearance.triggerClass ?? "");
const contentClass = computed(() => appearance.contentClass ?? "");
const placeholder = computed(() => text.placeholder ?? "");
const searchPlaceholder = computed(() => text.searchPlaceholder ?? "Search languages...");
const emptyLabel = computed(() => text.emptyLabel ?? "No languages found.");

const selected = computed(() => {
  return selectedOption ?? options.find((option) => option.value === modelValue) ?? null;
});
const triggerAriaLabel = computed(() => {
  return selected.value ? `${label}: ${selected.value.label}` : label;
});

function optionDomId(option: LanguagePickerOption): string {
  return `${id}-${option.value.replace(/[^a-z0-9_-]/gi, "-")}`;
}

function selectOption(option: LanguagePickerOption): void {
  open.value = false;

  if (option.value === modelValue) return;

  emit("update:modelValue", option.value);
  emit("select", option);
}

function closeMenu(): void {
  open.value = false;
}
</script>

<template>
  <Popover v-model:open="open">
    <PopoverTrigger as-child>
      <Button
        :id="`${id}-trigger`"
        type="button"
        :variant="triggerVariant"
        :size="triggerSize"
        :disabled="disabled"
        :aria-label="triggerAriaLabel"
        :aria-expanded="open"
        :class="[
          'group min-w-0 justify-between gap-2 font-medium',
          compact ? 'rounded-full px-2.5' : 'px-3',
          triggerClass,
        ]"
      >
        <span class="flex min-w-0 items-center gap-2">
          <LanguageFlag
            v-if="selected"
            :flag-code="selected.flagCode"
            :short-label="selected.shortLabel"
            :size="compact ? 'sm' : 'md'"
          />
          <slot v-else name="placeholder-icon" />
          <span
            :class="[
              'truncate',
              !selected && 'text-muted-foreground',
              compact && 'text-xs uppercase tracking-wide',
            ]"
          >
            {{ selected ? (compact ? selected.shortLabel : selected.label) : placeholder }}
          </span>
        </span>
        <ChevronDown
          class="size-3.5 shrink-0 text-muted-foreground transition-transform duration-200 group-data-[state=open]:rotate-180"
        />
      </Button>
    </PopoverTrigger>

    <PopoverContent
      :align="align"
      :side-offset="6"
      :class="['w-(--reka-popover-trigger-width) min-w-56 overflow-hidden p-0', contentClass]"
    >
      <Command v-if="mode === 'select'" class="max-h-80">
        <CommandInput v-if="searchable" :placeholder="searchPlaceholder" />
        <CommandList>
          <CommandEmpty>{{ emptyLabel }}</CommandEmpty>
          <CommandGroup>
            <CommandItem
              v-for="option in options"
              :id="optionDomId(option)"
              :key="option.value"
              :value="`${option.label} ${option.value}`"
              class="min-h-10 gap-2.5 px-3"
              @select="selectOption(option)"
            >
              <LanguageFlag :flag-code="option.flagCode" :short-label="option.shortLabel" />
              <span class="min-w-0 flex-1 truncate">{{ option.label }}</span>
              <span aria-hidden="true" class="sr-only">
                {{ option.value }} {{ option.languageTag }}
              </span>
              <span class="text-[0.68rem] font-medium uppercase text-muted-foreground">
                {{ option.shortLabel }}
              </span>
              <Check
                :class="[
                  'size-4 text-primary transition-opacity',
                  option.value === modelValue ? 'opacity-100' : 'opacity-0',
                ]"
              />
            </CommandItem>
          </CommandGroup>
        </CommandList>
      </Command>

      <ul v-else :aria-label="label" class="max-h-80 overflow-y-auto p-1.5">
        <li v-for="option in options" :key="option.value">
          <div
            v-if="option.value === modelValue"
            :id="optionDomId(option)"
            :lang="option.languageTag"
            aria-current="page"
            class="flex min-h-10 items-center gap-2.5 rounded-md bg-accent px-2.5 py-2 text-sm font-medium text-accent-foreground"
          >
            <LanguageFlag :flag-code="option.flagCode" :short-label="option.shortLabel" />
            <span class="min-w-0 flex-1 truncate">{{ option.label }}</span>
            <Check class="size-4 shrink-0 text-primary" />
          </div>
          <LiveLink
            v-else-if="option.href"
            :id="optionDomId(option)"
            :to="option.href"
            :lang="option.languageTag"
            :hreflang="option.languageTag"
            class="flex min-h-10 items-center gap-2.5 rounded-md px-2.5 py-2 text-sm font-medium text-foreground/80 outline-none transition-colors hover:bg-accent hover:text-accent-foreground focus-visible:bg-accent focus-visible:text-accent-foreground"
            @click="closeMenu"
          >
            <LanguageFlag :flag-code="option.flagCode" :short-label="option.shortLabel" />
            <span class="min-w-0 flex-1 truncate">{{ option.label }}</span>
            <span class="text-[0.68rem] font-medium uppercase text-muted-foreground">
              {{ option.shortLabel }}
            </span>
          </LiveLink>
        </li>
      </ul>
    </PopoverContent>
  </Popover>
</template>
