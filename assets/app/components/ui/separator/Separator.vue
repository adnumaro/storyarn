<script setup lang="ts">
import type { Component, HTMLAttributes } from "vue";
import { reactiveOmit } from "@vueuse/core";
import { Separator, type AsTag } from "reka-ui";
import { cn } from "../../../shared/utils/utils";

const props = defineProps<{
  orientation?: "horizontal" | "vertical";
  decorative?: boolean;
  asChild?: boolean;
  as?: AsTag | Component;
  class?: HTMLAttributes["class"];
}>();

const delegatedProps = reactiveOmit(props, "class");
</script>

<template>
  <Separator
    data-slot="separator"
    v-bind="delegatedProps"
    :class="
      cn(
        'bg-border shrink-0 data-[orientation=horizontal]:h-px data-[orientation=horizontal]:w-full data-[orientation=vertical]:h-full data-[orientation=vertical]:w-px',
        props.class,
      )
    "
  />
</template>
