<script setup lang="ts">
import type { Component } from "vue";
import { ContextMenuRadioGroup, useForwardProps, type AcceptableValue, type AsTag } from "reka-ui";

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
  <ContextMenuRadioGroup
    data-slot="context-menu-radio-group"
    v-bind="forwarded"
    @update:model-value="updateModelValue"
  >
    <slot />
  </ContextMenuRadioGroup>
</template>
