<script setup lang="ts">
import type { Component } from "vue";
import { CollapsibleRoot, useForwardPropsEmits, type AsTag } from "reka-ui";

const props = defineProps<{
  defaultOpen?: boolean;
  open?: boolean;
  disabled?: boolean;
  unmountOnHide?: boolean;
  asChild?: boolean;
  as?: AsTag | Component;
}>();
const emits = defineEmits<{
  "update:open": [value: boolean];
}>();

const forwarded = useForwardPropsEmits(props, emits);
</script>

<template>
  <CollapsibleRoot v-slot="slotProps" data-slot="collapsible" v-bind="forwarded">
    <slot v-bind="slotProps" />
  </CollapsibleRoot>
</template>
