<script setup lang="ts">
import { PopoverRoot, useForwardPropsEmits } from "reka-ui";

const props = defineProps<{
  defaultOpen?: boolean;
  open?: boolean;
  modal?: boolean;
}>();
const emits = defineEmits<{
  "update:open": [value: boolean];
}>();

const forwarded = useForwardPropsEmits(props, emits);
</script>

<template>
  <PopoverRoot v-slot="slotProps" data-slot="popover" v-bind="forwarded">
    <slot v-bind="slotProps" />
  </PopoverRoot>
</template>
