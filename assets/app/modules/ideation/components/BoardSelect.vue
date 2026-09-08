<script setup lang="ts">
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@components/ui/select";
const {
  label,
  options,
  disabled = false,
} = defineProps<{
  label: string;
  options: { value: string; label: string }[];
  disabled?: boolean;
}>();
const model = defineModel<string>({ required: true });
</script>
<template>
  <Select v-model="model" :disabled="disabled">
    <SelectTrigger :aria-label="label" class="w-full"
      ><SelectValue :placeholder="label"
    /></SelectTrigger>
    <SelectContent
      ><SelectItem v-for="option in options" :key="option.value" :value="option.value">{{
        option.label
      }}</SelectItem></SelectContent
    >
  </Select>
</template>
