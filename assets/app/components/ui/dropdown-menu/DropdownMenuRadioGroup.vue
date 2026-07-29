<script setup lang="ts">
import type { Component } from "vue";
import { DropdownMenuRadioGroup, useForwardProps, type AcceptableValue, type AsTag } from "reka-ui";

const props = defineProps<{
  modelValue?: string;
  asChild?: boolean;
  as?: AsTag | Component;
}>();
const emit = defineEmits<{
  "update:modelValue": [value: string];
}>();

const forwarded = useForwardProps(props);

function updateModelValue(value: AcceptableValue) {
  if (typeof value === "string") emit("update:modelValue", value);
}
</script>

<template>
  <DropdownMenuRadioGroup
    data-slot="dropdown-menu-radio-group"
    v-bind="forwarded"
    @update:model-value="updateModelValue"
  >
    <slot />
  </DropdownMenuRadioGroup>
</template>
