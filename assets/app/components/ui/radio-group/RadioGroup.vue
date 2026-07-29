<script setup lang="ts">
import type { Component, HTMLAttributes } from "vue";
import { reactiveOmit } from "@vueuse/core";
import { RadioGroupRoot, useForwardProps, type AcceptableValue, type AsTag } from "reka-ui";
import { cn } from "../../../shared/utils/utils";

const props = defineProps<{
  modelValue?: string;
  defaultValue?: string;
  disabled?: boolean;
  orientation?: "horizontal" | "vertical";
  dir?: "ltr" | "rtl";
  loop?: boolean;
  asChild?: boolean;
  as?: AsTag | Component;
  name?: string;
  required?: boolean;
  class?: HTMLAttributes["class"];
}>();
const emit = defineEmits<{
  "update:modelValue": [value: string];
}>();

const delegatedProps = reactiveOmit(props, "class");

const forwarded = useForwardProps(delegatedProps);

function updateModelValue(value: AcceptableValue) {
  if (typeof value === "string") emit("update:modelValue", value);
}
</script>

<template>
  <RadioGroupRoot
    v-slot="slotProps"
    data-slot="radio-group"
    :class="cn('grid gap-3', props.class)"
    v-bind="forwarded"
    @update:model-value="updateModelValue"
  >
    <slot v-bind="slotProps" />
  </RadioGroupRoot>
</template>
