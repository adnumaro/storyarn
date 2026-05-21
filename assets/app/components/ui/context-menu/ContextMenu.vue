<script setup lang="ts">
import { ContextMenuRoot, useForwardPropsEmits } from "reka-ui";

const props = defineProps<{
  pressOpenDelay?: number;
  dir?: "ltr" | "rtl";
  modal?: boolean;
}>();
const emits = defineEmits<{
  "update:open": [value: boolean];
}>();

const forwarded = useForwardPropsEmits(props, emits);
</script>

<template>
  <ContextMenuRoot data-slot="context-menu" v-bind="forwarded">
    <slot />
  </ContextMenuRoot>
</template>
