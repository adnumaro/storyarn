<script setup lang="ts">
import type { Component } from "vue";
import { DialogClose, type AsTag } from "reka-ui";

const props = defineProps<{
  asChild?: boolean;
  as?: AsTag | Component;
}>();
</script>

<template>
  <DialogClose data-slot="sheet-close" v-bind="props">
    <slot />
  </DialogClose>
</template>
