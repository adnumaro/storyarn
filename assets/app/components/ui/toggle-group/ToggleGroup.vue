<script setup lang="ts">
import type { Component, HTMLAttributes } from "vue";
import { reactiveOmit } from "@vueuse/core";
import { ToggleGroupRoot, useForwardProps, type AcceptableValue, type AsTag } from "reka-ui";
import { provide } from "vue";
import { cn } from "../../../shared/utils/utils";

const props = defineProps<{
  rovingFocus?: boolean;
  disabled?: boolean;
  orientation?: "horizontal" | "vertical";
  dir?: "ltr" | "rtl";
  loop?: boolean;
  asChild?: boolean;
  as?: AsTag | Component;
  name?: string;
  required?: boolean;
  type?: "single" | "multiple";
  modelValue?: string | string[];
  defaultValue?: string | string[];
  class?: HTMLAttributes["class"];
  variant?: "default" | "outline";
  size?: "default" | "xs" | "sm" | "lg";
  spacing?: number;
}>();

const emit = defineEmits<{
  "update:modelValue": [value: string | string[]];
}>();

provide("toggleGroup", {
  variant: props.variant,
  size: props.size,
  spacing: props.spacing,
});

const delegatedProps = reactiveOmit(props, "class", "size", "variant", "spacing");
const forwarded = useForwardProps(delegatedProps);

function updateModelValue(value: AcceptableValue | AcceptableValue[]) {
  if (typeof value === "string") {
    emit("update:modelValue", value);
    return;
  }

  if (Array.isArray(value) && value.every((item) => typeof item === "string")) {
    emit("update:modelValue", value as string[]);
  }
}
</script>

<template>
  <ToggleGroupRoot
    v-slot="slotProps"
    data-slot="toggle-group"
    :data-size="size"
    :data-variant="variant"
    :data-spacing="spacing"
    :style="{
      '--gap': spacing,
    }"
    v-bind="forwarded"
    @update:model-value="updateModelValue"
    :class="
      cn(
        'group/toggle-group flex w-fit items-center gap-[--spacing(var(--gap))] rounded-md data-[spacing=default]:data-[variant=outline]:shadow-xs',
        props.class,
      )
    "
  >
    <slot v-bind="slotProps" />
  </ToggleGroupRoot>
</template>
