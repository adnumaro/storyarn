<script setup lang="ts">
import type { Component } from "vue";
import { ContextMenuRadioGroup, useForwardPropsEmits, type AsTag } from "reka-ui";

const props = defineProps<{
  modelValue?: string;
  asChild?: boolean;
  as?: AsTag | Component;
}>();
const emits = defineEmits<{
  "update:modelValue": [value: string];
}>();

const forwarded = useForwardPropsEmits(props, emits);
</script>

<template>
  <ContextMenuRadioGroup data-slot="context-menu-radio-group" v-bind="forwarded">
    <slot />
  </ContextMenuRadioGroup>
</template>
