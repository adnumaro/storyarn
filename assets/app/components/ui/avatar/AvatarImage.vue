<script setup lang="ts">
import type { Component } from "vue";
import { AvatarImage, type AsTag } from "reka-ui";

const props = defineProps<{
  src: string;
  referrerPolicy?:
    | ""
    | "no-referrer"
    | "no-referrer-when-downgrade"
    | "origin"
    | "origin-when-cross-origin"
    | "same-origin"
    | "strict-origin"
    | "strict-origin-when-cross-origin"
    | "unsafe-url";
  crossOrigin?: "" | "anonymous" | "use-credentials";
  asChild?: boolean;
  as?: AsTag | Component;
}>();
</script>

<template>
  <AvatarImage v-bind="props" class="aspect-square size-full">
    <slot />
  </AvatarImage>
</template>
