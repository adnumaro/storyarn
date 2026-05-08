<script setup lang="ts">
import type { Component, HTMLAttributes } from "vue";
import { reactiveOmit } from "@vueuse/core";
import { DialogDescription, useForwardProps, type AsTag } from "reka-ui";
import { cn } from "../../../shared/utils/utils";

const props = defineProps<{
  asChild?: boolean;
  as?: AsTag | Component;
  class?: HTMLAttributes["class"];
}>();

const delegatedProps = reactiveOmit(props, "class");

const forwardedProps = useForwardProps(delegatedProps);
</script>

<template>
  <DialogDescription
    data-slot="dialog-description"
    v-bind="forwardedProps"
    :class="cn('text-muted-foreground text-sm', props.class)"
  >
    <slot />
  </DialogDescription>
</template>
