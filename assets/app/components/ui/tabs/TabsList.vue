<script setup lang="ts">
import type { Component, HTMLAttributes } from "vue";
import { reactiveOmit } from "@vueuse/core";
import { TabsList, type AsTag } from "reka-ui";
import { cn } from "@utils/utils";

const props = defineProps<{
  loop?: boolean;
  asChild?: boolean;
  as?: AsTag | Component;
  class?: HTMLAttributes["class"];
}>();

const delegatedProps = reactiveOmit(props, "class");
</script>

<template>
  <TabsList
    data-slot="tabs-list"
    v-bind="delegatedProps"
    :class="
      cn(
        'bg-muted text-muted-foreground inline-flex h-9 w-fit items-center justify-center rounded-md p-0.75',
        props.class,
      )
    "
  >
    <slot />
  </TabsList>
</template>
