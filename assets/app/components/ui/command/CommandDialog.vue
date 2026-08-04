<script setup lang="ts">
import { reactiveOmit } from "@vueuse/core";
import { useForwardPropsEmits } from "reka-ui";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@components/ui/dialog";
import Command from "./Command.vue";

const props = defineProps<{
  open?: boolean;
  defaultOpen?: boolean;
  modal?: boolean;
  title?: string;
  description?: string;
  disableFilter?: boolean;
}>();
const emit = defineEmits<{
  "update:open": [value: boolean];
  escapeKeyDown: [event: KeyboardEvent];
}>();

const dialogProps = reactiveOmit(props, "disableFilter");
const forwarded = useForwardPropsEmits(dialogProps, emit);
</script>

<template>
  <Dialog v-slot="slotProps" v-bind="forwarded">
    <DialogContent class="overflow-hidden p-0" @escape-key-down="emit('escapeKeyDown', $event)">
      <DialogHeader class="sr-only">
        <DialogTitle>{{ title }}</DialogTitle>
        <DialogDescription>{{ description }}</DialogDescription>
      </DialogHeader>
      <Command :disable-filter="props.disableFilter">
        <slot v-bind="slotProps" />
      </Command>
    </DialogContent>
  </Dialog>
</template>
