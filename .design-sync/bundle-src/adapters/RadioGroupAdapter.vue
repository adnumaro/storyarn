<script setup lang="ts">
/** Props-driven facade over the app's RadioGroup compound. */
import { useId } from "vue";
import { Label } from "@components/ui/label";
import { RadioGroup, RadioGroupItem } from "@components/ui/radio-group";

export interface RadioOption {
  value: string;
  label: string;
  disabled?: boolean;
}

const { options = [], disabled = false } = defineProps<{
  options?: RadioOption[];
  disabled?: boolean;
  class?: string;
}>();

const modelValue = defineModel<string>();

// Per-instance prefix: two groups sharing option values must not share ids.
const uid = useId();
</script>

<template>
  <RadioGroup v-model="modelValue" :disabled="disabled" :class="$props.class">
    <div v-for="opt in options" :key="opt.value" class="flex items-center gap-2">
      <RadioGroupItem :id="`${uid}-${opt.value}`" :value="opt.value" :disabled="opt.disabled" />
      <Label :for="`${uid}-${opt.value}`">{{ opt.label }}</Label>
    </div>
  </RadioGroup>
</template>
