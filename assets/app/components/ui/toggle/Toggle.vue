<script setup lang="ts">
import type { Component, HTMLAttributes } from "vue";
import { reactiveOmit } from "@vueuse/core";
import { Toggle, useForwardPropsEmits, type AsTag } from "reka-ui";
import { cn } from "../../../shared/utils/utils";
import { toggleVariants } from ".";

const props = defineProps<{
  defaultValue?: boolean;
  modelValue?: boolean | null;
  disabled?: boolean;
  asChild?: boolean;
  as?: AsTag | Component;
  name?: string;
  required?: boolean;
  class?: HTMLAttributes["class"];
  variant?: "default" | "outline";
  size?: "default" | "sm" | "lg";
}>();

const emits = defineEmits<{
  "update:modelValue": [value: boolean];
}>();

const delegatedProps = reactiveOmit(props, "class", "size", "variant");
const forwarded = useForwardPropsEmits(delegatedProps, emits);
</script>

<template>
  <Toggle
    v-slot="slotProps"
    data-slot="toggle"
    v-bind="forwarded"
    :class="cn(toggleVariants({ variant, size }), props.class)"
  >
    <slot v-bind="slotProps" />
  </Toggle>
</template>
