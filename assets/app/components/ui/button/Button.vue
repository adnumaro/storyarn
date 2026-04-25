<script setup lang="ts">
import type { Component, HTMLAttributes } from "vue";
import { Primitive, type AsTag } from "reka-ui";
import { cn } from "@utils/utils";
import { buttonVariants } from ".";

const props = withDefaults(
  defineProps<{
    variant?: "default" | "destructive" | "outline" | "secondary" | "ghost" | "link";
    size?: "default" | "xs" | "sm" | "lg" | "icon" | "icon-xs" | "icon-sm" | "icon-lg";
    class?: HTMLAttributes["class"];
    asChild?: boolean;
    as?: AsTag | Component;
  }>(),
  { as: "button" },
);
</script>

<template>
  <Primitive
    data-slot="button"
    :data-variant="variant"
    :data-size="size"
    :as="as"
    :as-child="asChild"
    :class="cn(buttonVariants({ variant, size }), props.class)"
  >
    <slot />
  </Primitive>
</template>
