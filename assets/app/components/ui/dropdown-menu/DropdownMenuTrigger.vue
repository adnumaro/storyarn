<script setup lang="ts">
import type { Component } from "vue";
import { DropdownMenuTrigger, useForwardProps, type AsTag } from "reka-ui";

const props = defineProps<{
  disabled?: boolean;
  asChild?: boolean;
  as?: AsTag | Component;
}>();

const forwardedProps = useForwardProps(props);
</script>

<template>
  <DropdownMenuTrigger data-slot="dropdown-menu-trigger" v-bind="forwardedProps">
    <slot />
  </DropdownMenuTrigger>
</template>
