<script setup lang="ts">
import type { Component } from "vue";
import { DropdownMenuRadioGroup, useForwardPropsEmits, type AsTag } from "reka-ui";

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
  <DropdownMenuRadioGroup data-slot="dropdown-menu-radio-group" v-bind="forwarded">
    <slot />
  </DropdownMenuRadioGroup>
</template>
