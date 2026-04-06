<script setup lang="ts">
import { ContextMenuSub, useForwardPropsEmits } from "reka-ui";

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
  <ContextMenuSub data-slot="context-menu-sub" v-bind="forwarded">
    <slot />
  </ContextMenuSub>
</template>
