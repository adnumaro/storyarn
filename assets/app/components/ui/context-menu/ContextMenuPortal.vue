<script setup lang="ts">
import { ContextMenuPortal } from "reka-ui";

const props = defineProps<{
  to?: string | HTMLElement;
  disabled?: boolean;
  defer?: boolean;
  forceMount?: boolean;
}>();
</script>

<template>
  <ContextMenuPortal data-slot="context-menu-portal" v-bind="props">
    <slot />
  </ContextMenuPortal>
</template>
