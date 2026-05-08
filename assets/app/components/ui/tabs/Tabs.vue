<script setup lang="ts">
import type { Component, HTMLAttributes } from "vue";
import { reactiveOmit } from "@vueuse/core";
import { TabsRoot, useForwardPropsEmits, type AsTag } from "reka-ui";
import { cn } from "../../../shared/utils/utils";

const props = defineProps<{
  defaultValue?: string | number;
  orientation?: "horizontal" | "vertical";
  dir?: "ltr" | "rtl";
  activationMode?: "automatic" | "manual";
  modelValue?: string | number;
  unmountOnHide?: boolean;
  asChild?: boolean;
  as?: AsTag | Component;
  class?: HTMLAttributes["class"];
}>();
const emits = defineEmits<{
  "update:modelValue": [value: string | number];
}>();

const delegatedProps = reactiveOmit(props, "class");
const forwarded = useForwardPropsEmits(delegatedProps, emits);
</script>

<template>
  <TabsRoot
    v-slot="slotProps"
    data-slot="tabs"
    v-bind="forwarded"
    :class="cn('flex flex-col gap-2', props.class)"
  >
    <slot v-bind="slotProps" />
  </TabsRoot>
</template>
