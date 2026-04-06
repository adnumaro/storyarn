<script setup lang="ts">
import { DropdownMenuSub, useForwardPropsEmits } from "reka-ui";

const props = defineProps<{
  defaultOpen?: boolean;
  open?: boolean;
}>();
const emits = defineEmits<{
  "update:open": [value: boolean];
}>();

const forwarded = useForwardPropsEmits(props, emits);
</script>

<template>
  <DropdownMenuSub v-slot="slotProps" data-slot="dropdown-menu-sub" v-bind="forwarded">
    <slot v-bind="slotProps" />
  </DropdownMenuSub>
</template>
