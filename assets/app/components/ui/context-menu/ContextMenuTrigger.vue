<script setup lang="ts">
import type { Component } from "vue";
import { ContextMenuTrigger, useForwardProps, type AsTag } from "reka-ui";

const props = defineProps<{
  disabled?: boolean;
  asChild?: boolean;
  as?: AsTag | Component;
}>();

const forwardedProps = useForwardProps(props);
</script>

<template>
  <ContextMenuTrigger data-slot="context-menu-trigger" v-bind="forwardedProps">
    <slot />
  </ContextMenuTrigger>
</template>
