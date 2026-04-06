<script setup lang="ts">
import type { Component } from "vue";
import { ContextMenuGroup, type AsTag } from "reka-ui";

const props = defineProps<{
  asChild?: boolean;
  as?: AsTag | Component;
}>();
</script>

<template>
  <ContextMenuGroup data-slot="context-menu-group" v-bind="props">
    <slot />
  </ContextMenuGroup>
</template>
