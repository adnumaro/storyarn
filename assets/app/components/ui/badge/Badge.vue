<script setup lang="ts">
import type { Component, HTMLAttributes } from "vue";
import { reactiveOmit } from "@vueuse/core";
import { Primitive, type AsTag } from "reka-ui";
import { cn } from "@utils/utils";
import { badgeVariants } from ".";

const props = defineProps<{
  asChild?: boolean;
  as?: AsTag | Component;
  variant?: "default" | "secondary" | "destructive" | "outline";
  class?: HTMLAttributes["class"];
}>();

const delegatedProps = reactiveOmit(props, "class");
</script>

<template>
  <Primitive
    data-slot="badge"
    :class="cn(badgeVariants({ variant }), props.class)"
    v-bind="delegatedProps"
  >
    <slot />
  </Primitive>
</template>
