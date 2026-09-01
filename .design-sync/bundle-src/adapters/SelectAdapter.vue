<script setup lang="ts">
/**
 * Props-driven facade over the app's Select compound (React can't compose
 * reka-ui subcomponents across the wrap boundary — provide/inject would split).
 */
import {
  Select,
  SelectContent,
  SelectGroup,
  SelectItem,
  SelectLabel,
  SelectSeparator,
  SelectTrigger,
  SelectValue,
} from "@components/ui/select";
import { computed } from "vue";
import { useContentThemeClass } from "./useDsTheme";

export interface SelectOption {
  value: string;
  label: string;
  disabled?: boolean;
}

export interface SelectOptionGroup {
  label: string;
  options: SelectOption[];
}

const {
  options = [],
  placeholder,
  disabled = false,
  size = "default",
} = defineProps<{
  options?: (SelectOption | SelectOptionGroup)[];
  placeholder?: string;
  disabled?: boolean;
  size?: "default" | "sm";
  class?: string;
}>();

const modelValue = defineModel<string>();

const groups = computed(() =>
  options.map((o) => ("options" in o ? o : { label: null, options: [o] })),
);

const themeClass = useContentThemeClass();
</script>

<template>
  <Select v-model="modelValue" :disabled="disabled">
    <SelectTrigger :size="size" :class="$props.class">
      <SelectValue :placeholder="placeholder" />
    </SelectTrigger>
    <SelectContent :class="themeClass">
      <template v-for="(group, gi) in groups" :key="gi">
        <SelectSeparator v-if="gi > 0 && group.label" />
        <SelectGroup>
          <SelectLabel v-if="group.label">{{ group.label }}</SelectLabel>
          <SelectItem
            v-for="opt in group.options"
            :key="opt.value"
            :value="opt.value"
            :disabled="opt.disabled"
          >
            {{ opt.label }}
          </SelectItem>
        </SelectGroup>
      </template>
    </SelectContent>
  </Select>
</template>
