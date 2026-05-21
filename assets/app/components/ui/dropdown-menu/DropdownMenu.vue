<script setup lang="ts">
import { DropdownMenuRoot, useForwardPropsEmits } from "reka-ui";

const props = defineProps<{
  defaultOpen?: boolean;
  open?: boolean;
  dir?: "ltr" | "rtl";
  modal?: boolean;
}>();
const emits = defineEmits<{
  "update:open": [value: boolean];
}>();

const forwarded = useForwardPropsEmits(props, emits);
</script>

<template>
  <DropdownMenuRoot v-slot="slotProps" data-slot="dropdown-menu" v-bind="forwarded">
    <slot v-bind="slotProps" />
  </DropdownMenuRoot>
</template>
