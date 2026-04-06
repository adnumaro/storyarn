<script setup lang="ts">
import { TooltipRoot, useForwardPropsEmits } from "reka-ui";

const props = defineProps<{
  defaultOpen?: boolean;
  open?: boolean;
  delayDuration?: number;
  disableHoverableContent?: boolean;
  disableClosingTrigger?: boolean;
  disabled?: boolean;
  ignoreNonKeyboardFocus?: boolean;
}>();
const emits = defineEmits<{
  "update:open": [value: boolean];
}>();

const forwarded = useForwardPropsEmits(props, emits);
</script>

<template>
  <TooltipRoot v-slot="slotProps" data-slot="tooltip" v-bind="forwarded">
    <slot v-bind="slotProps" />
  </TooltipRoot>
</template>
