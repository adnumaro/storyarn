<script setup lang="ts">
import type { Component } from "vue";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@components/ui/select";
import { useLive } from "../../../shared/composables/useLive";

interface SelectOption {
  id?: string | number;
  value?: string | number;
  name?: string;
  label?: string;
}

const {
  label = "",
  icon = null,
  options,
  value = "",
  placeholder = "Select...",
  disabled = false,
  event = null,
  paramKey = "value",
} = defineProps<{
  label?: string;
  icon?: Component | null;
  options: SelectOption[];
  value?: string | number;
  placeholder?: string;
  disabled?: boolean;
  event?: string | null;
  paramKey?: string;
}>();

const emit = defineEmits<{
  update: [value: string];
}>();
const live = useLive();

function onChange(v: string | string[]) {
  const val = Array.isArray(v) ? v[0] : v;
  emit("update", val);
  if (event) {
    live.pushEvent(event, { [paramKey]: val });
  }
}
</script>

<template>
  <div class="space-y-1.5">
    <label
      v-if="label"
      class="block text-xs font-medium text-foreground/70 flex items-center gap-1"
    >
      <component :is="icon" v-if="icon" class="size-3" />
      {{ label }}
    </label>
    <Select :model-value="String(value)" :disabled="disabled" @update:model-value="onChange">
      <SelectTrigger class="w-full h-8 text-xs">
        <SelectValue :placeholder="placeholder" />
      </SelectTrigger>
      <SelectContent>
        <SelectItem
          v-for="opt in options"
          :key="opt.id ?? opt.value"
          :value="String(opt.id ?? opt.value)"
        >
          {{ opt.name ?? opt.label }}
        </SelectItem>
      </SelectContent>
    </Select>
  </div>
</template>
